"""FastAPI WebSocket server for real-time visual speech recognition."""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path
from typing import List, Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import uvicorn

from frame_processor import FrameProcessor
from vsr_autoavsr import AutoAVSRVSR

logger = logging.getLogger("vsr_server")
logging.basicConfig(level=logging.INFO)

app = FastAPI()

# Global model instance loaded at startup.
vsr_model: Optional[AutoAVSRVSR] = None
processor = FrameProcessor(crop_size=96)

# Model + runtime config
WINDOW_SIZE = 16  # number of frames per inference chunk
STRIDE = 8  # overlap for smoother text
CKPT_PATH = Path(__file__).parent / "models" / "vsr_trlrs2lrs3vox2avsp_base.pth"


@app.on_event("startup")
async def _load_model():
    global vsr_model
    logger.info("Loading Auto-AVSR checkpoint from %s", CKPT_PATH)
    vsr_model = AutoAVSRVSR(str(CKPT_PATH))
    logger.info("Model ready on device %s", vsr_model.device)


async def _handle_frame_message(message: dict) -> Optional["np.ndarray"]:
    """Decode an incoming websocket message into an RGB frame."""

    frame = None
    if message.get("text") is not None:
        frame = processor.decode_base64_frame(message["text"])
    elif message.get("bytes") is not None:
        frame = processor.decode_bytes_frame(message["bytes"])

    return frame


@app.websocket("/ws/vsr")
async def vsr_endpoint(websocket: WebSocket):
    await websocket.accept()
    frame_buffer: List["np.ndarray"] = []
    loop = asyncio.get_running_loop()

    try:
        while True:
            if vsr_model is None:
                logger.warning("VSR model not yet loaded; skipping frame")
                await websocket.send_json({"partial": "", "final": False})
                await asyncio.sleep(0.01)
                continue

            message = await websocket.receive()
            frame = await _handle_frame_message(message)

            if frame is None:
                await websocket.send_json({"partial": "", "final": False})
                continue

            frame_buffer.append(frame)

            # When enough frames collected, run inference on a sliding window.
            if len(frame_buffer) >= WINDOW_SIZE:
                chunk = frame_buffer[-WINDOW_SIZE:]
                frame_buffer = frame_buffer[-STRIDE:]

                video_frames = processor.process_frames(chunk)
                if video_frames.shape[0] == 0:
                    await websocket.send_json({"partial": "", "final": False})
                    continue

                # Avoid blocking the event loop during model inference.
                try:
                    text = await loop.run_in_executor(
                        None, lambda: vsr_model.transcribe(video_frames)
                    )
                except Exception as exc:  # pylint: disable=broad-except
                    logger.exception("Inference failed: %s", exc)
                    await websocket.send_json({"partial": "", "final": False})
                    continue

                await websocket.send_json({"partial": text, "final": False})

    except WebSocketDisconnect:
        logger.info("Client disconnected")
    except Exception as exc:  # pylint: disable=broad-except
        logger.exception("WebSocket error: %s", exc)
        await websocket.close()


if __name__ == "__main__":
    uvicorn.run("ws_server:app", host="0.0.0.0", port=8001)
