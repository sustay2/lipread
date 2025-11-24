from __future__ import annotations

import os
os.environ["CUDA_VISIBLE_DEVICES"] = "0"
os.environ["MEDIAPIPE_DISABLE_GPU"] = "true"
os.environ["TF_FORCE_CPU"] = "1"
os.environ["OMP_NUM_THREADS"] = "1"

import asyncio
import logging
from pathlib import Path
from typing import List, Optional

import numpy as np
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import uvicorn

from frame_processor import FrameProcessor
from vsr_autoavsr import AutoAVSRVSR

logger = logging.getLogger("vsr_server")
logging.basicConfig(level=logging.INFO)

app = FastAPI()

# Global model instance loaded at startup.
vsr_model: Optional[AutoAVSRVSR] = None

processor = FrameProcessor()

# Model + runtime config
WINDOW_SIZE = 16
STRIDE = 8
CKPT_PATH = Path(__file__).parent / "models" / "vsr_trlrs2lrs3vox2avsp_base.pth"


@app.on_event("startup")
async def _load_model():
    global vsr_model
    logger.info("Loading Auto-AVSR checkpoint from %s", CKPT_PATH)
    vsr_model = AutoAVSRVSR(str(CKPT_PATH))
    logger.info("Model ready on device %s", vsr_model.device)


async def _handle_frame_message(message: dict) -> Optional["np.ndarray"]:
    """Decode an incoming websocket message into a full RGB frame."""

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
                await websocket.send_json({"partial": "", "final": False})
                await asyncio.sleep(0.01)
                continue

            message = await websocket.receive()
            frame = await _handle_frame_message(message)

            if frame is None:
                await websocket.send_json({"partial": "", "final": False})
                continue

            frame_buffer.append(frame)

            if len(frame_buffer) >= WINDOW_SIZE:
                chunk = frame_buffer[-WINDOW_SIZE:]
                frame_buffer = frame_buffer[-STRIDE:]

                video_frames = processor.process_frames(chunk)
                if video_frames.shape[0] == 0:
                    await websocket.send_json({"partial": "", "final": False})
                    continue

                print("[DEBUG] input shape:", video_frames.shape)
                print(
                    "[DEBUG] first-frame max/min:",
                    video_frames[0].max(),
                    video_frames[0].min(),
                )

                try:
                    text = await loop.run_in_executor(
                        None, lambda: vsr_model.transcribe(video_frames)
                    )

                    logger.info("PREDICTED TEXT (clean): %s", text)
                except Exception as exc:
                    logger.exception("Inference failed: %s", exc)
                    await websocket.send_json({"partial": "", "final": False})
                    continue

                await websocket.send_json({"partial": text, "final": False})

    except WebSocketDisconnect:
        logger.info("Client disconnected")
    except Exception as exc:
        logger.exception("WebSocket error: %s", exc)
        await websocket.close()


if __name__ == "__main__":
    uvicorn.run("ws_server:app", host="0.0.0.0", port=8001)
