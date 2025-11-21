from typing import List, Dict, Any, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from firebase_admin import firestore as admin_fs
from google.cloud.firestore_v1 import SERVER_TIMESTAMP

from app.deps.auth import require_roles, get_current_user

router = APIRouter()
db = admin_fs.client()

COL = "viseme_sets"

def _viseme_doc_to_payload(doc_snap) -> Dict[str, Any]:
    data = doc_snap.to_dict() or {}
    vid = doc_snap.id
    return {
        "id": vid,
        "name": data.get("name"),
        "language": data.get("language"),
        "mapping": data.get("mapping", {}),
        "references": data.get("references", []),
        "createdAt": data.get("createdAt"),
        "updatedAt": data.get("updatedAt"),
    }


@router.get(
    "",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def list_viseme_sets(
    q: Optional[str] = Query(None, description="search text to match in name"),
    limit: int = Query(100, ge=1, le=500),
):
    ref = db.collection(COL).limit(limit)
    snaps = list(ref.stream())

    items: List[Dict[str, Any]] = []
    for s in snaps:
        payload = _viseme_doc_to_payload(s)

        if q:
            name_val = (payload.get("name") or "").lower()
            if q.lower() not in name_val:
                continue

        items.append(payload)

    return {
        "items": items,
        "next_cursor": None,
    }


@router.post(
    "",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def create_viseme_set(
    body: Dict[str, Any],
    user=Depends(get_current_user),
):
    name = (body.get("name") or "").strip()
    language = (body.get("language") or "").strip()

    mapping = body.get("mapping") or {}
    refs = body.get("references") or []

    if not name:
        raise HTTPException(status_code=400, detail="name is required")
    if not language:
        raise HTTPException(status_code=400, detail="language is required")

    # Coerce types defensively
    if not isinstance(mapping, dict):
        raise HTTPException(status_code=400, detail="mapping must be an object")
    if not isinstance(refs, list):
        refs = [str(refs)]

    doc_ref = db.collection(COL).document()
    doc_ref.set(
        {
            "name": name,
            "language": language,
            "mapping": mapping,
            "references": refs,
            "createdAt": SERVER_TIMESTAMP,
            "updatedAt": SERVER_TIMESTAMP,
            "ownerId": user.get("uid"),
        }
    )

    snap = doc_ref.get()
    return _viseme_doc_to_payload(snap)