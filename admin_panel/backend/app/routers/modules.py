from typing import Any, Dict, List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, Body
from firebase_admin import firestore as admin_fs
from google.cloud.firestore_v1 import SERVER_TIMESTAMP
from google.api_core.exceptions import FailedPrecondition
from app.deps.auth import require_roles, get_current_user

router = APIRouter()
db = admin_fs.client()
COL = "modules"

def _module_payload(snap) -> Dict[str, Any]:
    d = snap.to_dict() or {}
    d["id"] = snap.id
    return {
        "id": snap.id,
        "courseId": d.get("courseId"),
        "title": d.get("title"),
        "summary": d.get("summary"),
        "order": d.get("order", 0),
        "isArchived": d.get("isArchived", False),
        "createdAt": d.get("createdAt"),
        "updatedAt": d.get("updatedAt"),
    }

def _normalize_orders(course_id: str):
    snaps = list(
        db.collection(COL)
          .where("courseId", "==", course_id)
          .order_by("order")
          .stream()
    )
    batch = db.batch()
    for idx, s in enumerate(snaps):
        ref = db.collection(COL).document(s.id)
        batch.update(ref, {"order": idx, "updatedAt": SERVER_TIMESTAMP})
    batch.commit()

@router.get(
    "",
    dependencies=[Depends(get_current_user)]
)
async def list_modules(
    courseId: str = Query(..., alias="courseId"),
    includeArchived: bool = Query(False),
):
    try:
        q = (
            db.collection(COL)
            .where("courseId", "==", courseId)
            .order_by("order")
        )
        snaps = list(q.stream())
    except FailedPrecondition as e:
        raise HTTPException(
            500,
            f"The query requires a composite index (courseId + order). "
            f"Create the suggested index from the Firebase error link in logs. Details: {e.message}"
        )

    items = []
    for s in snaps:
        p = _module_payload(s)
        if includeArchived or not p.get("isArchived", False):
            items.append(p)
    return items

@router.post(
    "",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))]
)
async def create_module(
    courseId: str = Query(..., alias="courseId"),
    body: Dict[str, Any] = Body(...)
):
    title = (body.get("title") or "").strip()
    summary = (body.get("summary") or None)
    if not title:
        raise HTTPException(400, "title is required")

    count = db.collection(COL).where("courseId", "==", courseId).get()
    next_order = len(count)

    doc = {
        "courseId": courseId,
        "title": title,
        "summary": summary,
        "order": next_order,
        "isArchived": False,
        "createdAt": SERVER_TIMESTAMP,
        "updatedAt": SERVER_TIMESTAMP,
    }
    ref = db.collection(COL).document()
    ref.set(doc)
    snap = ref.get()
    return _module_payload(snap)

@router.patch(
    "/{moduleId}",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))]
)
async def update_module(moduleId: str, body: Dict[str, Any]):
    ref = db.collection(COL).document(moduleId)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(404, "Module not found")

    allowed = {k: v for k, v in body.items() if k in ["title", "summary", "isArchived"]}
    if not allowed:
        return _module_payload(snap)

    allowed["updatedAt"] = SERVER_TIMESTAMP
    ref.update(allowed)
    return _module_payload(ref.get())

@router.delete(
    "/{moduleId}",
    dependencies=[Depends(require_roles(["admin"]))]
)
async def delete_module(moduleId: str):
    ref = db.collection(COL).document(moduleId)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(404, "Module not found")

    course_id = snap.to_dict().get("courseId")
    ref.delete()
    if course_id:
        _normalize_orders(course_id)
    return {"ok": True, "deletedId": moduleId}

@router.post(
    "/reorder",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))]
)
async def reorder_modules(
    courseId: str = Query(..., alias="courseId"),
    body: Dict[str, Any] = Body(...)
):
    ids: List[str] = body.get("ids") or []
    if not ids:
        raise HTTPException(400, "ids (list) is required")

    snaps = db.collection(COL).where("courseId", "==", courseId).get()
    existing_ids = {s.id for s in snaps}
    if set(ids) - existing_ids:
        raise HTTPException(400, "ids contain modules not in this course")

    batch = db.batch()
    for idx, mid in enumerate(ids):
        batch.update(db.collection(COL).document(mid), {"order": idx, "updatedAt": SERVER_TIMESTAMP})
    batch.commit()
    return {"ok": True}