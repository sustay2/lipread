from fastapi import FastAPI, File, UploadFile, Form, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pathlib import Path
import shutil
import os
import time

from chaplin_model import transcribe_video

MEDIA_ROOT = Path("C:/lipread_media")
UPLOADS_DIR = MEDIA_ROOT / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="ELRL Inference API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/media", StaticFiles(directory=str(MEDIA_ROOT)), name="media")

@app.get("/health")
def health():
    return {"status": "ok", "ts": int(time.time())}

@app.post("/transcribe")
async def transcribe(video: UploadFile = File(...), lessonId: str = Form(None)):
    print(f"[REQ] /transcribe filename={video.filename} lessonId={lessonId}")

    try:
        # Store uploaded video
        dest = UPLOADS_DIR / f"{int(time.time())}_{video.filename}"
        with dest.open("wb") as f:
            shutil.copyfileobj(video.file, f)

        print(f"[OK] saved to {dest}")

        # Run inference
        result = transcribe_video(dest, lesson_id=lessonId)

        print(
            f"[DONE] transcript len={len(result.get('transcript',''))} "
            f"latency={result.get('latencyMs')}"
        )

        return JSONResponse(result, status_code=200)

    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)