from __future__ import annotations
import os
import sys
import time
import subprocess
from pathlib import Path
from uuid import uuid4
from typing import Optional

import torch

MEDIA_ROOT = Path("C:/lipread_media")
TMP_DIR = MEDIA_ROOT / "tmp"
TMP_DIR.mkdir(parents=True, exist_ok=True)

BASE_DIR = Path(__file__).resolve().parents[1]
AI_DIR = BASE_DIR / "ai_inference"
CHAPLIN_DIR = AI_DIR / "chaplin"
CONFIG_PATH = CHAPLIN_DIR / "configs" / "LRS3_V_WER19.1.ini"

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
_pipeline = None

def _ensure_ffmpeg():
    try:
        subprocess.run(
            ["ffmpeg", "-version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except Exception as e:
        raise RuntimeError("ffmpeg not found. Install it and ensure it's on PATH.") from e


def _normalize_video(src: Path) -> Path:
    _ensure_ffmpeg()

    if not src.exists():
        raise FileNotFoundError(f"Input video not found: {src}")

    dst = TMP_DIR / f"{uuid4().hex[:8]}.mp4"

    cmd = [
        "ffmpeg",
        "-y",
        "-loglevel", "error",
        "-i", str(src),
        "-r", "25",
        "-pix_fmt", "yuv420p",
        "-f", "mp4",
        str(dst),
    ]
    subprocess.run(cmd, check=True)
    return dst


def _load_pipeline():
    global _pipeline

    if _pipeline is not None:
        return _pipeline

    if not CONFIG_PATH.exists():
        raise FileNotFoundError(f"Chaplin config not found: {CONFIG_PATH}")

    if str(CHAPLIN_DIR) not in sys.path:
        sys.path.insert(0, str(CHAPLIN_DIR))

    from chaplin.pipelines.pipeline import InferencePipeline

    _pipeline = InferencePipeline(
        config_filename=str(CONFIG_PATH),
        device=DEVICE,
        face_track=True,
        detector="mediapipe",
    )
    return _pipeline

def transcribe_video(video_path: str | Path, lesson_id: str | None = None) -> dict:
    t0 = time.time()

    video_path = Path(video_path)
    if not video_path.exists():
        raise FileNotFoundError(f"Video not found: {video_path}")

    norm_path = _normalize_video(video_path)
    pipe = _load_pipeline()

    old_cwd = os.getcwd()
    try:
        os.chdir(str(CHAPLIN_DIR))

        landmarks = pipe.process_landmarks(str(norm_path), landmarks_filename=None)
        data = pipe.dataloader.load_data(str(norm_path), landmarks)
        transcript = pipe.model.infer(data)

    finally:
        os.chdir(old_cwd)
        try:
            norm_path.unlink(missing_ok=True)  # auto-cleanup
        except:
            pass

    latency_ms = int(round((time.time() - t0) * 1000))

    return {
        "lessonId": lesson_id,
        "transcript": transcript.strip(),
        "confidence": None,
        "words": [],
        "visemes": [],
        "latencyMs": latency_ms,
    }

if __name__ == "__main__":
    test_file = MEDIA_ROOT / "uploads" / "sample.mp4"
    if test_file.exists():
        print(transcribe_video(test_file))
    else:
        print("No sample video found.")