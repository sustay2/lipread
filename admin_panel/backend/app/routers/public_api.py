from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from google.api_core.exceptions import FailedPrecondition

from app.deps.auth import get_current_user
from app.services.activities import activity_service
from app.services.firebase_client import get_firestore_client

router = APIRouter()
db = get_firestore_client()


def _course_payload(doc_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": doc_id,
        "title": data.get("title"),
        "slug": data.get("slug"),
        "level": data.get("level"),
        "description": data.get("description"),
        "tags": data.get("tags", []),
        "thumbnailPath": data.get("thumbnailPath"),
        "thumbnailUrl": data.get("thumbnailUrl"),
        "thumbnail": data.get("thumbnail"),
        "mediaId": data.get("mediaId"),
        "published": data.get("published", False),
        "version": data.get("version", 1),
        "createdBy": data.get("createdBy"),
        "createdAt": data.get("createdAt"),
        "updatedAt": data.get("updatedAt"),
    }


def _module_payload(doc_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": doc_id,
        "courseId": data.get("courseId"),
        "title": data.get("title"),
        "summary": data.get("summary"),
        "order": data.get("order", 0),
        "isArchived": data.get("isArchived", False),
        "createdAt": data.get("createdAt"),
        "updatedAt": data.get("updatedAt"),
    }


def _lesson_payload(doc_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": doc_id,
        "courseId": data.get("courseId"),
        "moduleId": data.get("moduleId"),
        "title": data.get("title"),
        "order": data.get("order", 0),
        "objectives": data.get("objectives", []),
        "estimatedMin": data.get("estimatedMin", 5),
        "isArchived": data.get("isArchived", False),
        "createdAt": data.get("createdAt"),
        "updatedAt": data.get("updatedAt"),
    }


@router.get("/courses")
async def api_list_courses(
    q: Optional[str] = Query(None),
    includeUnpublished: bool = Query(False, description="Include unpublished courses"),
    limit: int = Query(100, ge=1, le=500),
    user=Depends(get_current_user),
):
    ref = db.collection("courses").limit(limit)
    snaps = list(ref.stream())

    items: List[Dict[str, Any]] = []
    for s in snaps:
        data = s.to_dict() or {}
        payload = _course_payload(s.id, data)

        if not includeUnpublished and not payload.get("published", False):
            continue
        if q:
            title_lc = (payload.get("title") or "").lower()
            if q.lower() not in title_lc:
                continue
        items.append(payload)

    # Sort newest first to mirror the admin and Home screen ordering
    items.sort(key=lambda i: i.get("createdAt") or 0, reverse=True)
    return {"items": items, "next_cursor": None}


@router.get("/courses/{courseId}/modules")
async def api_list_modules(
    courseId: str,
    includeArchived: bool = Query(False),
    user=Depends(get_current_user),
):
    try:
        query = (
            db.collection("modules")
            .where("courseId", "==", courseId)
            .order_by("order")
        )
        snaps = list(query.stream())
    except FailedPrecondition as e:
        raise HTTPException(
            500,
            "The query requires a composite index (courseId + order). "
            f"Create the suggested index from the Firebase error link in logs. Details: {e.message}",
        )

    modules: List[Dict[str, Any]] = []
    for s in snaps:
        payload = _module_payload(s.id, s.to_dict() or {})
        if includeArchived or not payload.get("isArchived", False):
            modules.append(payload)
    return modules


@router.get("/modules/{moduleId}/lessons")
async def api_list_lessons(
    moduleId: str,
    includeArchived: bool = Query(False),
    user=Depends(get_current_user),
):
    module_snap = db.collection("modules").document(moduleId).get()
    if not module_snap.exists:
        raise HTTPException(404, "Module not found")

    module_data = module_snap.to_dict() or {}
    course_id = module_data.get("courseId")
    if not course_id:
        raise HTTPException(400, "Module is missing courseId")

    try:
        query = (
            db.collection("lessons")
            .where("courseId", "==", course_id)
            .where("moduleId", "==", moduleId)
            .order_by("order")
        )
        snaps = list(query.stream())
    except FailedPrecondition as e:
        raise HTTPException(
            500,
            "The query needs a composite index (courseId ==, moduleId ==, order). "
            f"Create from the Firebase error link in logs. Details: {e.message}",
        )

    lessons: List[Dict[str, Any]] = []
    for s in snaps:
        payload = _lesson_payload(s.id, s.to_dict() or {})
        if includeArchived or not payload.get("isArchived", False):
            lessons.append(payload)
    return lessons


@router.get("/lessons/{lessonId}/activities")
async def api_list_activities(lessonId: str, user=Depends(get_current_user)):
    lesson_snap = db.collection("lessons").document(lessonId).get()
    if not lesson_snap.exists:
        raise HTTPException(404, "Lesson not found")

    lesson_data = lesson_snap.to_dict() or {}
    course_id = lesson_data.get("courseId")
    module_id = lesson_data.get("moduleId")
    if not course_id or not module_id:
        raise HTTPException(400, "Lesson is missing courseId or moduleId")

    activities = activity_service.list_activities(course_id, module_id, lessonId)
    activities = sorted(activities, key=lambda a: a.order)
    return {
        "items": [
            {
                "id": a.id,
                "title": a.title,
                "type": a.type,
                "order": a.order,
                "config": a.config,
                "scoring": a.scoring,
                "itemCount": a.itemCount,
                "createdAt": a.createdAt,
                "updatedAt": a.updatedAt,
            }
            for a in activities
        ],
        "next_cursor": None,
    }


@router.get("/activities/{activityId}")
async def api_get_activity(
    activityId: str,
    courseId: Optional[str] = Query(None),
    moduleId: Optional[str] = Query(None),
    lessonId: Optional[str] = Query(None),
    user=Depends(get_current_user),
):
    course_id = courseId
    module_id = moduleId
    lesson_id = lessonId

    if not (course_id and module_id and lesson_id):
        # Fallback: attempt to resolve via lessons collection if lessonId is known
        if lesson_id and (not course_id or not module_id):
            lesson_snap = db.collection("lessons").document(lesson_id).get()
            if lesson_snap.exists:
                lesson_data = lesson_snap.to_dict() or {}
                course_id = course_id or lesson_data.get("courseId")
                module_id = module_id or lesson_data.get("moduleId")

    if not (course_id and module_id and lesson_id):
        raise HTTPException(400, "courseId, moduleId, and lessonId are required")

    activity = activity_service.get_activity(course_id, module_id, lesson_id, activityId)
    if not activity:
        raise HTTPException(404, "Activity not found")
    # Ensure dataclasses are serialized
    questions = [q.__dict__ for q in activity.get("questions", [])]
    return {**activity, "questions": questions}
