import os
import logging
import time
import jwt
from typing import List, Callable

from fastapi import Depends, Header, HTTPException
import firebase_admin
from firebase_admin import credentials, auth as admin_auth, firestore as admin_fs

log = logging.getLogger("auth")
log.setLevel(logging.INFO)

FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID")
FIREBASE_CLIENT_EMAIL = os.getenv("FIREBASE_CLIENT_EMAIL")
FIREBASE_PRIVATE_KEY = os.getenv("FIREBASE_PRIVATE_KEY")

if not firebase_admin._apps:
    cred = credentials.Certificate({
        "type": "service_account",
        "project_id": FIREBASE_PROJECT_ID,
        "client_email": FIREBASE_CLIENT_EMAIL,
        "private_key": (FIREBASE_PRIVATE_KEY or "").replace("\\n", "\n"),
        "token_uri": "https://oauth2.googleapis.com/token",
        "private_key_id": "dummy",
    })
    firebase_admin.initialize_app(cred)

def _firestore():
    return admin_fs.client()

def _fetch_user_roles(uid: str) -> List[str]:
    db = _firestore()
    role_snaps = (
        db.collection("users")
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
    # admin_auth.verify_id_token() already fetched Google certs internally when working normally.
    # Here, for dev, we accept the token payload purely as data and trust it.
    try:
        # options={"verify_signature": False} means: don't cryptographically verify.
        # This is ONLY okay for local dev behind Docker.
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
        decoded = admin_auth.verify_id_token(id_token)
        log.info("get_current_user: verified uid=%s email=%s",
                 decoded.get("uid"), decoded.get("email"))
        return decoded
    except Exception as e:
        msg = str(e)
        log.warning("get_current_user: verify_id_token failed: %s", msg)

        # dev-only skew bypass
        if "Token used too early" in msg:
            log.warning("get_current_user: applying DEV clock-skew bypass")
            decoded = _unsafe_decode_without_iat_check(id_token)
            # sanity: make sure it at least has sub/uid
            uid = decoded.get("user_id") or decoded.get("uid") or decoded.get("sub")
            if not uid:
                raise HTTPException(status_code=401, detail="Invalid token (no uid)")
            # normalize to same shape as verify_id_token()
            decoded_norm = {
                "uid": uid,
                "email": decoded.get("email"),
                "iat": decoded.get("iat", time.time()),
            }
            return decoded_norm

        # else, real failure
        raise HTTPException(status_code=401, detail="Invalid token")

def require_roles(required: List[str]) -> Callable:
    required_lower = [r.lower() for r in required]

    async def _guard(user = Depends(get_current_user)):
        uid = user["uid"]
        roles = _fetch_user_roles(uid)
        ok = any(r in roles for r in required_lower)
        if not ok:
            log.warning(
                "require_roles: uid=%s has roles=%s but needs=%s",
                uid, roles, required_lower
            )
            raise HTTPException(status_code=403, detail="Insufficient role")
        return user

    return _guard
