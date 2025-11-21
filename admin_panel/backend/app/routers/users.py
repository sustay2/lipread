from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Optional, List, Dict, Any
from firebase_admin import firestore as admin_fs
from google.cloud.firestore_v1 import SERVER_TIMESTAMP
from app.deps.auth import require_roles, get_current_user

router = APIRouter()
db = admin_fs.client()
COL = "users"

def _collect_roles_for_uid(uid: str) -> List[str]:
    out: List[str] = []
    role_docs = (
        db.collection(COL)
          .document(uid)
          .collection("roles")
          .stream()
    )
    for rdoc in role_docs:
        rdata = rdoc.to_dict() or {}
        role_val = rdata.get("role")
        if role_val:
            out.append(str(role_val).strip().lower())
    return out

def _user_doc_to_payload(doc_snap) -> Dict[str, Any]:
    data = doc_snap.to_dict() or {}
    uid = doc_snap.id
    roles = _collect_roles_for_uid(uid)

    return {
        "id": uid,
        "email": data.get("email"),
        "displayName": data.get("displayName"),
        "photoURL": data.get("photoURL"),
        "locale": data.get("locale", "en"),
        "roles": roles,
        "createdAt": data.get("createdAt"),
        "lastActiveAt": data.get("lastActiveAt"),
    }

@router.get(
    "",
    dependencies=[Depends(require_roles(["admin","content_editor"]))],
)
async def list_users(
    q: Optional[str] = Query(None, description="filter by email substring (case-insensitive)"),
    limit: int = Query(25, ge=1, le=100),
    cursor: Optional[str] = Query(None, description="email to start AFTER"),
):
    col_ref = db.collection(COL)

    snaps_iter = col_ref.stream()
    all_docs = []
    for s in snaps_iter:
        u = _user_doc_to_payload(s)
        if q and q.lower() not in ((u.get("email") or "").lower()):
            continue
        all_docs.append(u)

    all_docs.sort(key=lambda row: (row.get("email") or "").lower())

    if cursor:
        cursor_lower = cursor.lower()
        all_docs = [u for u in all_docs if (u.get("email") or "").lower() > cursor_lower]

    page = all_docs[: limit + 1]

    if len(page) > limit:
        next_cursor_val = page[-1].get("email")
        page = page[:limit]
    else:
        next_cursor_val = None

    return {
        "items": page,
        "next_cursor": next_cursor_val,
    }

@router.get("/me/roles")
async def my_roles(user = Depends(get_current_user)):
    uid = user["uid"]
    roles = _collect_roles_for_uid(uid)
    return {"uid": uid, "roles": roles}

@router.post(
    "",
    dependencies=[Depends(require_roles(["admin"]))],
)
async def create_user(body: Dict[str, Any]):
    from firebase_admin import auth as admin_auth

    email = body.get("email")
    password = body.get("password")
    display_name = body.get("displayName")
    new_roles = body.get("roles", [])

    if not email or not password:
        raise HTTPException(400, detail="email and password are required")

    try:
        user_rec = admin_auth.create_user(
            email=email,
            password=password,
            display_name=display_name or None,
            disabled=False,
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Auth create failed: {e}")

    uid = user_rec.uid

    base_doc = {
        "email": email,
        "displayName": display_name or user_rec.display_name or None,
        "photoURL": user_rec.photo_url or None,
        "locale": "en",
        "createdAt": SERVER_TIMESTAMP,
        "updatedAt": SERVER_TIMESTAMP,
    }
    db.collection(COL).document(uid).set(base_doc, merge=True)

    for role_val in new_roles:
        role_clean = str(role_val).strip().lower()
        role_doc = (
            db.collection(COL)
              .document(uid)
              .collection("roles")
              .document()
        )
        role_doc.set({
            "role": role_clean,
            "grantedBy": "system",
            "grantedAt": SERVER_TIMESTAMP,
        })

    snap = db.collection(COL).document(uid).get()
    return _user_doc_to_payload(snap)