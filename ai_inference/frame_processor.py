from __future__ import annotations
import base64
import logging
from typing import List, Optional, Tuple

import cv2
import numpy as np
import dlib
from pathlib import Path

logger = logging.getLogger(__name__)

# Auto-AVSR expects 112x112 grayscale mouth ROI
TARGET_SIZE = 112

# Mouth landmark indices (Auto-AVSR compatible)
MOUTH_IDXS = list(range(48, 68))  # 48–67

PREDICTOR_PATH = (
    Path(__file__).parent / "models" / "shape_predictor_68_face_landmarks.dat"
)

class FrameProcessor:
    """Mouth-only ROI extractor using dlib landmarks."""

    def __init__(self):
        self.detector = dlib.get_frontal_face_detector()
        if not PREDICTOR_PATH.exists():
            raise FileNotFoundError("Missing shape_predictor_68_face_landmarks.dat!")
        self.predictor = dlib.shape_predictor(str(PREDICTOR_PATH))
        self._last_box = None  # (x0, y0, x1, y1)

    # ------------------------------------------------------------
    # Decoding helpers
    # ------------------------------------------------------------
    @staticmethod
    def decode_base64_frame(data: str) -> Optional[np.ndarray]:
        try:
            frame_bytes = base64.b64decode(data)
        except Exception:
            return None
        return FrameProcessor.decode_bytes_frame(frame_bytes)

    @staticmethod
    def decode_bytes_frame(data: bytes) -> Optional[np.ndarray]:
        arr = np.frombuffer(data, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            return None
        return cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # ------------------------------------------------------------
    # Mouth ROI via dlib 68-landmarks
    # ------------------------------------------------------------
    def _detect_mouth_box(self, rgb: np.ndarray) -> Optional[Tuple[int, int, int, int]]:
        h, w = rgb.shape[:2]

        gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
        rects = self.detector(gray, 0)

        if len(rects) == 0:
            return None

        shape = self.predictor(gray, rects[0])
        pts = np.array([(shape.part(i).x, shape.part(i).y) for i in MOUTH_IDXS])

        min_x, min_y = pts.min(axis=0)
        max_x, max_y = pts.max(axis=0)

        box_w = max_x - min_x
        box_h = max_y - min_y
        side = int(max(box_w, box_h) * 1.4)  # pad by ~40%

        cx = (min_x + max_x) // 2
        cy = (min_y + max_y) // 2

        half = side // 2

        x0 = max(0, cx - half)
        y0 = max(0, cy - half)
        x1 = min(w, cx + half)
        y1 = min(h, cy + half)

        return (x0, y0, x1, y1)

    # ------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------
    # frame_processor.py

    def process_frames(self, frames: List[np.ndarray]) -> np.ndarray:
        """
        Returns:
            (T, 112, 112, 3) float32 in range [0, 1].
        """
        if not frames:
            # Return empty with 3 channels (RGB)
            return np.empty((0, TARGET_SIZE, TARGET_SIZE, 3), dtype=np.float32)

        ref = frames[len(frames) // 2]
        box = self._detect_mouth_box(ref)

        if box is None:
            box = self._last_box
            if box is None:  # final fallback
                h, w = ref.shape[:2]
                side = min(h, w)
                cx, cy = w // 2, h // 2
                half = side // 2
                box = (cx-half, cy-half, cx+half, cy+half)

        self._last_box = box

        x0, y0, x1, y1 = box
        processed = []

        for f in frames:
            mouth = f[y0:y1, x0:x1]
            if mouth.size == 0:
                continue

            # RESIZE ONLY. Do not convert to Gray. Do not Normalize to -1.
            mouth = cv2.resize(mouth, (TARGET_SIZE, TARGET_SIZE), cv2.INTER_AREA)
            
            # Normalize to [0, 1] only. 
            # Auto-AVSR VideoTransform expects [0,1] or [0,255]. 
            mouth = mouth.astype(np.float32) / 255.0

            processed.append(mouth)

        if not processed:
            return np.empty((0, TARGET_SIZE, TARGET_SIZE, 3), dtype=np.float32)

        return np.stack(processed, axis=0)