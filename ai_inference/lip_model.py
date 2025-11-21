"""
Backends:
  1. Chaplin / Auto-AVSR (visual-only, pretrained)  [primary if available]
  2. Legacy GRID/Lombard CTC model                  [fallback]

Exports a single function:

    transcribe_video(video_path: str|Path, lesson_id: str|None) -> dict

Return format (stable for Flutter app):

    {
      "lessonId": str|None,
      "transcript": str,
      "confidence": float|None,
      "words": [],
      "visemes": [],
      "latencyMs": int
    }

Selection:
  - Use env LIP_MODEL_BACKEND to force:
        "chaplin" | "ctc"
  - If unset: try chaplin, else fallback to ctc.
"""
from __future__ import annotations
import os
import time
import logging
import subprocess
from pathlib import Path
from typing import Optional, List
from lip_model_chaplin import transcribe_video as chaplin_transcribe

import cv2
import numpy as np
import torch

import builtins
_builtin_open = open

def utf8_open(file, mode="r", *args, **kwargs):
    if "b" not in mode and "encoding" not in kwargs:
        kwargs["encoding"] = "utf-8"
    return _builtin_open(file, mode, *args, **kwargs)

builtins.open = utf8_open

AI_DIR = Path(__file__).resolve().parent
PROJ_ROOT = AI_DIR.parent
TMP_DIR = AI_DIR / "tmp_infer"
TMP_DIR.mkdir(parents=True, exist_ok=True)

BACKEND_ENV = os.getenv("LIP_MODEL_BACKEND", "").strip().lower()
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

_chaplin_ok = None
_chaplin_pipeline = None
_ctc_model: Optional[torch.nn.Module] = None


def _ensure_ffmpeg():
    try:
        subprocess.run(
            ["ffmpeg", "-version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except Exception as e:
        raise RuntimeError(
            "ffmpeg not found. Install it and ensure it's on PATH."
        ) from e


def _normalize_video(src: Path) -> Path:
    _ensure_ffmpeg()

    if not src.exists():
        raise FileNotFoundError(f"Input video not found: {src}")

    out = TMP_DIR / f"norm_{int(time.time()*1000)}.mp4"
    cmd = [
        "ffmpeg",
        "-y",
        "-loglevel",
        "error",
        "-i", str(src),
        "-r", "25",
        "-pix_fmt", "yuv420p",
        "-f", "mp4",
        str(out),
    ]
    subprocess.run(cmd, check=True)
    return out

def _chaplin_available() -> bool:
    global _chaplin_ok
    if _chaplin_ok is not None:
        return _chaplin_ok

    try:
        chaplin_dir = AI_DIR / "chaplin_repo"
        cfg = chaplin_dir / "configs" / "LRS3_V_WER19.1.ini"
        if not chaplin_dir.is_dir() or not cfg.is_file():
            _chaplin_ok = False
            return _chaplin_ok

        from chaplin_repo.pipelines.pipeline import InferencePipeline
        _chaplin_ok = True
    except Exception:
        _chaplin_ok = False

    return _chaplin_ok


def _get_chaplin_pipeline():
    global _chaplin_pipeline

    if _chaplin_pipeline is not None:
        return _chaplin_pipeline

    from chaplin_repo.pipelines.pipeline import InferencePipeline

    chaplin_dir = AI_DIR / "chaplin_repo"
    cfg = chaplin_dir / "configs" / "LRS3_V_WER19.1.ini"

    if not cfg.is_file():
        raise FileNotFoundError(f"Chaplin config not found: {cfg}")

    logging.info(f"[chaplin] Loading InferencePipeline on {DEVICE} with {cfg}")
    _chaplin_pipeline = InferencePipeline(
        config_filename=str(cfg),
        device=str(DEVICE),
        face_track=True,
        detector="mediapipe",
    )
    return _chaplin_pipeline


def _transcribe_chaplin(video_path: Path, lesson_id: str | None) -> dict:
    video_path = Path(video_path)
    if not video_path.exists():
        raise FileNotFoundError(f"Video not found: {video_path}")

    print("[BACKEND] using CHAPLIN")

    return chaplin_transcribe(video_path, lesson_id)

try:
    from scripts.lipread_grid import LipReadCTC, greedy_decode
    _ctc_import_ok = True
except Exception:
    LipReadCTC = None
    greedy_decode = None
    _ctc_import_ok = False

CKPT_CTC_DEFAULT = AI_DIR / "runs" / "grid_ctc" / "best.pt"

try:
    import mediapipe as mp
    _MP_OK = True
except Exception:
    mp = None
    _MP_OK = False

OUT_SIZE = 96
MIN_FRAMES = 48
MAX_FRAMES = 80


def _mouth_roi(frame_bgr: np.ndarray, face_mesh, out_size: int = OUT_SIZE) -> np.ndarray:
    h, w = frame_bgr.shape[:2]

    if face_mesh is not None:
        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        res = face_mesh.process(rgb)
        if res.multi_face_landmarks:
            lm = res.multi_face_landmarks[0]
            pts = np.array([(p.x * w, p.y * h) for p in lm.landmark])
            mouth_idx = list(range(61, 88))
            mpts = pts[mouth_idx]
            x, y, ww, hh = cv2.boundingRect(mpts.astype(np.int32))
            cx = x + ww / 2.0
            cy = y + hh / 2.0
            sz = int(max(ww, hh) * 2.0)
            x0 = max(0, int(cx - sz // 2))
            y0 = max(0, int(cy - sz // 2))
            x1 = min(w, x0 + sz)
            y1 = min(h, y0 + sz)
            crop = frame_bgr[y0:y1, x0:x1]
            if crop.size == 0:
                crop = frame_bgr
        else:
            sz = min(h, w)
            y0 = (h - sz) // 2
            x0 = (w - sz) // 2
            crop = frame_bgr[y0:y0 + sz, x0:x0 + sz]
    else:
        sz = min(h, w)
        y0 = (h - sz) // 2
        x0 = (w - sz) // 2
        crop = frame_bgr[y0:y0 + sz, x0:x0 + sz]

    crop = cv2.resize(crop, (out_size, out_size), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    return gray


def _extract_frames_ctc(video_path: Path) -> torch.Tensor:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise FileNotFoundError(f"Cannot open video: {video_path}")

    face_mesh = mp.solutions.face_mesh.FaceMesh(
        static_image_mode=False,
        refine_landmarks=True
    ) if _MP_OK else None

    frames: List[np.ndarray] = []
    try:
        while True:
            ok, img = cap.read()
            if not ok:
                break
            g = _mouth_roi(img, face_mesh)
            frames.append(g)
    finally:
        cap.release()
        if face_mesh is not None:
            face_mesh.close()

    if not frames:
        raise ValueError(f"No frames decoded from {video_path}")

    T = len(frames)
    if T < MIN_FRAMES:
        frames.extend([frames[-1]] * (MIN_FRAMES - T))
    elif T > MAX_FRAMES:
        start = (T - MAX_FRAMES) // 2
        frames = frames[start:start + MAX_FRAMES]

    arr = np.stack(frames, axis=0).astype(np.float32) / 255.0  # (T,H,W)
    arr = arr[:, None, :, :]                                   # (T,1,H,W)
    return torch.from_numpy(arr)


def _load_ctc_model(ckpt_path: Path = CKPT_CTC_DEFAULT) -> torch.nn.Module:
    global _ctc_model

    if _ctc_model is not None:
        return _ctc_model

    if not _ctc_import_ok:
        raise RuntimeError("LipReadCTC / greedy_decode not importable from scripts.lipread_grid.")

    if not ckpt_path.exists():
        raise FileNotFoundError(f"CTC checkpoint not found: {ckpt_path}")

    logging.info(f"[ctc] Loading CTC model from {ckpt_path} on {DEVICE}")
    model = LipReadCTC().to(DEVICE)  # type: ignore
    ck = torch.load(str(ckpt_path), map_location=DEVICE)
    state = ck.get("model", ck)
    model.load_state_dict(state)
    model.eval()
    _ctc_model = model
    return _ctc_model


def _transcribe_ctc(video_path: Path, lesson_id: str | None) -> dict:
    t0 = time.time()

    model = _load_ctc_model()
    frames = _extract_frames_ctc(video_path)  # [T,1,96,96]
    x = frames.permute(1, 0, 2, 3).unsqueeze(0).to(DEVICE)  # (1,1,T,H,W)

    with torch.no_grad():
        logits = model(x)                      # (T,B=1,C)
        hyps = greedy_decode(logits)
        transcript = hyps[0] if hyps else ""

    return {
        "lessonId": lesson_id,
        "transcript": transcript,
        "confidence": None,
        "words": [],
        "visemes": [],
        "latencyMs": int(round((time.time() - t0) * 1000)),
    }

def transcribe_video(video_path: str | Path, lesson_id: str | None = None) -> dict:
    video_path = Path(video_path)
    if not video_path.exists():
        raise FileNotFoundError(f"Video not found: {video_path}")

    if BACKEND_ENV == "chaplin":
        if not _chaplin_available():
            raise RuntimeError("LIP_MODEL_BACKEND=chaplin but Chaplin repo/config not found.")
        return _transcribe_chaplin(video_path, lesson_id)

    if BACKEND_ENV == "ctc":
        return _transcribe_ctc(video_path, lesson_id)

    if _chaplin_available():
        try:
            return _transcribe_chaplin(video_path, lesson_id)
        except Exception as e:
            logging.error(f"[chaplin] Failed, falling back to CTC: {e}")

    return _transcribe_ctc(video_path, lesson_id)

if __name__ == "__main__":
    sample = PROJ_ROOT / "media" / "uploads" / "sample_001.mp4"
    if sample.exists():
        print(transcribe_video(sample, lesson_id="debug_sample"))
    else:
        print(f"No sample found at {sample}")