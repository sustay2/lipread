from __future__ import annotations
import base64
import logging
from typing import List, Optional, Tuple
import cv2
import numpy as np

logger = logging.getLogger(__name__)

TARGET_SIZE = 112

# Load OpenCV DNN face detector
MODEL_PROTO = "models/deploy.prototxt"
MODEL_WEIGHTS = "models/res10_300x300_ssd_iter_140000_fp16.caffemodel"

detector = cv2.dnn.readNetFromCaffe(MODEL_PROTO, MODEL_WEIGHTS)

class FrameProcessor:

    def __init__(self):
        self._last_box: Optional[Tuple[int, int, int, int]] = None

    #
    # Decode helpers
    #
    @staticmethod
    def decode_base64_frame(data: str):
        try:
            bytes_ = base64.b64decode(data)
            return FrameProcessor.decode_bytes_frame(bytes_)
        except:
            return None

    @staticmethod
    def decode_bytes_frame(data: bytes):
        arr = np.frombuffer(data, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            return None
        return cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    #
    # Face detection
    #
    def _detect_face_box(self, frame: np.ndarray):

        h, w = frame.shape[:2]

        # DNN expects BGR
        bgr = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)

        blob = cv2.dnn.blobFromImage(
            bgr, 1.0, (300, 300),
            (104.0, 177.0, 123.0), swapRB=False
        )
        detector.setInput(blob)
        detections = detector.forward()

        # Only one face expected
        conf = detections[0, 0, 0, 2]
        if conf < 0.5:
            return None

        box = detections[0, 0, 0, 3:7] * np.array([w, h, w, h])
        x0, y0, x1, y1 = box.astype(int)

        # Square crop expansion
        bw = x1 - x0
        bh = y1 - y0
        side = max(bw, bh)
        cx = (x0 + x1) // 2
        cy = (y0 + y1) // 2
        half = side // 2

        x0 = max(0, cx - half)
        y0 = max(0, cy - half)
        x1 = min(w, cx + half)
        y1 = min(h, cy + half)

        return (x0, y0, x1, y1)

    #
    # Main processor
    #
    def process_frames(self, frames: List[np.ndarray]) -> np.ndarray:
        if not frames:
            return np.zeros((0, TARGET_SIZE, TARGET_SIZE, 3), np.float32)

        ref = frames[len(frames)//2]
        box = self._detect_face_box(ref)

        if box is None:
            box = self._last_box
            if box is None:
                # fallback: center crop
                h, w = ref.shape[:2]
                side = min(h, w)
                cx, cy = w // 2, h // 2
                half = side // 2
                box = (cx-half, cy-half, cx+half, cy+half)

        self._last_box = box
        x0, y0, x1, y1 = box

        # Focus on mouth region inside the detected face box
        face = ref[y0:y1, x0:x1]
        fh, fw = face.shape[:2]

        # Heuristic mouth ROI (works for neutral webcam angles)
        mx0 = int(fw * 0.15)
        mx1 = int(fw * 0.85)

        my0 = int(fh * 0.55)   # lower half of the face
        my1 = int(fh * 0.95)

        # Convert back to full-frame coordinates
        x0 += mx0
        x1 = x0 + (mx1 - mx0)
        y0 += my0
        y1 = y0 + (my1 - my0)

        crops = []
        for f in frames:
            crop = f[y0:y1, x0:x1]
            if crop.size == 0:
                continue
            crop = cv2.resize(crop, (TARGET_SIZE, TARGET_SIZE))
            crops.append(crop.astype(np.float32) / 255.0)

        if not crops:
            return np.zeros((0, TARGET_SIZE, TARGET_SIZE, 3), np.float32)

        return np.stack(crops)