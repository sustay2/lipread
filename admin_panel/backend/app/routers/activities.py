from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Dict, Any, List, Optional
from firebase_admin import firestore as admin_fs
from google.cloud.firestore_v1 import SERVER_TIMESTAMP

from app.deps.auth import require_roles, get_current_user
from app.core.config import settings

router = APIRouter()
db = admin_fs.client()

def activity_doc_to_payload(doc_snap) -> Dict[str, Any]:
    data = doc_snap.to_dict() or {}
    data_out = {
        "id": doc_snap.id,
        "type": data.get("type"),
        "title": data.get("title"),
        "order": data.get("order", 0),
        "abVariant": data.get("abVariant"),
        "config": data.get("config", {}),
        "scoring": data.get("scoring", {}),
        "createdAt": data.get("createdAt"),
        "updatedAt": data.get("updatedAt"),
    }
    return data_out


def _lesson_activities_collection(
    course_id: str,
    module_id: str,
    lesson_id: str,
):
    return (
        db.collection("courses")
          .document(course_id)
          .collection("modules")
          .document(module_id)
          .collection("lessons")
          .document(lesson_id)
          .collection("activities")
    )


@router.get(
    "",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def list_activities(
    courseId: str = Query(..., description="courseId (required)"),
    moduleId: str = Query(..., description="moduleId (required)"),
    lessonId: str = Query(..., description="lessonId (required)"),
    limit: int = Query(100, ge=1, le=500),
    user=Depends(get_current_user),
):
    col_ref = _lesson_activities_collection(courseId, moduleId, lessonId)
    snaps = list(col_ref.order_by("order").limit(limit).stream())

    items = [activity_doc_to_payload(s) for s in snaps]
    return {"items": items, "next_cursor": None}


@router.post(
    "",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def create_activity(
    body: Dict[str, Any],
    courseId: str = Query(..., description="courseId (required)"),
    moduleId: str = Query(..., description="moduleId (required)"),
    lessonId: str = Query(..., description="lessonId (required)"),
    user=Depends(get_current_user),
):
    activity_type = body.get("type")
    if not activity_type:
        raise HTTPException(400, "Missing field 'type'.")

    title = body.get("title", "").strip()
    order_val = body.get("order", 0)
    ab_variant = body.get("abVariant")
    config = body.get("config", {})
    scoring = body.get("scoring", {})

    if activity_type == "quiz":
        if "bankId" not in config:
            raise HTTPException(400, "Quiz activity requires config.bankId")
        if "numQuestions" not in config:
            raise HTTPException(400, "Quiz activity requires config.numQuestions")

    doc_ref = _lesson_activities_collection(courseId, moduleId, lessonId).document()

    new_doc = {
        "type": activity_type,
        "title": title or None,
        "order": int(order_val),
        "abVariant": ab_variant or None,
        "config": config,
        "scoring": scoring,
        "createdAt": SERVER_TIMESTAMP,
        "updatedAt": SERVER_TIMESTAMP,
        "lessonRef": {
            "courseId": courseId,
            "moduleId": moduleId,
            "lessonId": lessonId,
        },
        "createdBy": user["uid"],
    }

    doc_ref.set(new_doc)

    snap = doc_ref.get()
    return activity_doc_to_payload(snap)

SUPPORTED_TYPES = {"quiz", "practice_lip", "dictation", "video_drill", "viseme_match", "mirror_practice"}

def _validate_activity_payload(body: dict):
    atype = (body.get("type") or "").lower()
    if atype not in SUPPORTED_TYPES:
        raise HTTPException(400, f"Unsupported activity type: {atype}")

    cfg = body.get("config") or {}
    scoring = body.get("scoring") or {}

    if atype == "quiz":
        bank_id = cfg.get("bankId") or cfg.get("questionBankId")
        if not bank_id:
            raise HTTPException(400, "quiz.config.bankId (or questionBankId) is required")
        if int(cfg.get("numQuestions", 0)) <= 0:
            raise HTTPException(400, "quiz.config.numQuestions must be > 0")

    elif atype == "practice_lip":
        if not (cfg.get("videoId") or cfg.get("mediaPath")):
            raise HTTPException(400, "practice_lip.config.videoId or mediaPath is required")
        if not (cfg.get("expected") or cfg.get("expectedPhones")):
            raise HTTPException(400, "practice_lip.config.expected (text) or expectedPhones is required")
        th = cfg.get("thresholds") or {}
        cfg["thresholds"] = {
            "cerMax": float(th.get("cerMax", 0.35)),
            "werMax": float(th.get("werMax", 0.45)),
            "visemeScoreMin": float(th.get("visemeScoreMin", 0.55)),
        }
        body["config"] = cfg

    elif atype == "dictation":
        if not (cfg.get("videoId") or cfg.get("mediaPath")):
            raise HTTPException(400, "dictation.config.videoId or mediaPath is required")
        if not cfg.get("answers") and not cfg.get("answerPattern"):
            raise HTTPException(400, "dictation.config.answers[] or answerPattern is required")
        cfg["maxChars"] = int(cfg.get("maxChars", 80))
        body["config"] = cfg

    weights = (scoring.get("weights") or {}) or {"score": 1.0}
    body["scoring"] = {"weights": weights, **({k: v for k, v in scoring.items() if k != "weights"})}