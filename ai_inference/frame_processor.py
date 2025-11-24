from __future__ import annotations

import base64
import logging
from typing import List, Optional, Tuple

import cv2
import numpy as np

logger = logging.getLogger(__name__)

TARGET_SIZE = 112
LIP_LANDMARKS: Tuple[int, ...] = (
    61,
    146,
    91,
    181,
    84,
    17,
    314,
    405,
    321,
    375,
    291,
    308,
)


class FrameProcessor:
    """Extracts lip crops that match the Auto-AVSR training input."""

    def __init__(self):
        try:
            import mediapipe as mp  # type: ignore
        except Exception as exc:  # pragma: no cover - defensive
            raise RuntimeError(
                "MediaPipe is required for mouth cropping but could not be imported"
            ) from exc

        self._face_mesh = mp.solutions.face_mesh.FaceMesh(
            refine_landmarks=True,
            max_num_faces=1,
        )
        self._last_box: Optional[Tuple[int, int, int, int]] = None

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
    # Landmark helpers
    # ------------------------------------------------------------
    def _landmarks_to_box(self, rgb: np.ndarray) -> Optional[Tuple[int, int, int, int]]:
        h, w = rgb.shape[:2]
        results = self._face_mesh.process(rgb)

        if not results.multi_face_landmarks:
            return None

        face_landmarks = results.multi_face_landmarks[0].landmark
        pts: List[Tuple[float, float]] = []
        for idx in LIP_LANDMARKS:
            if idx < len(face_landmarks):
                lm = face_landmarks[idx]
                pts.append((lm.x * w, lm.y * h))

        if not pts:
            return None

        pts_np = np.array(pts, dtype=np.float32)
        min_xy = pts_np.min(axis=0)
        max_xy = pts_np.max(axis=0)

        min_x, min_y = min_xy
        max_x, max_y = max_xy

        box_w = max_x - min_x
        box_h = max_y - min_y
        side = max(box_w, box_h)

        padding = side * 0.3
        side = side + 2 * padding

        cx = (min_x + max_x) / 2.0
        cy = (min_y + max_y) / 2.0

        half = side / 2.0
        x0 = int(np.clip(round(cx - half), 0, w))
        y0 = int(np.clip(round(cy - half), 0, h))
        x1 = int(np.clip(round(cx + half), 0, w))
        y1 = int(np.clip(round(cy + half), 0, h))

        if x1 <= x0 or y1 <= y0:
            return None

        return (x0, y0, x1, y1)

    def _stable_box(self, rgb: np.ndarray) -> Tuple[int, int, int, int]:
        box = self._landmarks_to_box(rgb)

        if box is None:
            box = self._last_box
            if box is None:
                h, w = rgb.shape[:2]
                side = min(h, w)
                cx, cy = w // 2, h // 2
                half = side // 2
                box = (cx - half, cy - half, cx + half, cy + half)
        else:
            self._last_box = box

        return box

    # ------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------
    def process_frames(self, frames: List[np.ndarray]) -> np.ndarray:
        """Return a batch of lip crops shaped [T, 112, 112, 1]."""
        if not frames:
            logger.warning("No frames provided to process_frames; returning blank crop")
            blank = np.zeros((1, TARGET_SIZE, TARGET_SIZE, 1), dtype=np.float32)
            return blank

        processed: List[np.ndarray] = []

        for frame in frames:
            box = self._stable_box(frame)
            x0, y0, x1, y1 = box

            mouth = frame[y0:y1, x0:x1]
            if mouth.size == 0:
                h, w = frame.shape[:2]
                side = min(h, w)
                cx, cy = w // 2, h // 2
                half = side // 2
                mouth = frame[cy - half : cy + half, cx - half : cx + half]

            crop = cv2.resize(mouth, (TARGET_SIZE, TARGET_SIZE), cv2.INTER_AREA)
            crop = cv2.cvtColor(crop, cv2.COLOR_RGB2GRAY)
            crop = crop.astype(np.float32) / 255.0
            crop = np.expand_dims(crop, axis=-1)

            processed.append(crop)

        if not processed:
            blank = np.zeros((1, TARGET_SIZE, TARGET_SIZE, 1), dtype=np.float32)
            return blank

        return np.stack(processed, axis=0)
