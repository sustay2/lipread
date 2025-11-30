from __future__ import annotations

import os
from typing import Any, Dict, Optional

from passlib.context import CryptContext

from app.services.firebase_client import get_firestore_client


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
db = get_firestore_client()

ADMIN_COLLECTION = os.getenv("ADMIN_COLLECTION", "admins")


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
    data = snap.to_dict() or {}
    data["id"] = snap.id
    return data


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
