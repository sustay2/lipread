from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from passlib.context import CryptContext
from google.cloud.firestore_v1 import SERVER_TIMESTAMP

from app.services.firebase_client import get_firestore_client


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
db = get_firestore_client()

ADMIN_COLLECTION = os.getenv("ADMIN_COLLECTION", "admins")


def _to_datetime(value: Any) -> Optional[datetime]:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    if hasattr(value, "timestamp"):
        try:
            return datetime.fromtimestamp(value.timestamp(), tz=timezone.utc)
        except Exception:
            return None
    return None


def _map_admin(doc) -> Optional[Dict[str, Any]]:
    if not doc:
        return None
    data = doc.to_dict() if hasattr(doc, "to_dict") else dict(doc or {})
    if data is None:
        data = {}
    data["id"] = getattr(doc, "id", data.get("id"))
    created_at = _to_datetime(data.get("createdAt"))
    updated_at = _to_datetime(data.get("updatedAt"))
    if created_at:
        data["createdAt"] = created_at
    if updated_at:
        data["updatedAt"] = updated_at
    return data


def get_admin_by_email(email: str) -> Optional[Dict[str, Any]]:
    normalized_email = (email or "").strip().lower()
    if not normalized_email:
        return None

    snaps = (
        db.collection(ADMIN_COLLECTION)
        .where("email", "==", normalized_email)
        .limit(1)
        .get()
    )

    if not snaps:
        return None

    snap = snaps[0]
    return _map_admin(snap)


def get_admin_by_id(admin_id: str | None) -> Optional[Dict[str, Any]]:
    if not admin_id:
        return None
    ref = db.collection(ADMIN_COLLECTION).document(admin_id)
    doc = ref.get()
    if not doc.exists:
        return None
    return _map_admin(doc)


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return pwd_context.verify(password, password_hash)
    except Exception:
        return False


def verify_admin_credentials(email: str, password: str) -> Optional[Dict[str, Any]]:
    admin_doc = get_admin_by_email(email)
    if not admin_doc:
        return None

    stored_hash = admin_doc.get("passwordHash")
    if not stored_hash or not verify_password(password, stored_hash):
        return None

    return admin_doc


def update_admin_profile(admin_id: str, display_name: Optional[str], photo_url: Optional[str]) -> Optional[Dict[str, Any]]:
    if not admin_id:
        return None
    ref = db.collection(ADMIN_COLLECTION).document(admin_id)
    doc = ref.get()
    if not doc.exists:
        return None

    update: Dict[str, Any] = {"updatedAt": SERVER_TIMESTAMP}
    if display_name is not None:
        update["name"] = display_name.strip()
        update["displayName"] = display_name.strip()
    if photo_url is not None:
        update["photoURL"] = photo_url.strip() or None

    ref.set(update, merge=True)
    return get_admin_by_id(admin_id)


def update_admin_password(admin_id: str, new_password: str) -> bool:
    if not admin_id or not new_password:
        return False
    ref = db.collection(ADMIN_COLLECTION).document(admin_id)
    doc = ref.get()
    if not doc.exists:
        return False
    password_hash = hash_password(new_password)
    ref.update({"passwordHash": password_hash, "updatedAt": SERVER_TIMESTAMP})
    return True
