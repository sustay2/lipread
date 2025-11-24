from __future__ import annotations

import base64
import logging
from typing import List, Optional, Tuple

import cv2
import numpy as np

logger = logging.getLogger(__name__)

# Output dimensions expected by Auto-AVSR
TARGET_SIZE = 112

# MediaPipe FaceMesh mouth/lip landmark indices (468-point topology)
LIP_IDXS: Tuple[int, ...] = (
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
    324,
    318,
    402,
    317,
    14,
    87,
    178,
    88,
    95,
    185,
    40,
    39,
    37,
    0,
    267,
    269,
    270,
    409,
    415,
    310,
    311,
    312,
    13,
    82,
    81,
    42,
    183,
    78,
)


class FrameProcessor:
    """Extracts mouth-only crops suitable for Auto-AVSR."""

    def __init__(self):
        try:
            import mediapipe as mp  # type: ignore
        except Exception as exc:  # pragma: no cover - defensive
            raise RuntimeError(
                "MediaPipe is required for mouth cropping but could not be imported"
            ) from exc

        self._mp_face_mesh = mp.solutions.face_mesh.FaceMesh(
            static_image_mode=True,
            max_num_faces=1,
            refine_landmarks=True,
            min_detection_confidence=0.3,
            min_tracking_confidence=0.3,
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
        results = self._mp_face_mesh.process(rgb)

        if not results.multi_face_landmarks:
            return None

        pts = []
        for lm_idx in LIP_IDXS:
            lm = results.multi_face_landmarks[0].landmark[lm_idx]
            pts.append((lm.x * w, lm.y * h))

        pts_np = np.array(pts, dtype=np.float32)
        min_xy = pts_np.min(axis=0)
        max_xy = pts_np.max(axis=0)

        min_x, min_y = min_xy
        max_x, max_y = max_xy

        box_w = max_x - min_x
        box_h = max_y - min_y
        side = int(max(box_w, box_h) * 1.6)  # generous padding

        cx = (min_x + max_x) / 2.0
        cy = (min_y + max_y) / 2.0

        half = side / 2.0
        x0 = max(0, int(round(cx - half)))
        y0 = max(0, int(round(cy - half)))
        x1 = min(w, int(round(cx + half)))
        y1 = min(h, int(round(cy + half)))

        if x1 <= x0 or y1 <= y0:
            return None

        return (x0, y0, x1, y1)

    def _stable_box(self, rgb: np.ndarray) -> Tuple[int, int, int, int]:
        box = self._landmarks_to_box(rgb)

        if box is None:
            box = self._last_box
            if box is None:
                # Centered square fallback
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
        """Return a batch of mouth crops shaped [T,112,112,1]."""
        if not frames:
            logger.warning("No frames provided to process_frames; returning blank crop")
            blank = np.zeros((1, TARGET_SIZE, TARGET_SIZE, 1), dtype=np.float32)
            return blank

        processed: List[np.ndarray] = []

        # Use the middle frame to stabilise the ROI
        reference = frames[len(frames) // 2]
        ref_box = self._stable_box(reference)

        for frame in frames:
            box = self._stable_box(frame)
            if box is None:
                box = ref_box

            x0, y0, x1, y1 = box
            mouth = frame[y0:y1, x0:x1]

            if mouth.size == 0:
                # If the crop vanished, use the reference box on the current frame
                mouth = frame[ref_box[1]:ref_box[3], ref_box[0]:ref_box[2]]

            if mouth.size == 0:
                # Absolute last resort: centered crop
                h, w = frame.shape[:2]
                side = min(h, w)
                cx, cy = w // 2, h // 2
                half = side // 2
                mouth = frame[cy - half:cy + half, cx - half:cx + half]

            # Resize to target, convert to grayscale and normalise
            mouth = cv2.resize(mouth, (TARGET_SIZE, TARGET_SIZE), cv2.INTER_AREA)
            mouth = cv2.cvtColor(mouth, cv2.COLOR_RGB2GRAY)
            mouth = mouth.astype(np.float32) / 255.0
            mouth = np.expand_dims(mouth, axis=-1)  # (112, 112, 1)

            processed.append(mouth)

        if not processed:
            # Should never happen, but keep the contract of non-empty output.
            blank = np.zeros((1, TARGET_SIZE, TARGET_SIZE, 1), dtype=np.float32)
            return blank

        return np.stack(processed, axis=0)
