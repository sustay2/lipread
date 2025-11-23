"""Frame preprocessing utilities for Auto-AVSR streaming."""

from __future__ import annotations

import base64
import logging
from typing import List, Optional, Tuple

import cv2
import mediapipe as mp
import numpy as np

logger = logging.getLogger(__name__)

# Key landmark indices around the mouth for MediaPipe FaceMesh.
MOUTH_LANDMARKS = [
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
]


class FrameProcessor:
    """Decode frames and extract square mouth crops for Auto-AVSR."""

    def __init__(self, crop_size: int = 96, padding_ratio: float = 0.3) -> None:
        self.crop_size = crop_size
        self.padding_ratio = padding_ratio

        # MediaPipe expects RGB input. Use refine_landmarks for better mouth keypoints.
        self._face_mesh = mp.solutions.face_mesh.FaceMesh(
            static_image_mode=False, max_num_faces=1, refine_landmarks=True
        )

        self._last_roi: Optional[Tuple[int, int, int, int]] = None

    # ------------------------------------------------------------------
    # Decoding helpers
    # ------------------------------------------------------------------
    @staticmethod
    def decode_base64_frame(data: str) -> Optional[np.ndarray]:
        """Decode a base64-encoded JPEG/PNG payload into an RGB array."""

        try:
            frame_bytes = base64.b64decode(data)
        except Exception as exc:  # pylint: disable=broad-except
            logger.warning("Failed to base64-decode frame: %s", exc)
            return None
        return FrameProcessor.decode_bytes_frame(frame_bytes)

    @staticmethod
    def decode_bytes_frame(data: bytes) -> Optional[np.ndarray]:
        frame_array = np.frombuffer(data, np.uint8)
        if frame_array.size == 0:
            return None
        frame = cv2.imdecode(frame_array, cv2.IMREAD_COLOR)
        if frame is None:
            return None
        if frame.ndim != 3 or frame.shape[2] != 3:
            return None
        # Convert BGR (OpenCV default) -> RGB for MediaPipe and the model.
        return cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

    # ------------------------------------------------------------------
    # Landmark + ROI utilities
    # ------------------------------------------------------------------
    def _extract_landmarks(self, full_frame_rgb: np.ndarray) -> Optional[np.ndarray]:
        """Run FaceMesh on the *original* frame and return pixel landmarks."""

        if full_frame_rgb.ndim != 3 or full_frame_rgb.shape[2] != 3:
            return None

        height, width = full_frame_rgb.shape[:2]
        contiguous_frame = np.ascontiguousarray(full_frame_rgb)
        result = self._face_mesh.process(contiguous_frame)
        if not result.multi_face_landmarks:
            return None

        return np.array(
            [(lm.x * width, lm.y * height) for lm in result.multi_face_landmarks[0].landmark],
            dtype=np.float32,
        )

    def _compute_mouth_roi(
        self, landmarks: np.ndarray, frame_shape: Tuple[int, int, int]
    ) -> Optional[Tuple[int, int, int, int]]:
        """Compute a square, padded mouth ROI from FaceMesh landmarks."""

        height, width = frame_shape[:2]
        mouth_pts = landmarks[MOUTH_LANDMARKS]
        min_xy = mouth_pts.min(axis=0)
        max_xy = mouth_pts.max(axis=0)

        mouth_width, mouth_height = max_xy - min_xy
        size = float(max(mouth_width, mouth_height))
        if size <= 0:
            return None

        # Center at the middle of the lip landmarks.
        center_x, center_y = mouth_pts.mean(axis=0)

        # Add padding (20–40% recommended) and ensure the ROI remains square.
        side = size * (1.0 + self.padding_ratio)
        side = min(side, float(min(width, height)))
        half = side * 0.5

        center_x = float(np.clip(center_x, half, width - half))
        center_y = float(np.clip(center_y, half, height - half))

        x0 = int(round(center_x - half))
        y0 = int(round(center_y - half))
        x1 = int(round(center_x + half))
        y1 = int(round(center_y + half))

        if x1 <= x0 or y1 <= y0:
            return None

        return x0, y0, x1, y1

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    def process_frames(self, frames: List[np.ndarray]) -> np.ndarray:
        """Extract mouth crops from a list of RGB frames.

        Returns:
            float32 array shaped (T, crop_size, crop_size, 3) with values in [0, 1].
        """

        if not frames:
            return np.empty((0, self.crop_size, self.crop_size, 3), dtype=np.float32)

        reference_frame = frames[len(frames) // 2]
        roi: Optional[Tuple[int, int, int, int]] = None

        landmarks = self._extract_landmarks(reference_frame)
        if landmarks is not None:
            roi = self._compute_mouth_roi(landmarks, reference_frame.shape)

        if roi is None:
            if self._last_roi is not None:
                roi = self._last_roi
            else:
                # Fallback to a centered square crop covering the largest possible area.
                h, w = reference_frame.shape[:2]
                side = min(h, w)
                cx, cy = w * 0.5, h * 0.5
                half = side * 0.5
                roi = (
                    int(round(cx - half)),
                    int(round(cy - half)),
                    int(round(cx + half)),
                    int(round(cy + half)),
                )

        self._last_roi = roi

        x0, y0, x1, y1 = roi
        processed: List[np.ndarray] = []
        for frame in frames:
            if frame.ndim != 3 or frame.shape[2] != 3:
                continue
            # Crop directly from the original, unrotated frame.
            mouth = frame[y0:y1, x0:x1]
            if mouth.size == 0:
                continue
            mouth = cv2.resize(
                mouth, (self.crop_size, self.crop_size), interpolation=cv2.INTER_AREA
            )
            processed.append(mouth.astype(np.float32) / 255.0)

        if not processed:
            return np.empty((0, self.crop_size, self.crop_size, 3), dtype=np.float32)

        return np.stack(processed, axis=0)
