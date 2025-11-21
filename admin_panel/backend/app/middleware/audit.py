import os
import time
from datetime import datetime, timezone
from typing import Callable, Awaitable
from fastapi import Request, Response
import firebase_admin
from firebase_admin import auth as admin_auth
from firebase_admin import firestore as admin_fs

AUDIT_TO_FIRESTORE = os.getenv("AUDIT_TO_FIRESTORE", "false").lower() == "true"

_db = None
def _db_client():
    global _db
    if _db is None:
        _db = admin_fs.client()
    return _db

async def _extract_uid_from_auth_header(request: Request) -> str | None:
    auth_header = request.headers.get("authorization") or request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        return None
    token = auth_header.split(" ", 1)[1]
    try:
        decoded = admin_auth.verify_id_token(token)
        return decoded.get("uid")
    except Exception:
        return None  # best-effort only

async def audit_middleware(request: Request, call_next: Callable[[Request], Awaitable[Response]]) -> Response:
    started = time.perf_counter()
    uid = await _extract_uid_from_auth_header(request)
    client_ip = request.client.host if request.client else None
    method = request.method
    path = request.url.path
    query = str(request.query_params) if request.query_params else ""

    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        duration_ms = int((time.perf_counter() - started) * 1000)
        record = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "method": method,
            "path": path,
            "query": query,
            "status": locals().get("status", 500),
            "duration_ms": duration_ms,
            "uid": uid,
            "ip": client_ip,
            "ua": request.headers.get("user-agent"),
        }

        if AUDIT_TO_FIRESTORE:
            try:
                _db_client().collection("audit_logs").add(record)
            except Exception as e:
                # Don't break requests on audit failures
                print(f"[audit] Firestore write failed: {e} | record={record}")
        else:
            print(f"[audit] {record}")
