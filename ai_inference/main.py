"""
To run the server for model:
uvicorn main:app --reload --host 0.0.0.0 --port 8000

In flutter:
flutter run --dart-define=API_BASE=http://192.168.0.115:8000
"""

from fastapi import FastAPI, File, UploadFile, Form, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pathlib import Path
import shutil, os, time

from lip_model import transcribe_video

# ---- Config ----
BASE_DIR = Path(__file__).resolve().parents[1]
MEDIA_ROOT = Path(os.getenv("MEDIA_ROOT", BASE_DIR / "media"))
UPLOADS_DIR = MEDIA_ROOT / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="ELRL Inference API")

# CORS so mobile/web can access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Optional: serve media for debugging / previews
app.mount("/media", StaticFiles(directory=str(MEDIA_ROOT)), name="media")

@app.get("/health")
def health():
    return {"status": "ok", "ts": int(time.time())}

@app.get("/server_info")
def server_info(request: Request):
    client_ip = request.client.host
    
    return {
        "server_ip": client_ip,
        "api_base": f"http://{client_ip}:8000",
        "media_base": f"http://{client_ip}:8000/media"
    }

@app.post("/transcribe")
async def transcribe(video: UploadFile = File(...), lessonId: str = Form(None)):
    print(f"[REQ] /transcribe filename={video.filename} lessonId={lessonId}")
    """
    Receives a video, saves to /media/uploads, runs lip model, returns transcript JSON.
    """
    try:
        # 1) Save the upload
        dest = UPLOADS_DIR / f"{int(time.time())}_{video.filename}"
        with dest.open("wb") as f:
            shutil.copyfileobj(video.file, f)

        # 2) Inference
        print(f"[OK] saved to {dest} -> running inference")
        result = transcribe_video(dest, lesson_id=lessonId)

        # 3) Return JSON
        print(f"[DONE] transcript len={len(result.get('transcript',''))} latency={result.get('latencyMs')}")
        return JSONResponse(content=result, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)