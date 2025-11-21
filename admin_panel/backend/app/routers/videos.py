from pathlib import Path
import os, uuid, subprocess, shlex, pathlib, json
from typing import Optional, Dict, Any, List
from firebase_admin import firestore as admin_fs
from google.cloud.firestore_v1 import SERVER_TIMESTAMP
from app.deps.auth import require_roles, get_current_user
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query, Body

router = APIRouter()
db = admin_fs.client()

MEDIA_ROOT = os.getenv("MEDIA_ROOT", "/data")
MEDIA_BASE_URL = os.getenv("MEDIA_BASE_URL", "http://api:8000/media")
MEDIA_ORIGINAL_DIR = os.getenv("MEDIA_ORIGINAL_DIR", os.path.join(MEDIA_ROOT, "original"))
MEDIA_THUMB_DIR    = os.getenv("MEDIA_THUMB_DIR",    os.path.join(MEDIA_ROOT, "thumbs"))
MEDIA_PUBLIC_BASE_URL = os.getenv("MEDIA_PUBLIC_BASE_URL", None)
THUMB_DIR_REL = "thumbs"
THUMB_WIDTH  = 480

Path(MEDIA_ORIGINAL_DIR).mkdir(parents=True, exist_ok=True)
Path(MEDIA_THUMB_DIR).mkdir(parents=True, exist_ok=True)

def _url_for(rel_path: str) -> str:
    rel = rel_path.replace("\\", "/").lstrip("/")
    return f"{MEDIA_BASE_URL.rstrip('/')}/{rel}"

def _abs_for(rel_path: str) -> str:
    rel = rel_path.replace("\\", "/").lstrip("/")
    return f"{MEDIA_ROOT.rstrip('/')}/{rel}"

def _thumb_rel_from_storage(storage_path: str) -> str:
    base = os.path.splitext(os.path.basename(storage_path))[0]
    return f"{THUMB_DIR_REL}/{base}.jpg"

def _thumb_rel_for(storage_path: str) -> str:
    return _thumb_rel_from_storage(storage_path)

def _run_ffmpeg_thumbnail(input_rel: str, out_rel: str) -> bool:
    in_abs  = _abs_for(input_rel)
    out_abs = _abs_for(out_rel)
    os.makedirs(os.path.dirname(out_abs), exist_ok=True)
    cmd = f'ffmpeg -y -ss 0.2 -i {shlex.quote(in_abs)} -vframes 1 -vf scale={THUMB_WIDTH}:-1 {shlex.quote(out_abs)}'
    try:
        proc = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        return proc.returncode == 0 and os.path.exists(out_abs)
    except Exception:
        return False

def _probe_metadata(input_rel: str) -> Dict[str, Optional[float]]:
    in_abs = _abs_for(input_rel)
    cmd = f'ffprobe -v error -print_format json -show_streams -show_format {shlex.quote(in_abs)}'
    try:
        proc = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if proc.returncode != 0:
            return {}
        info = json.loads(proc.stdout.decode("utf-8", "ignore") or "{}")
        duration = None; fps = None
        if "format" in info and "duration" in info["format"]:
            try: duration = float(info["format"]["duration"])
            except Exception: pass
        for s in info.get("streams", []):
            if s.get("codec_type") == "video":
                rate = s.get("r_frame_rate") or s.get("avg_frame_rate")
                if rate and "/" in rate:
                    num, den = rate.split("/", 1)
                    try:
                        n, d = float(num), float(den)
                        if d != 0: fps = n / d
                    except Exception: pass
                break
        out = {}
        if duration is not None: out["durationSec"] = round(duration, 3)
        if fps is not None: out["fps"] = round(fps, 3)
        return out
    except Exception:
        return {}

def _video_doc_to_payload(doc_snap) -> Dict[str, Any]:
    data = doc_snap.to_dict() or {}
    vid = doc_snap.id
    thumb_rel = data.get("thumbPath")
    payload = {
        "id": vid,
        "title": data.get("title"),
        "storagePath": data.get("storagePath"),
        "url": data.get("url"),
        "thumbPath": thumb_rel,
        "thumbUrl": _url_for(thumb_rel) if thumb_rel else None,
        "durationSec": data.get("durationSec"),
        "fps": data.get("fps"),
        "language": data.get("language"),
        "speakerId": data.get("speakerId"),
        "license": data.get("license"),
        "source": data.get("source"),
        "createdAt": data.get("createdAt"),
        "uploadedBy": data.get("uploadedBy"),
        "sizeBytes": data.get("sizeBytes"),
        "isArchived": bool(data.get("isArchived", False)),
    }
    return payload

@router.get("", dependencies=[Depends(require_roles(["admin","content_editor","instructor"]))])
async def list_videos(limit: int = Query(50, ge=1, le=500), q: Optional[str] = Query(None), include_archived: bool = Query(False)):
    col = db.collection("videos")
    try:
        snaps = list(col.order_by("createdAt", direction="DESCENDING").limit(limit).stream())
    except Exception:
        snaps = list(col.limit(limit).stream())
    out: List[Dict[str, Any]] = []
    for s in snaps:
        item = _video_doc_to_payload(s)
        if not include_archived and item.get("isArchived"): continue
        if q and q.lower() not in (item.get("title") or "").lower(): continue
        out.append(item)
    return {"items": out, "next_cursor": out[-1]["id"] if len(out) == limit else None}

@router.post("/upload", dependencies=[Depends(require_roles(["admin","content_editor"]))])
async def upload_video(
    user = Depends(get_current_user),
    file: UploadFile = File(...),
    title: Optional[str] = Form(None),
    language: Optional[str] = Form("en"),
    speakerId: Optional[str] = Form(None),
    license: Optional[str] = Form("internal"),
    source: Optional[str] = Form("manual"),
):
    uid = user["uid"]
    vid_id = uuid.uuid4().hex[:20]
    safe_name = file.filename.replace("/", "_").replace("\\", "_")
    disk_name = f"{vid_id}_{safe_name}"
    storage_rel = f"original/{disk_name}"
    disk_path = os.path.join(MEDIA_ORIGINAL_DIR, disk_name)

    data = await file.read()
    with open(disk_path, "wb") as f: f.write(data)

    url = _url_for(storage_rel)
    thumb_rel = _thumb_rel_from_storage(storage_rel)
    _ = _run_ffmpeg_thumbnail(storage_rel, thumb_rel)

    video_doc = {
        "title": title or safe_name,
        "storagePath": storage_rel,
        "url": url,
        "thumbPath": thumb_rel if os.path.exists(_abs_for(thumb_rel)) else None,
        "durationSec": None, "fps": None,
        "language": language, "speakerId": speakerId,
        "license": license, "source": source,
        "sizeBytes": len(data),
        "uploadedBy": uid,
        "createdAt": SERVER_TIMESTAMP,
        "isArchived": False,
    }
    db.collection("videos").document(vid_id).set(video_doc)
    return _video_doc_to_payload(db.collection("videos").document(vid_id).get())

@router.post("/{videoId}:thumbnail", dependencies=[Depends(require_roles(["admin","content_editor"]))])
async def generate_thumbnail(videoId: str):
    ref = db.collection("videos").document(videoId)
    snap = ref.get()
    if not snap.exists: raise HTTPException(404, "Video not found")
    d = snap.to_dict() or {}

    src_rel = d.get("storagePath") or d.get("path")
    if not src_rel:
        ref.set({"thumbsPending": True, "updatedAt": SERVER_TIMESTAMP}, merge=True)
        raise HTTPException(400, "No storagePath/path on video")

    if not os.path.isfile(_abs_for(src_rel)):
        ref.set({"thumbsPending": True, "updatedAt": SERVER_TIMESTAMP}, merge=True)
        return {"accepted": True, "status": 202, "reason": "not_local"}

    out_rel = _thumb_rel_for(src_rel)
    ok = _run_ffmpeg_thumbnail(src_rel, out_rel)
    if not ok:
        ref.set({"thumbsPending": True, "updatedAt": SERVER_TIMESTAMP}, merge=True)
        return {"accepted": True, "status": 202, "reason": "ffmpeg_failed"}

    ref.set({"thumbPath": out_rel, "thumbUrl": _url_for(out_rel), "thumbsPending": False, "updatedAt": SERVER_TIMESTAMP}, merge=True)
    return _video_doc_to_payload(ref.get())

@router.patch("/{videoId}", dependencies=[Depends(require_roles(["admin","content_editor"]))])
async def rename_video(videoId: str, body: Dict[str, Any] = Body(...)):
    ref = db.collection("videos").document(videoId)
    snap = ref.get()
    if not snap.exists: raise HTTPException(404, "Video not found")
    d = snap.to_dict() or {}

    title = (body.get("title") or "").strip()
    do_rename = bool(body.get("renameFile", False))

    patch: Dict[str, Any] = {"updatedAt": SERVER_TIMESTAMP}
    if title: patch["title"] = title

    if do_rename and d.get("storagePath"):
        old_rel = d["storagePath"]
        old_abs = _abs_for(old_rel)
        if os.path.isfile(old_abs):
            base_dir = os.path.dirname(old_rel.replace("\\", "/"))
            ext = os.path.splitext(old_rel)[1]
            safe = (title or pathlib.PurePosixPath(old_rel).stem).replace("/", "_").replace("\\", "_").strip()
            new_rel = f"{base_dir}/{safe}{ext}"
            os.makedirs(os.path.dirname(_abs_for(new_rel)), exist_ok=True)
            os.replace(old_abs, _abs_for(new_rel))
            patch["storagePath"] = new_rel
            patch["url"] = _url_for(new_rel)
            if d.get("thumbPath"):
                old_thumb_abs = _abs_for(d["thumbPath"])
                if os.path.isfile(old_thumb_abs):
                    new_thumb_rel = _thumb_rel_for(new_rel)
                    os.makedirs(os.path.dirname(_abs_for(new_thumb_rel)), exist_ok=True)
                    os.replace(old_thumb_abs, _abs_for(new_thumb_rel))
                    patch["thumbPath"] = new_thumb_rel
                    patch["thumbUrl"] = _url_for(new_thumb_rel)

    ref.set(patch, merge=True)
    return _video_doc_to_payload(ref.get())

@router.delete("/{videoId}", dependencies=[Depends(require_roles(["admin"]))])
async def delete_video(videoId: str, hard: bool = Query(False)):
    ref = db.collection("videos").document(videoId)
    snap = ref.get()
    if not snap.exists: raise HTTPException(404, "Video not found")
    d = snap.to_dict() or {}

    if not hard:
        ref.set({"isArchived": True, "updatedAt": SERVER_TIMESTAMP}, merge=True)
        return {"ok": True, "archived": True}

    if d.get("storagePath"):
        try:
            absf = _abs_for(d["storagePath"])
            if os.path.isfile(absf): os.remove(absf)
        except Exception: pass
    if d.get("thumbPath"):
        try:
            abs_thumb = _abs_for(d["thumbPath"])
            if os.path.isfile(abs_thumb): os.remove(abs_thumb)
        except Exception: pass

    ref.delete()
    return {"ok": True, "deletedId": videoId}