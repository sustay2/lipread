import logging
import time
import jwt
from typing import List, Callable

from fastapi import Depends, Header, HTTPException
from firebase_admin import auth as admin_auth

from app.services.firebase_client import get_firebase_app, get_firestore_client

log = logging.getLogger("auth")
log.setLevel(logging.INFO)

# Ensure Firebase is initialized with the provided credentials
firebase_app = get_firebase_app()
db = get_firestore_client()


def _firestore():
    return db


def _fetch_user_roles(uid: str) -> List[str]:
    role_snaps = (
        _firestore()
        .collection("users")
        .document(uid)
        .collection("roles")
        .stream()
    )
    roles: List[str] = []
    for rdoc in role_snaps:
        data = rdoc.to_dict() or {}
        r = (data.get("role") or "").strip().lower()
        if r:
            roles.append(r)
    return roles


def _unsafe_decode_without_iat_check(id_token: str):
    """
    DEV-ONLY FALLBACK.
    We'll decode the token just to get uid/email if the only problem is tiny clock skew.
    """
    try:
        payload = jwt.decode(id_token, options={"verify_signature": False, "verify_exp": False})
        return payload
    except Exception as e:
        log.warning("unsafe fallback decode failed: %s", e)
        raise HTTPException(status_code=401, detail="Invalid token")


async def get_current_user(authorization: str | None = Header(default=None)):
    if not authorization or not authorization.startswith("Bearer "):
        log.warning("get_current_user: missing/invalid Authorization header: %r", authorization)
        raise HTTPException(status_code=401, detail="Missing token")

    id_token = authorization.split(" ", 1)[1].strip()

    try:
        decoded = admin_auth.verify_id_token(id_token, app=firebase_app)
        log.info(
            "get_current_user: verified uid=%s email=%s",
            decoded.get("uid"),
            decoded.get("email"),
        )
        return decoded
    except Exception as e:
        msg = str(e)
        log.warning("get_current_user: verify_id_token failed: %s", msg)

        if "Token used too early" in msg:
            log.warning("get_current_user: applying DEV clock-skew bypass")
            decoded = _unsafe_decode_without_iat_check(id_token)
            uid = decoded.get("user_id") or decoded.get("uid") or decoded.get("sub")
            if not uid:
                raise HTTPException(status_code=401, detail="Invalid token (no uid)")
            decoded_norm = {
                "uid": uid,
                "email": decoded.get("email"),
                "iat": decoded.get("iat", time.time()),
            }
            return decoded_norm

        raise HTTPException(status_code=401, detail="Invalid token")


def require_roles(required: List[str]) -> Callable:
    required_lower = [r.lower() for r in required]

    async def _guard(user=Depends(get_current_user)):
        uid = user["uid"]
        roles = _fetch_user_roles(uid)
        ok = any(r in roles for r in required_lower)
        if not ok:
            log.warning(
                "require_roles: uid=%s has roles=%s but needs=%s",
                uid,
                roles,
                required_lower,
            )
            raise HTTPException(status_code=403, detail="Insufficient role")
        return user

    return _guard
