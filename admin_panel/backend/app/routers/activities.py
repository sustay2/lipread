from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from app.deps.auth import get_current_user, require_roles
from app.services.activities import activity_service
from app.services.question_banks import question_bank_service

router = APIRouter()


def _validate_scoring(scoring: Dict[str, Any]) -> Dict[str, Any]:
    max_score = int(scoring.get("maxScore", 100)) if scoring else 100
    passing = int(scoring.get("passingScore", max_score))
    weights = scoring.get("weights") or {"score": 1.0}
    return {"maxScore": max_score, "passingScore": passing, "weights": weights}


def _ensure_questions(bank_id: Optional[str], question_ids: List[str]):
    if not bank_id:
        raise HTTPException(400, "questionBankId is required when attaching questions")
    missing: List[str] = []
    for qid in question_ids:
        if not question_bank_service.get_question(bank_id, qid):
            missing.append(qid)
    if missing:
        raise HTTPException(404, f"Questions not found in bank {bank_id}: {', '.join(missing)}")


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
    items = activity_service.list_activities(courseId, moduleId, lessonId)
    items = sorted(items, key=lambda a: a.order)[:limit]
    return {
        "items": [
            {
                "id": a.id,
                "title": a.title,
                "type": a.type,
                "order": a.order,
                "config": a.config,
                "scoring": a.scoring,
                "questionCount": a.questionCount,
                "createdAt": a.createdAt,
                "updatedAt": a.updatedAt,
            }
            for a in items
        ],
        "next_cursor": None,
    }


@router.get(
    "/{activityId}",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def get_activity(
    activityId: str,
    courseId: str = Query(...),
    moduleId: str = Query(...),
    lessonId: str = Query(...),
    user=Depends(get_current_user),
):
    activity = activity_service.get_activity(courseId, moduleId, lessonId, activityId)
    if not activity:
        raise HTTPException(404, "Activity not found")
    return activity


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
    activity_type = (body.get("type") or "").strip()
    if not activity_type:
        raise HTTPException(400, "Missing field 'type'.")

    title = (body.get("title") or activity_type).strip()
    order_val = int(body.get("order") or 0)
    scoring = _validate_scoring(body.get("scoring") or {})
    config = body.get("config") or {}
    bank_id = config.get("questionBankId") or body.get("questionBankId")
    question_ids = body.get("questionIds") or []
    embed_questions = bool(config.get("embedQuestions") or body.get("embedQuestions", False))

    if question_ids:
        _ensure_questions(bank_id, question_ids)

    activity_id = activity_service.create_activity(
        courseId,
        moduleId,
        lessonId,
        title=title,
        type=activity_type,
        order=order_val,
        scoring=scoring,
        config=config,
        question_bank_id=bank_id,
        question_ids=question_ids,
        embed_questions=embed_questions,
        ab_variant=body.get("abVariant"),
        created_by=user["uid"],
    )

    return activity_service.get_activity(courseId, moduleId, lessonId, activity_id)


@router.put(
    "/{activityId}",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def update_activity(
    activityId: str,
    body: Dict[str, Any],
    courseId: str = Query(..., description="courseId (required)"),
    moduleId: str = Query(..., description="moduleId (required)"),
    lessonId: str = Query(..., description="lessonId (required)"),
    user=Depends(get_current_user),
):
    activity_type = (body.get("type") or "").strip()
    if not activity_type:
        raise HTTPException(400, "Missing field 'type'.")

    title = (body.get("title") or activity_type).strip()
    order_val = int(body.get("order") or 0)
    scoring = _validate_scoring(body.get("scoring") or {})
    config = body.get("config") or {}
    bank_id = config.get("questionBankId") or body.get("questionBankId")
    question_ids = body.get("questionIds") or []
    embed_questions = bool(config.get("embedQuestions") or body.get("embedQuestions", False))

    if question_ids:
        _ensure_questions(bank_id, question_ids)

    updated = activity_service.update_activity(
        courseId,
        moduleId,
        lessonId,
        activityId,
        title=title,
        type=activity_type,
        order=order_val,
        scoring=scoring,
        config=config,
        question_bank_id=bank_id,
        question_ids=question_ids,
        embed_questions=embed_questions,
        ab_variant=body.get("abVariant"),
    )
    if not updated:
        raise HTTPException(404, "Activity not found")

    return activity_service.get_activity(courseId, moduleId, lessonId, activityId)


@router.delete(
    "/{activityId}",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def delete_activity(
    activityId: str,
    courseId: str = Query(..., description="courseId (required)"),
    moduleId: str = Query(..., description="moduleId (required)"),
    lessonId: str = Query(..., description="lessonId (required)"),
    user=Depends(get_current_user),
):
    ok = activity_service.delete_activity(courseId, moduleId, lessonId, activityId)
    if not ok:
        raise HTTPException(404, "Activity not found")
    return {"status": "deleted"}
