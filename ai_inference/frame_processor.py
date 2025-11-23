"""Frame preprocessing utilities for Auto-AVSR streaming."""

from __future__ import annotations

import base64
import logging
import math
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
LEFT_MOUTH_CORNER = 61
RIGHT_MOUTH_CORNER = 291


class FrameProcessor:
    """Decode, align, and crop frames for Auto-AVSR."""

    def __init__(self, crop_size: int = 96) -> None:
        self.crop_size = crop_size
        # MediaPipe expects RGB input. Use refine_landmarks for better mouth keypoints.
        self._face_mesh = mp.solutions.face_mesh.FaceMesh(
            static_image_mode=False, max_num_faces=1, refine_landmarks=True
        )
        self._face_detector = mp.solutions.face_detection.FaceDetection(
            model_selection=1, min_detection_confidence=0.4
        )
        self._last_bbox: Optional[Tuple[int, int, int, int]] = None
        self._last_rotation: Optional[np.ndarray] = None

    # ---------------------------------------------------------------------
    # Decoding helpers
    # ---------------------------------------------------------------------
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

    # ---------------------------------------------------------------------
    # Landmark + ROI utilities
    # ---------------------------------------------------------------------
    def _mesh_landmarks(self, rgb_frame: np.ndarray) -> Optional[np.ndarray]:
        """Run FaceMesh and return pixel landmarks if available."""

        h, w = rgb_frame.shape[:2]
        contiguous_frame = np.ascontiguousarray(rgb_frame)
        result = self._face_mesh.process(contiguous_frame)
        if not result.multi_face_landmarks:
            return None

        return np.array(
            [(lm.x * w, lm.y * h) for lm in result.multi_face_landmarks[0].landmark],
            dtype=np.float32,
        )

    def _detect_face_box(self, rgb_frame: np.ndarray) -> Optional[Tuple[int, int, int, int]]:
        """Fallback to coarse face detection if landmarks are missing."""

        detection_result = self._face_detector.process(rgb_frame)
        if not detection_result.detections:
            return None

        h, w = rgb_frame.shape[:2]
        bbox = detection_result.detections[0].location_data.relative_bounding_box
        x0 = max(int(bbox.xmin * w), 0)
        y0 = max(int(bbox.ymin * h), 0)
        x1 = min(int((bbox.xmin + bbox.width) * w), w)
        y1 = min(int((bbox.ymin + bbox.height) * h), h)
        if x1 <= x0 or y1 <= y0:
            return None
        # Convert to a square for stable mouth crops.
        return self._square_bbox((x0, y0, x1, y1), w, h)

    @staticmethod
    def _square_bbox(box: Tuple[int, int, int, int], width: int, height: int) -> Tuple[int, int, int, int]:
        x0, y0, x1, y1 = box
        bw, bh = x1 - x0, y1 - y0
        side = max(bw, bh)
        cx = x0 + bw * 0.5
        cy = y0 + bh * 0.5
        half = side * 0.5
        sx0 = int(max(cx - half, 0))
        sy0 = int(max(cy - half, 0))
        sx1 = int(min(cx + half, width))
        sy1 = int(min(cy + half, height))
        return sx0, sy0, sx1, sy1

    def _alignment(self, rgb_frame: np.ndarray) -> Tuple[np.ndarray, Tuple[int, int, int, int]]:
        """Compute rotation + bounding box for the mouth ROI."""

        h, w = rgb_frame.shape[:2]
        landmarks = self._mesh_landmarks(rgb_frame)

        if landmarks is not None:
            left = landmarks[LEFT_MOUTH_CORNER]
            right = landmarks[RIGHT_MOUTH_CORNER]
            angle = math.degrees(math.atan2(right[1] - left[1], right[0] - left[0]))
            center = ((left[0] + right[0]) * 0.5, (left[1] + right[1]) * 0.5)
            rot_mat = cv2.getRotationMatrix2D(center, angle, 1.0)

            mouth_pts = landmarks[MOUTH_LANDMARKS]
            homog = np.concatenate([mouth_pts, np.ones((mouth_pts.shape[0], 1))], axis=1)
            rotated = (rot_mat @ homog.T).T
            x, y, bw, bh = cv2.boundingRect(rotated.astype(np.float32))
            side = int(max(bw, bh) * 1.6)
            cx, cy = x + bw * 0.5, y + bh * 0.5
            half = side * 0.5
            x0 = int(max(cx - half, 0))
            y0 = int(max(cy - half, 0))
            x1 = int(min(cx + half, w))
            y1 = int(min(cy + half, h))
            bbox = (x0, y0, x1, y1)
        else:
            rot_mat = np.array([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]], dtype=np.float32)
            bbox = self._detect_face_box(rgb_frame)
            if bbox is None:
                if self._last_bbox is not None:
                    bbox = self._last_bbox
                else:
                    bbox = self._square_bbox((0, 0, w, h), w, h)

        self._last_bbox = bbox
        self._last_rotation = rot_mat
        return rot_mat, bbox

    def _warp_and_crop(
        self, rgb_frame: np.ndarray, rot_mat: np.ndarray, bbox: Tuple[int, int, int, int]
    ) -> np.ndarray:
        h, w = rgb_frame.shape[:2]
        aligned = cv2.warpAffine(rgb_frame, rot_mat, (w, h), flags=cv2.INTER_LINEAR)
        x0, y0, x1, y1 = bbox
        mouth = aligned[y0:y1, x0:x1]
        if mouth.size == 0:
            mouth = aligned
        mouth = cv2.resize(
            mouth, (self.crop_size, self.crop_size), interpolation=cv2.INTER_AREA
        )
        return mouth

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    def process_frames(self, frames: List[np.ndarray]) -> np.ndarray:
        """Align and crop frames, returning float32 T x H x W x C in [0,1]."""

        if not frames:
            return np.empty((0, self.crop_size, self.crop_size, 3), dtype=np.float32)

        rot_mat, bbox = self._alignment(frames[len(frames) // 2])
        processed: List[np.ndarray] = []
        for frame in frames:
            if frame.ndim != 3 or frame.shape[2] != 3:
                continue
            mouth = self._warp_and_crop(frame, rot_mat, bbox)
            processed.append(mouth.astype(np.float32) / 255.0)

        if not processed:
            return np.empty((0, self.crop_size, self.crop_size, 3), dtype=np.float32)

        return np.stack(processed, axis=0)
