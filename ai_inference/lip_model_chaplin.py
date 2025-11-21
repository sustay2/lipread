"""
Chaplin / Auto-AVSR wrapper for Lip Read.

- Uses the LRS3_V_WER19.1 visual-only model via InferencePipeline.
- Accepts a video file path (from your Flutter upload or local test).
- Normalizes the video with ffmpeg.
- Returns: { lessonId, transcript, confidence, words, visemes, latencyMs }

Requirements:
- chaplin_repo cloned inside ai_inference/
- ffmpeg in PATH
- mediapipe, opencv-python, etc. installed.
"""

from __future__ import annotations

import os
import sys
import time
import subprocess
from pathlib import Path
from uuid import uuid4
from typing import Optional

import torch

# ---------- Paths & device ----------

# project root (lipread/)
BASE_DIR = Path(__file__).resolve().parents[1]

# chaplin repo: lipread/ai_inference/chaplin_repo
CHAPLIN_DIR = BASE_DIR / "ai_inference" / "chaplin_repo"
CONFIG_PATH = CHAPLIN_DIR / "configs" / "LRS3_V_WER19.1.ini"

# Make chaplin_repo's "pipelines" package visible as top-level "pipelines"
# so that `from pipelines.model import AVSR` inside pipeline.py works.
if str(CHAPLIN_DIR) not in sys.path:
    sys.path.insert(0, str(CHAPLIN_DIR))

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

# tmp dir for normalized videos
TMP_DIR = BASE_DIR / "ai_inference" / "chaplin_tmp"
TMP_DIR.mkdir(parents=True, exist_ok=True)

_pipeline = None  # type: Optional["InferencePipeline"]


# ---------- Helpers ----------

def _ensure_ffmpeg() -> None:
    """Check ffmpeg availability."""
    try:
        subprocess.run(
            ["ffmpeg", "-version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except Exception as e:
        raise RuntimeError(
            "ffmpeg not found. Ensure it's installed and in PATH."
        ) from e


def _normalize_video(src: Path) -> Path:
    """
    Convert input to a safe MP4:
    - 25 fps
    - yuv420p
    - mp4 container
    """
    _ensure_ffmpeg()

    if not src.exists():
        raise FileNotFoundError(f"Input video not found: {src}")

    dst = TMP_DIR / f"{uuid4().hex[:8]}.mp4"

    cmd = [
        "ffmpeg",
        "-y",
        "-loglevel",
        "error",
        "-i",
        str(src),
        "-r",
        "25",
        "-pix_fmt",
        "yuv420p",
        "-f",
        "mp4",
        str(dst),
    ]
    subprocess.run(cmd, check=True)
    return dst


def _load_pipeline():
    """
    Lazily initialize the InferencePipeline.
    Uses the visual-only LRS3_V_WER19.1 config.
    """
    global _pipeline

    if _pipeline is not None:
        return _pipeline

    if not CONFIG_PATH.exists():
        raise FileNotFoundError(
            f"Chaplin/Auto-AVSR config not found: {CONFIG_PATH}"
        )

    # Import AFTER sys.path adjustment so that
    # chaplin_repo/pipelines/pipeline.py can do `from pipelines.model import AVSR`.
    from chaplin_repo.pipelines.pipeline import InferencePipeline

    _pipeline = InferencePipeline(
        config_filename=str(CONFIG_PATH),
        device=DEVICE,
        face_track=True,
        detector="mediapipe",
    )

    return _pipeline


# ---------- Public API ----------

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
            norm_path.unlink(missing_ok=True)
        except Exception:
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


# ---------- Local debug ----------

if __name__ == "__main__":
    sample = BASE_DIR / "media" / "uploads" / "sample_001.mp4"
    if sample.exists():
        out = transcribe_video(sample, lesson_id="debug_sample")
        print(out)
    else:
        print(f"Sample not found: {sample}")