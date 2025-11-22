import os
import numpy as np
import onnxruntime as ort
from fastapi import FastAPI, WebSocket
import cv2
import uvicorn

app = FastAPI()

MODEL_PATH = os.getenv("AUTOAVSR_MODEL_PATH", "models/vsr_autoavsr.onnx")

# 1. Load the Optimized ONNX Model (Load once at startup)
session = ort.InferenceSession(MODEL_PATH, providers=["CPUExecutionProvider"])

# Vocabulary mapping (You need the char list from the Auto-AVSR training config)
CHAR_LIST = ["_", "'", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", " "]

def decode_prediction(preds):
    """Simple Greedy Decoder for CTC output"""
    # preds shape: (Time, Batch, Classes)
    arg_maxes = np.argmax(preds, axis=2)
    decoded = []
    for i, index in enumerate(arg_maxes):
        if index != 0 and (i == 0 or index != arg_maxes[i-1]):
            # 0 is usually the "blank" token in CTC
            if index < len(CHAR_LIST):
                decoded.append(CHAR_LIST[index])
    return "".join(decoded)

@app.websocket("/ws/lipread")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("Client connected")
    
    buffer = []
    WINDOW_SIZE = 50  # Process 50 frames at a time (~2 seconds)
    
    try:
        while True:
            # Receive raw bytes (assume 96x96 grayscale frame sent from Flutter)
            data = await websocket.receive_bytes()
            
            # Convert bytes to numpy array
            nparr = np.frombuffer(data, np.uint8)
            frame = cv2.imdecode(nparr, cv2.IMREAD_GRAYSCALE)
            
            if frame is not None:
                # Preprocessing: Resize to model expectation (e.g., 96x96) & Normalize
                frame = cv2.resize(frame, (96, 96))
                frame = (frame - 0.421) / 0.165 # Standard normalization for LRS3
                buffer.append(frame)

                # INFERENCE TRIGGER
                if len(buffer) >= WINDOW_SIZE:
                    # Prepare Input Tensor: (1, 1, 50, 96, 96)
                    input_tensor = np.array(buffer)[np.newaxis, np.newaxis, ...].astype(np.float32)
                    
                    # Run Inference
                    outputs = session.run(["logits"], {"video_input": input_tensor})
                    text = decode_prediction(outputs[0])
                    
                    # Send result back
                    if text.strip():
                        await websocket.send_text(text)
                    
                    # Sliding Window Strategy:
                    # Keep the last 25 frames to provide context for the next batch
                    # This prevents cutting words in half.
                    buffer = buffer[25:] 
                    
    except Exception as e:
        print(f"Connection closed: {e}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
