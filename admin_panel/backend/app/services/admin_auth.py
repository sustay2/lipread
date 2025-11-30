from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
import hashlib
import secrets
from typing import Any, Dict, Optional, Tuple

from passlib.context import CryptContext
from google.cloud.firestore_v1 import SERVER_TIMESTAMP
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
from firebase_admin import auth
import requests

from app.services.firebase_client import get_firestore_client
from app.services.firebase_client import get_firebase_app


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
db = get_firestore_client()

ADMIN_COLLECTION = os.getenv("ADMIN_COLLECTION", "admins")
RESET_COLLECTION = os.getenv("ADMIN_RESET_COLLECTION", "admin_password_resets")
RESET_SECRET = os.getenv("ADMIN_RESET_SECRET") or os.getenv("ADMIN_SESSION_SECRET", "change-me-please")
RESET_TOKEN_TTL = int(os.getenv("ADMIN_RESET_TOKEN_TTL", str(3600)))
RESET_SALT = "admin-password-reset"

reset_serializer = URLSafeTimedSerializer(RESET_SECRET, salt=RESET_SALT)


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


def _reset_collection():
    return db.collection(RESET_COLLECTION)


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def _hash_reset_secret(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()


def _verify_reset_secret(secret: str, secret_hash: str) -> bool:
    digest = hashlib.sha256(secret.encode("utf-8")).hexdigest()
    return digest == secret_hash


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


def send_password_reset_email(email: str, reset_url: str | None = None) -> Optional[str]:
    """Generate and dispatch a Firebase password reset email.

    If FIREBASE_WEB_API_KEY is provided, the Identity Toolkit REST API will send the
    email using Firebase's hosted templates. Otherwise, a password reset link will be
    generated and returned for logging or alternative delivery.
    """

    get_firebase_app()
    action_settings = auth.ActionCodeSettings(url=reset_url) if reset_url else None
    try:
        reset_link = auth.generate_password_reset_link(email, action_settings)
    except Exception:
        return None

    api_key = os.getenv("FIREBASE_WEB_API_KEY")
    if api_key:
        try:
            requests.post(
                f"https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key={api_key}",
                json={"requestType": "PASSWORD_RESET", "email": email, "continueUrl": reset_url},
                timeout=10,
            )
        except Exception:
            # Even if the API call fails, return the generated link for fallback delivery.
            pass

    return reset_link


def create_password_reset(email: str) -> Optional[str]:
    admin_doc = get_admin_by_email(email)
    if not admin_doc:
        return None

    admin_id = admin_doc.get("id")
    token_id = secrets.token_hex(16)
    nonce = secrets.token_urlsafe(32)

    signed_token = reset_serializer.dumps({"aid": admin_id, "em": admin_doc.get("email"), "jti": token_id, "n": nonce})

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=RESET_TOKEN_TTL)
    _reset_collection().document(token_id).set(
        {
            "adminId": admin_id,
            "email": admin_doc.get("email"),
            "tokenHash": _hash_reset_secret(nonce),
            "createdAt": SERVER_TIMESTAMP,
            "expiresAt": expires_at,
            "used": False,
        }
    )

    return signed_token


def _validate_reset_token(token: str) -> Optional[Tuple[Dict[str, Any], str]]:
    if not token:
        return None
    try:
        payload = reset_serializer.loads(token, max_age=RESET_TOKEN_TTL)
    except (BadSignature, SignatureExpired):
        return None

    token_id = payload.get("jti")
    nonce = payload.get("n")
    admin_id = payload.get("aid")
    email = (payload.get("em") or "").lower()
    if not token_id or not nonce or not admin_id or not email:
        return None

    doc_ref = _reset_collection().document(token_id)
    doc = doc_ref.get()
    if not doc.exists:
        return None
    data = doc.to_dict() or {}
    if data.get("used"):
        return None

    expires_at = _to_datetime(data.get("expiresAt"))
    if expires_at and expires_at < datetime.now(timezone.utc):
        return None

    if str(data.get("adminId")) != str(admin_id):
        return None

    stored_email = (data.get("email") or "").lower()
    if stored_email and stored_email != email:
        return None

    if not _verify_reset_secret(nonce, data.get("tokenHash", "")):
        return None

    admin_doc = get_admin_by_id(admin_id)
    if not admin_doc:
        return None

    return admin_doc, token_id


def verify_reset_token(token: str) -> Optional[Dict[str, Any]]:
    verified = _validate_reset_token(token)
    if not verified:
        return None
    admin_doc, _ = verified
    return admin_doc


def consume_reset_token(token: str, new_password: str) -> bool:
    verified = _validate_reset_token(token)
    if not verified:
        return False

    admin_doc, token_id = verified
    success = update_admin_password(admin_doc.get("id"), new_password)
    if success:
        _reset_collection().document(token_id).set({"used": True, "usedAt": SERVER_TIMESTAMP}, merge=True)
    return success
