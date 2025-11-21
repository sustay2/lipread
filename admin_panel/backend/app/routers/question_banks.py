from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from typing import Dict, Any, List, Optional
import os, uuid, subprocess
from pathlib import Path

from firebase_admin import firestore as admin_fs
from google.cloud.firestore_v1 import SERVER_TIMESTAMP
from app.deps.auth import require_roles, get_current_user

router = APIRouter()
db = admin_fs.client()
COL = "question_banks"

# ---------------- Media config ----------------
MEDIA_ROOT = os.getenv("MEDIA_ROOT", "/data")
MEDIA_BASE_URL = os.getenv("MEDIA_BASE_URL", "http://api:8000/media")

QB_IMG_DIR = "qb/images"
QB_VID_DIR = "qb/videos/original"
QB_THUMB_DIR = "qb/videos/thumbs"

# Toggle resolving media into a light object on reads
RESOLVE_MEDIA = True

# ---------------- Helpers ----------------
def _url_for(rel_path: str) -> str:
    rel = str(rel_path).replace("\\", "/").lstrip("/")
    return f"{MEDIA_BASE_URL.rstrip('/')}/{rel}"

def _abs_for(rel_path: str) -> str:
    rel = str(rel_path).replace("\\", "/").lstrip("/")
    return os.path.join(MEDIA_ROOT, rel)

def _mkdir_parent(abs_path: str):
    Path(os.path.dirname(abs_path)).mkdir(parents=True, exist_ok=True)

def _is_video(name: str, ctype: Optional[str]) -> bool:
    if ctype and ctype.startswith("video/"):
        return True
    ext = (os.path.splitext(name)[1] or "").lower()
    return ext in [".mp4", ".mov", ".m4v", ".webm", ".avi", ".mkv"]

def _is_image(name: str, ctype: Optional[str]) -> bool:
    if ctype and ctype.startswith("image/"):
        return True
    ext = (os.path.splitext(name)[1] or "").lower()
    return ext in [".jpg", ".jpeg", ".png", ".webp", ".gif"]

def _ffmpeg_thumb(src_abs: str, out_abs: str) -> bool:
    """Render a thumbnail at ~0.5s into the video. Returns True if file exists."""
    _mkdir_parent(out_abs)
    cmd = [
        "ffmpeg", "-y",
        "-ss", "00:00:00.500",
        "-i", src_abs,
        "-vframes", "1",
        "-vf", "scale=480:-1",
        out_abs,
    ]
    try:
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return os.path.isfile(out_abs)
    except Exception:
        return False

def _norm_difficulty(val: Any, default: int = 1) -> int:
    """Normalize to 1..3 (1=Easy,2=Medium,3=Hard). Accepts label or int."""
    label_map = {"easy": 1, "medium": 2, "hard": 3}
    if isinstance(val, str):
        v = label_map.get(val.strip().lower(), None)
        if v is not None:
            return v
    try:
        v = int(val)
    except Exception:
        v = default
    if v < 1:
        v = 1
    if v > 3:
        v = 3
    return v

# -------- Firestore payload mappers --------
def _media_doc_to_payload(snap) -> Optional[Dict[str, Any]]:
    if not snap or not snap.exists:
        return None
    d = snap.to_dict() or {}
    return {
        "id": snap.id,
        "kind": d.get("kind"),  # "image" | "video"
        "url": d.get("url"),
        "storagePath": d.get("storagePath"),
        "thumbUrl": d.get("thumbUrl") or _url_for(d["thumbPath"]) if d.get("thumbPath") else None,
        "title": d.get("title"),
        "contentType": d.get("contentType"),
    }

def _bank_doc_to_payload(snap) -> Dict[str, Any]:
    d = snap.to_dict() or {}
    return {
        "id": snap.id,
        "title": d.get("title"),
        "topic": d.get("topic"),
        "difficulty": int(d.get("difficulty", 1)),  # 1..3
        "ownerId": d.get("ownerId"),
        "tags": d.get("tags", []),
        "createdAt": d.get("createdAt"),
        "updatedAt": d.get("updatedAt"),
        "isArchive": d.get("isArchive", False),
    }

def _question_doc_to_payload(snap) -> Dict[str, Any]:
    d = snap.to_dict() or {}
    payload = {
        "id": snap.id,
        "type": d.get("type", "mcq"),
        "stem": d.get("stem", ""),
        "options": d.get("options", []),
        "answers": d.get("answers", []),
        "answerPattern": d.get("answerPattern"),
        "explanation": d.get("explanation"),
        "tags": d.get("tags", []),
        "difficulty": _norm_difficulty(d.get("difficulty", 1)),  # 1..3
        "mediaId": d.get("mediaId"),  # <-- reference to /media
        "createdAt": d.get("createdAt"),
        "updatedAt": d.get("updatedAt"),
    }
    # Optionally resolve media for admin preview
    if RESOLVE_MEDIA and payload.get("mediaId"):
        try:
            msnap = db.collection("media").document(payload["mediaId"]).get()
            payload["media"] = _media_doc_to_payload(msnap)
        except Exception:
            payload["media"] = None
    return payload

def _validate_question_payload(q: Dict[str, Any]):
    qtype = (q.get("type") or "mcq").lower()
    stem = (q.get("stem") or "").strip()
    if not stem:
        raise HTTPException(400, "Question 'stem' is required.")
    if "difficulty" in q:
        _ = _norm_difficulty(q.get("difficulty", 1))
    if qtype in {"mcq"}:
        options = q.get("options") or []
        answers = q.get("answers") or []
        if not (isinstance(options, list) and len(options) >= 2):
            raise HTTPException(400, "MCQ needs at least 2 options.")
        if not (isinstance(answers, list) and len(answers) >= 1):
            raise HTTPException(400, "MCQ needs at least 1 answer.")
    elif qtype == "fitb":
        if not q.get("answers") and not q.get("answerPattern"):
            raise HTTPException(400, "FITB requires 'answers' or 'answerPattern'.")
    elif qtype == "open":
        pass
    else:
        raise HTTPException(400, f"Unsupported question type: {qtype}")

def _batch_delete_query(query_iter):
    batch = db.batch()
    count = 0
    for snap in query_iter:
        batch.delete(snap.reference)
        count += 1
        if count % 400 == 0:
            batch.commit()
            batch = db.batch()
    if count % 400 != 0:
        batch.commit()
    return count

# --------------- Media upload endpoint ---------------
@router.post(
    "/upload_media",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def upload_question_media(
    user = Depends(get_current_user),
    file: UploadFile = File(...),
):
    """
    Stores media under /media and returns its metadata (with id).
    - image -> qb/images/<id>_<name>
    - video -> qb/videos/original/<id>_<name> (+ optional thumb at qb/videos/thumbs/<id>.jpg)
    """
    uid = user["uid"]
    safe_name = file.filename.replace("/", "_").replace("\\", "_")
    fid = uuid.uuid4().hex[:20]

    if _is_image(safe_name, file.content_type):
        rel = f"{QB_IMG_DIR}/{fid}_{safe_name}"
        absf = _abs_for(rel)
        _mkdir_parent(absf)
        raw = await file.read()
        with open(absf, "wb") as f:
            f.write(raw)

        doc = {
            "storagePath": rel,
            "url": _url_for(rel),
            "title": safe_name,
            "contentType": file.content_type or "application/octet-stream",
            "uploadedBy": uid,
            "createdAt": SERVER_TIMESTAMP,
            "purpose": "question_bank",
            "kind": "image",
        }
        db.collection("media").document(fid).set(doc)

        return {"id": fid, **{k: v for k, v in doc.items() if k != "createdAt"}}

    # video
    rel = f"{QB_VID_DIR}/{fid}_{safe_name}"
    absf = _abs_for(rel)
    _mkdir_parent(absf)
    raw = await file.read()
    with open(absf, "wb") as f:
        f.write(raw)

    thumb_rel = f"{QB_THUMB_DIR}/{fid}.jpg"
    thumb_abs = _abs_for(thumb_rel)
    thumb_ok = _ffmpeg_thumb(absf, thumb_abs)

    doc = {
        "storagePath": rel,
        "url": _url_for(rel),
        "title": safe_name,
        "contentType": file.content_type or "application/octet-stream",
        "uploadedBy": uid,
        "createdAt": SERVER_TIMESTAMP,
        "purpose": "question_bank",
        "kind": "video",
        "thumbPath": thumb_rel if thumb_ok else None,
        "thumbUrl": _url_for(thumb_rel) if thumb_ok else None,
    }
    db.collection("media").document(fid).set(doc)

    # Return only JSON-serializable primitives
    out = {k: v for k, v in doc.items() if k != "createdAt"}
    out["id"] = fid
    return out

# ---------------- Banks CRUD ----------------
@router.get("", dependencies=[Depends(require_roles(["admin","content_editor","instructor"]))])
async def list_banks(q: Optional[str] = Query(None), limit: int = Query(100, ge=1, le=500)):
    ref = db.collection(COL).order_by("difficulty").limit(limit)
    snaps = list(ref.stream())
    out = []
    for s in snaps:
        b = _bank_doc_to_payload(s)
        if q and q.lower() not in (b.get("title") or "").lower():
            continue
        out.append(b)
    return out

@router.post("", dependencies=[Depends(require_roles(["admin","content_editor"]))])
async def create_bank(body: Dict[str, Any], user=Depends(get_current_user)):
    title = (body.get("title") or "").strip()
    if not title:
        raise HTTPException(400, "title is required")
    doc = {
        "title": title,
        "topic": body.get("topic"),
        "difficulty": _norm_difficulty(body.get("difficulty", 1)),
        "ownerId": user["uid"],
        "tags": body.get("tags", []),
        "isArchive": False,
        "createdAt": SERVER_TIMESTAMP,
        "updatedAt": SERVER_TIMESTAMP,
    }
    ref = db.collection(COL).document()
    ref.set(doc)
    return _bank_doc_to_payload(ref.get())

@router.get("/{bankId}", dependencies=[Depends(require_roles(["admin","content_editor","instructor"]))])
async def get_bank(bankId: str):
    snap = db.collection(COL).document(bankId).get()
    if not snap.exists:
        raise HTTPException(404, "Question bank not found")
    return _bank_doc_to_payload(snap)

@router.patch("/{bankId}", dependencies=[Depends(require_roles(["admin","content_editor"]))])
async def update_bank(bankId: str, patch: Dict[str, Any]):
    ref = db.collection(COL).document(bankId)
    if not ref.get().exists:
        raise HTTPException(404, "Question bank not found")
    data = {k: v for k, v in patch.items() if v is not None}
    if "difficulty" in data:
        data["difficulty"] = _norm_difficulty(data.get("difficulty", 1))
    data["updatedAt"] = SERVER_TIMESTAMP
    ref.set(data, merge=True)
    return _bank_doc_to_payload(ref.get())

@router.delete("/{bankId}", dependencies=[Depends(require_roles(["admin"]))])
async def delete_bank(bankId: str, hard: bool = False):
    ref = db.collection(COL).document(bankId)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(404, "Question bank not found")
    if hard:
        qref = ref.collection("questions").stream()
        deleted = _batch_delete_query(qref)
        ref.delete()
        return {"deleted": True, "hard": True, "questionsDeleted": deleted}
    else:
        ref.set({"isArchive": True, "updatedAt": SERVER_TIMESTAMP}, merge=True)
        return {"deleted": True, "hard": False}

# ---------------- Questions CRUD ----------------
def _extract_media_id_from_body(body: Dict[str, Any]) -> Optional[str]:
    """
    Accepts either:
      - "mediaId": "<id>"
      - legacy "media": {"id": "<id>", ...}
      - null to remove
    """
    if "mediaId" in body:
        return body.get("mediaId")
    m = body.get("media")
    if isinstance(m, dict):
        mid = m.get("id")
        return mid
    return None

@router.get("/{bankId}/questions", dependencies=[Depends(require_roles(["admin","content_editor","instructor"]))])
async def list_questions(bankId: str, limit: int = Query(500, ge=1, le=2000)):
    ref = db.collection(COL).document(bankId).collection("questions").order_by("createdAt").limit(limit)
    snaps = list(ref.stream())
    return [_question_doc_to_payload(s) for s in snaps]

@router.post("/{bankId}/questions", dependencies=[Depends(require_roles(["admin","content_editor"]))])
async def create_question(bankId: str, body: Dict[str, Any]):
    _validate_question_payload(body)
    qtype = (body.get("type") or "mcq").lower()
    media_id = _extract_media_id_from_body(body)

    doc = {
        "type": qtype,
        "stem": (body.get("stem") or "").strip(),
        "options": body.get("options", []),
        "answers": body.get("answers", []),
        "answerPattern": body.get("answerPattern"),
        "explanation": body.get("explanation"),
        "tags": body.get("tags", []),
        "difficulty": _norm_difficulty(body.get("difficulty", 1)),
        "mediaId": media_id or None,  # <-- only reference
        "createdAt": SERVER_TIMESTAMP,
        "updatedAt": SERVER_TIMESTAMP,
    }
    ref = db.collection(COL).document(bankId).collection("questions").document()
    ref.set(doc)
    return _question_doc_to_payload(ref.get())

@router.patch("/{bankId}/questions/{questionId}", dependencies=[Depends(require_roles(["admin","content_editor"]))])
async def update_question(bankId: str, questionId: str, patch: Dict[str, Any]):
    ref = db.collection(COL).document(bankId).collection("questions").document(questionId)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(404, "Question not found")

    # Normalize difficulty & validate if core fields changed
    if "difficulty" in patch:
        patch["difficulty"] = _norm_difficulty(patch.get("difficulty", 1))
    if any(k in patch for k in ("type","stem","options","answers","answerPattern","difficulty")):
        merged = {**(snap.to_dict() or {}), **patch}
        _validate_question_payload(merged)

    # Normalize media reference
    if "media" in patch or "mediaId" in patch:
        patch["mediaId"] = _extract_media_id_from_body(patch)

    # Remove legacy "media" if provided
    if "media" in patch:
        patch.pop("media", None)

    patch["updatedAt"] = SERVER_TIMESTAMP
    ref.set({k: v for k, v in patch.items() if k is not None}, merge=True)
    return _question_doc_to_payload(ref.get())

@router.delete("/{bankId}/questions/{questionId}", dependencies=[Depends(require_roles(["admin"]))])
async def delete_question(bankId: str, questionId: str):
    ref = db.collection(COL).document(bankId).collection("questions").document(questionId)
    if not ref.get().exists:
        raise HTTPException(404, "Question not found")
    ref.delete()
    return {"deleted": True}

@router.post("/{bankId}/questions:bulk_delete", dependencies=[Depends(require_roles(["admin"]))])
async def bulk_delete_questions(bankId: str, body: Dict[str, Any]):
    ids: List[str] = body.get("ids") or []
    if not ids:
        raise HTTPException(400, "ids[] required")
    batch = db.batch()
    count = 0
    for qid in ids:
        ref = db.collection(COL).document(bankId).collection("questions").document(qid)
        batch.delete(ref)
        count += 1
        if count % 400 == 0:
            batch.commit()
            batch = db.batch()
    if count % 400 != 0:
        batch.commit()
    return {"deleted": count}

# ---------------- Export / Import ----------------
@router.get("/{bankId}/export", dependencies=[Depends(require_roles(["admin","content_editor"]))])
async def export_bank(bankId: str):
    bank_snap = db.collection(COL).document(bankId).get()
    if not bank_snap.exists:
        raise HTTPException(404, "Question bank not found")
    bank = _bank_doc_to_payload(bank_snap)
    qs = list(db.collection(COL).document(bankId).collection("questions").stream())
    questions = [_question_doc_to_payload(s) for s in qs]
    return {"bank": bank, "questions": questions}

@router.post("/{bankId}/import", dependencies=[Depends(require_roles(["admin","content_editor"]))])
async def import_questions(bankId: str, body: Dict[str, Any]):
    mode = (body.get("mode") or "append").lower()
    qlist: List[Dict[str, Any]] = body.get("questions") or []
    if not isinstance(qlist, list) or not qlist:
        raise HTTPException(400, "questions[] required")

    ref = db.collection(COL).document(bankId)
    if not ref.get().exists:
        raise HTTPException(404, "Question bank not found")

    replaced = 0
    if mode == "replace":
        qref = ref.collection("questions").stream()
        replaced = _batch_delete_query(qref)

    imported = 0
    batch = db.batch()
    count = 0
    qcol = ref.collection("questions")

    for q in qlist:
        _validate_question_payload(q)
        doc = {
            "type": (q.get("type") or "mcq").lower(),
            "stem": (q.get("stem") or "").strip(),
            "options": q.get("options", []),
            "answers": q.get("answers", []),
            "answerPattern": q.get("answerPattern"),
            "explanation": q.get("explanation"),
            "tags": q.get("tags", []),
            "difficulty": _norm_difficulty(q.get("difficulty", 1)),
            # Only store reference:
            "mediaId": _extract_media_id_from_body(q) or None,
            "createdAt": SERVER_TIMESTAMP,
            "updatedAt": SERVER_TIMESTAMP,
        }
        qref = qcol.document()
        batch.set(qref, doc)
        count += 1
        imported += 1
        if count % 400 == 0:
            batch.commit()
            batch = db.batch()
    if count % 400 != 0:
        batch.commit()

    return {"imported": imported, "replaced": replaced, "mode": mode}