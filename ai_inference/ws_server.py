import io
import base64
import asyncio
from fastapi import FastAPI, WebSocket
from fastapi.websockets import WebSocketDisconnect
import uvicorn
import numpy as np
import cv2

try:
    import mediapipe as mp
    _FACE_MESH = mp.solutions.face_mesh.FaceMesh(
        static_image_mode=False, max_num_faces=1, refine_landmarks=True
    )
except Exception:
    _FACE_MESH = None

from vsr_autoavsr import AutoAVSRVSR

app = FastAPI()
vsr_model = AutoAVSRVSR(
    ckpt_path="models/vsr_trlrs2lrs3vox2avsp_base.pth",
    device="cuda"
)

# Parameters for streaming
WINDOW_SIZE = 16      # number of frames per inference chunk
STRIDE = 8            # overlap for smoother text
MOUTH_CROP_SIZE = 112

_last_mouth_box = None


def _detect_mouth_bbox(frame):
    if _FACE_MESH is None:
        return None

    h, w = frame.shape[:2]
    res = _FACE_MESH.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
    if not res.multi_face_landmarks:
        return None

    pts = np.array([(p.x * w, p.y * h) for p in res.multi_face_landmarks[0].landmark], dtype=np.float32)
    mouth_pts = pts[61:88]
    x, y, ww, hh = cv2.boundingRect(mouth_pts.astype(np.int32))
    size = int(max(ww, hh) * 2.0)
    cx = x + ww * 0.5
    cy = y + hh * 0.5
    half = size * 0.5
    x0 = max(int(cx - half), 0)
    y0 = max(int(cy - half), 0)
    x1 = min(int(cx + half), w)
    y1 = min(int(cy + half), h)
    if x1 <= x0 or y1 <= y0:
        return None
    return x0, y0, x1, y1


def _center_square(h, w):
    side = min(h, w)
    x0 = (w - side) // 2
    y0 = (h - side) // 2
    return x0, y0, x0 + side, y0 + side


def crop_mouth_frames(frames):
    """
    Detect mouth once per chunk for speed, then crop/rescale each frame.
    """
    global _last_mouth_box
    if not frames:
        return np.empty((0, MOUTH_CROP_SIZE, MOUTH_CROP_SIZE, 3), dtype=np.uint8)

    bbox = _detect_mouth_bbox(frames[len(frames) // 2]) if _FACE_MESH else None
    if bbox is None:
        bbox = _last_mouth_box
    else:
        _last_mouth_box = bbox

    if bbox is None:
        h, w = frames[0].shape[:2]
        bbox = _center_square(h, w)

    x0, y0, x1, y1 = bbox
    crops = []
    for f in frames:
        crop = f[y0:y1, x0:x1]
        if crop.size == 0:
            crop = f
        crops.append(cv2.resize(crop, (MOUTH_CROP_SIZE, MOUTH_CROP_SIZE), interpolation=cv2.INTER_AREA))
    return np.stack(crops, axis=0)


@app.websocket("/ws/vsr")
async def vsr_endpoint(websocket: WebSocket):
    await websocket.accept()

    frame_buffer = []

    try:
        while True:
            # You decide your own message format.
            # Example: frontend sends base64-encoded JPEG
            data = await websocket.receive_text()
            frame_bytes = base64.b64decode(data)

            # Decode jpeg to numpy frame
            frame_array = np.frombuffer(frame_bytes, np.uint8)
            frame = cv2.imdecode(frame_array, cv2.IMREAD_COLOR)  # BGR

            frame_buffer.append(frame)

            # When enough frames collected, run inference
            if len(frame_buffer) >= WINDOW_SIZE:
                # Take last WINDOW_SIZE frames
                chunk = frame_buffer[-WINDOW_SIZE:]

                # Optional: keep STRIDE overlap instead of clearing whole buffer
                frame_buffer = frame_buffer[-STRIDE:]

                # Convert to [T, H, W, 3] with mouth-focused crops
                video_frames = crop_mouth_frames(chunk)
                text = vsr_model.transcribe(video_frames)

                # Send partial result to client
                await websocket.send_json({"partial_text": text})

    except WebSocketDisconnect:
        pass

if __name__ == "__main__":
    uvicorn.run("ws_server:app", host="0.0.0.0", port=8000)
