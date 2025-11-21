from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Dict, Any, List, Optional
from firebase_admin import firestore as admin_fs
from google.cloud.firestore_v1 import SERVER_TIMESTAMP

from app.deps.auth import require_roles, get_current_user

router = APIRouter()
db = admin_fs.client()

COL = "courses"


def _course_payload(doc_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": doc_id,
        "title": data.get("title"),
        "slug": data.get("slug"),
        "level": data.get("level"),
        "description": data.get("description"),
        "tags": data.get("tags", []),
        "thumbnailPath": data.get("thumbnailPath"),
        "published": data.get("published", False),
        "version": data.get("version", 1),
        "createdBy": data.get("createdBy"),
        "createdAt": data.get("createdAt"),
        "updatedAt": data.get("updatedAt"),
    }


@router.get(
    "",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def list_courses(
    q: Optional[str] = Query(None),
    limit: int = Query(100, ge=1, le=500),
):
    ref = db.collection(COL).limit(limit)
    snaps = list(ref.stream())

    items: List[Dict[str, Any]] = []
    for s in snaps:
        data = s.to_dict() or {}
        item = _course_payload(s.id, data)

        if q:
            # filter locally by case-insensitive partial match in title
            title_lc = (item.get("title") or "").lower()
            if q.lower() not in title_lc:
                continue

        items.append(item)

    return {"items": items, "next_cursor": None}


@router.post(
    "",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def create_course(
    body: Dict[str, Any],
    user=Depends(get_current_user),
):
    title = (body.get("title") or "").strip()
    if not title:
        raise HTTPException(400, "title is required")

    now = SERVER_TIMESTAMP

    doc_ref = db.collection(COL).document()
    doc_ref.set(
        {
            "title": title,
            "slug": body.get("slug"),
            "level": body.get("level"),
            "description": body.get("description"),
            "tags": body.get("tags", []),
            "thumbnailPath": body.get("thumbnailPath"),
            "published": bool(body.get("published", False)),
            "version": int(body.get("version", 1)),
            "createdBy": user.get("uid"),
            "createdAt": now,
            "updatedAt": now,
        }
    )

    snap = doc_ref.get()
    data = snap.to_dict() or {}
    return _course_payload(snap.id, data)