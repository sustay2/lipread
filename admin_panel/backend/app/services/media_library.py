"""File-based media library stored under MEDIA_ROOT and indexed in Firestore."""
from __future__ import annotations

import os
import uuid
from pathlib import Path
from typing import Dict, List, Optional

from google.cloud.firestore_v1 import SERVER_TIMESTAMP

from app.services.firebase_client import get_firestore_client

DEFAULT_MEDIA_ROOT = "C:/lipread_media"
MEDIA_ROOT = os.getenv("MEDIA_ROOT", DEFAULT_MEDIA_ROOT)
API_BASE_FALLBACK = os.getenv("API_BASE", "http://localhost:8000")


def _normalize_media_base(raw: str) -> str:
    base = (raw or "").strip() or API_BASE_FALLBACK
    if not base.startswith("http://") and not base.startswith("https://"):
        base = f"http://{base}"
    base = base.rstrip("/")
    if not base.endswith("/media"):
        base = f"{base}/media"
    return base


MEDIA_BASE_URL = _normalize_media_base(os.getenv("MEDIA_BASE_URL", ""))

Path(MEDIA_ROOT).mkdir(parents=True, exist_ok=True)

_db = get_firestore_client()


def _write_file(data: bytes, filename: str, subdir: str) -> str:
    safe_name = filename.replace("/", "_").replace("\\", "_")
    rel_path = f"{subdir}/{safe_name}"
    abs_path = Path(MEDIA_ROOT) / rel_path
    abs_path.parent.mkdir(parents=True, exist_ok=True)
    abs_path.write_bytes(data)
    return rel_path


def _url_for(rel_path: str) -> str:
    rel = rel_path.replace("\\", "/").lstrip("/")
    return f"{MEDIA_BASE_URL.rstrip('/')}/{rel}"


def save_media_file(file_obj, media_type: str = "file") -> Dict[str, str]:
    data = file_obj.file.read()
    media_id = uuid.uuid4().hex[:20]
    rel_path = _write_file(data, f"{media_id}_{file_obj.filename}", subdir=media_type)
    payload = {
        "type": media_type,
        "name": file_obj.filename,
        "storagePath": rel_path,
        "url": _url_for(rel_path),
        "contentType": file_obj.content_type,
        "sizeBytes": len(data),
        "createdAt": SERVER_TIMESTAMP,
    }
    _db.collection("media").document(media_id).set(payload)
    stored = _db.collection("media").document(media_id).get()
    stored_data = stored.to_dict() or {}
    stored_data.update({"id": media_id, "url": payload["url"]})
    return stored_data


def list_media(limit: int = 200) -> List[Dict[str, Optional[str]]]:
    results: List[Dict[str, Optional[str]]] = []
    snaps = (
        _db.collection("media")
        .order_by("createdAt", direction="DESCENDING")
        .limit(limit)
        .stream()
    )
    for snap in snaps:
        data = snap.to_dict() or {}
        results.append(
            {
                "id": snap.id,
                "type": data.get("type", "file"),
                "name": data.get("name"),
                "url": data.get("url"),
                "contentType": data.get("contentType"),
                "sizeBytes": data.get("sizeBytes"),
                "createdAt": data.get("createdAt"),
            }
        )
    return results
