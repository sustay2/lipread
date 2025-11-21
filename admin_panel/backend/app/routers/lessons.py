from typing import Any, Dict, List
from fastapi import APIRouter, Depends, HTTPException, Query, Body
from firebase_admin import firestore as admin_fs
from google.cloud.firestore_v1 import SERVER_TIMESTAMP
from google.api_core.exceptions import FailedPrecondition
from app.deps.auth import require_roles, get_current_user

router = APIRouter()
db = admin_fs.client()
COL = "lessons"

def _payload(snap) -> Dict[str, Any]:
    d = snap.to_dict() or {}
    return {
        "id": snap.id,
        "courseId": d.get("courseId"),
        "moduleId": d.get("moduleId"),
        "title": d.get("title"),
        "order": d.get("order", 0),
        "objectives": d.get("objectives", []),
        "estimatedMin": d.get("estimatedMin", 5),
        "isArchived": d.get("isArchived", False),
        "createdAt": d.get("createdAt"),
        "updatedAt": d.get("updatedAt"),
    }

def _normalize_orders(course_id: str, module_id: str):
    snaps = list(
        db.collection(COL)
          .where("courseId", "==", course_id)
          .where("moduleId", "==", module_id)
          .order_by("order")
          .stream()
    )
    batch = db.batch()
    for idx, s in enumerate(snaps):
        batch.update(s.reference, {"order": idx, "updatedAt": SERVER_TIMESTAMP})
    batch.commit()

@router.get("", dependencies=[Depends(get_current_user)])
async def list_lessons(
    courseId: str = Query(..., alias="courseId"),
    moduleId: str = Query(..., alias="moduleId"),
    includeArchived: bool = Query(False),
):
    try:
        q = (
            db.collection(COL)
              .where("courseId", "==", courseId)
              .where("moduleId", "==", moduleId)
              .order_by("order")
        )
        snaps = list(q.stream())
    except FailedPrecondition as e:
        raise HTTPException(
            500,
            "The query needs a composite index (courseId ==, moduleId ==, order). "
            f"Create from the Firebase error link in logs. Details: {e.message}"
        )

    items = []
    for s in snaps:
        p = _payload(s)
        if includeArchived or not p.get("isArchived", False):
            items.append(p)
    return items

@router.post("", dependencies=[Depends(require_roles(["admin", "content_editor"]))])
async def create_lesson(
    courseId: str = Query(..., alias="courseId"),
    moduleId: str = Query(..., alias="moduleId"),
    body: Dict[str, Any] = Body(...)
):
    title = (body.get("title") or "").strip()
    if not title:
        raise HTTPException(400, "title is required")

    count = db.collection(COL)\
        .where("courseId", "==", courseId)\
        .where("moduleId", "==", moduleId)\
        .get()
    next_order = len(count)

    doc = {
        "courseId": courseId,
        "moduleId": moduleId,
        "title": title,
        "order": next_order,
        "objectives": body.get("objectives", []),
        "estimatedMin": int(body.get("estimatedMin", 5)),
        "isArchived": False,
        "createdAt": SERVER_TIMESTAMP,
        "updatedAt": SERVER_TIMESTAMP,
    }
    ref = db.collection(COL).document()
    ref.set(doc)
    return _payload(ref.get())

@router.patch("/{lessonId}", dependencies=[Depends(require_roles(["admin", "content_editor"]))])
async def update_lesson(lessonId: str, body: Dict[str, Any]):
    ref = db.collection(COL).document(lessonId)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(404, "Lesson not found")

    allowed_keys = ["title", "estimatedMin", "objectives", "isArchived"]
    patch = {k: body[k] for k in allowed_keys if k in body}
    if not patch:
        return _payload(snap)

    patch["updatedAt"] = SERVER_TIMESTAMP
    ref.update(patch)
    return _payload(ref.get())

@router.delete("/{lessonId}", dependencies=[Depends(require_roles(["admin"]))])
async def delete_lesson(lessonId: str):
    ref = db.collection(COL).document(lessonId)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(404, "Lesson not found")
    d = snap.to_dict() or {}
    course_id, module_id = d.get("courseId"), d.get("moduleId")

    ref.delete()
    if course_id and module_id:
        _normalize_orders(course_id, module_id)
    return {"ok": True, "deletedId": lessonId}

@router.post("/reorder", dependencies=[Depends(require_roles(["admin", "content_editor"]))])
async def reorder_lessons(
    courseId: str = Query(..., alias="courseId"),
    moduleId: str = Query(..., alias="moduleId"),
    body: Dict[str, Any] = Body(...)
):
    ids: List[str] = body.get("ids") or []
    if not ids:
        raise HTTPException(400, "ids (list) is required")

    snaps = db.collection(COL)\
        .where("courseId", "==", courseId)\
        .where("moduleId", "==", moduleId)\
        .get()
    existing_ids = {s.id for s in snaps}
    if set(ids) - existing_ids:
        raise HTTPException(400, "ids contain lessons not in this module")

    batch = db.batch()
    for idx, lid in enumerate(ids):
        batch.update(db.collection(COL).document(lid), {"order": idx, "updatedAt": SERVER_TIMESTAMP})
    batch.commit()
    return {"ok": True}