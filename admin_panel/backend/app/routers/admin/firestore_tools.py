from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query
from typing import Any, Dict, List, Optional, Iterable
from pathlib import Path
import io, json, csv, datetime
from google.cloud.firestore_v1 import SERVER_TIMESTAMP
from firebase_admin import firestore as admin_fs
from app.deps.auth import require_roles
from dateutil import parser as dateparser

router = APIRouter()
db = admin_fs.client()

# -------- helpers --------
def _to_plain(v: Any):
    """Make Firestore types JSON-safe."""
    # google.cloud.firestore_v1._helpers.Timestamp -> has .isoformat via datetime
    try:
        # Firestore Timestamp behaves like datetime; turn to ISO if possible
        if hasattr(v, "isoformat"):
            return v.isoformat()
    except Exception:
        pass

    if isinstance(v, dict):
        return {k: _to_plain(v2) for k, v2 in v.items()}
    if isinstance(v, (list, tuple)):
        return [_to_plain(x) for x in v]
    return v

def _from_plain(v: Any):
    """Best-effort parse ISO8601 strings back to datetime for import."""
    if isinstance(v, str):
        # try datetime
        try:
            dt = dateparser.isoparse(v)
            if isinstance(dt, datetime.datetime):
                # make timezone-aware if naive
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=datetime.timezone.utc)
                return dt
        except Exception:
            return v
    if isinstance(v, dict):
        return {k: _from_plain(v2) for k, v2 in v.items()}
    if isinstance(v, list):
        return [_from_plain(x) for x in v]
    return v

def _stream_docs(coll_name: str, where_field: Optional[str], where_value: Optional[str], limit: Optional[int]):
    col = db.collection(coll_name)
    if where_field and where_value is not None:
        col = col.where(where_field, "==", where_value)
    if limit and limit > 0:
        col = col.limit(limit)
    for snap in col.stream():
        yield snap

def _batch_commit(batch_docs: Iterable[Dict[str, Any]], coll_name: str, mode: str, preserve_ids: bool) -> int:
    """Write docs in batches of 400. batch_docs is iterable of dicts already cleaned."""
    count = 0
    batch = db.batch()
    n_in = 0
    col_ref = db.collection(coll_name)
    for d in batch_docs:
        _id = d.pop("_id", None) if preserve_ids else None
        d["updatedAt"] = SERVER_TIMESTAMP
        if "createdAt" not in d:
            d["createdAt"] = SERVER_TIMESTAMP
        if _id:
            ref = col_ref.document(_id)
        else:
            ref = col_ref.document()
        if mode == "merge":
            batch.set(ref, d, merge=True)
        else:  # append/replace -> set
            batch.set(ref, d)
        n_in += 1
        if n_in % 400 == 0:
            batch.commit()
            batch = db.batch()
    if n_in % 400 != 0:
        batch.commit()
    return n_in

def _delete_all_in_collection(coll_name: str) -> int:
    col_ref = db.collection(coll_name)
    batch = db.batch()
    n = 0
    for snap in col_ref.stream():
        batch.delete(snap.reference)
        n += 1
        if n % 400 == 0:
            batch.commit()
            batch = db.batch()
    if n % 400 != 0:
        batch.commit()
    return n

# -------- routes --------
@router.get(
    "/export",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def export_collection(
    collection: str = Query(..., description="Top-level collection name"),
    where_field: Optional[str] = Query(None),
    where_value: Optional[str] = Query(None),
    limit: Optional[int] = Query(None, ge=1, le=50000),
    format: str = Query("json", regex="^(json|ndjson)$"),
    pretty: bool = Query(False),
):
    """
    Export a top-level collection. Returns JSON or NDJSON.
    Each record contains `_id` and `data` fields flattened (no subcollections).
    """
    docs = list(_stream_docs(collection, where_field, where_value, limit))
    if format == "json":
        items = []
        for s in docs:
            d = s.to_dict() or {}
            row = {"_id": s.id, **_to_plain(d)}
            items.append(row)
        if pretty:
            return items  # FastAPI will JSON dump pretty if client formats
        return items
    else:  # ndjson
        # return as fake "lines" array to keep it JSON-safe; client can save as .ndjson
        lines = []
        for s in docs:
            d = {"_id": s.id, **_to_plain(s.to_dict() or {})}
            lines.append(json.dumps(d, ensure_ascii=False))
        return {"ndjson": lines}

@router.post(
    "/import",
    dependencies=[Depends(require_roles(["admin", "content_editor"]))],
)
async def import_collection(
    collection: str = Query(...),
    mode: str = Query("append", regex="^(append|merge|replace)$"),
    preserve_ids: bool = Query(True),
    file: UploadFile = File(..., description="JSON or NDJSON produced by /export"),
):
    """
    Import JSON/NDJSON. Each object can optionally include `_id` (respected if preserve_ids=True).
    Modes:
      - append: add new docs (existing ids overwrite)
      - merge: merge into existing docs
      - replace: delete all docs in collection before importing
    """
    raw = await file.read()
    text = raw.decode("utf-8", errors="ignore").strip()
    if not text:
        raise HTTPException(400, "Empty file.")

    # detect ndjson wrapper we returned: {"ndjson":[...]}
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict) and "ndjson" in parsed and isinstance(parsed["ndjson"], list):
            rows = [json.loads(line) for line in parsed["ndjson"]]
        elif isinstance(parsed, list):
            rows = parsed
        else:
            # single object
            rows = [parsed]
    except Exception:
        # maybe real ndjson
        rows = [json.loads(line) for line in text.splitlines() if line.strip()]

    # normalize + parse datetimes
    cleaned = []
    for obj in rows:
        if not isinstance(obj, dict):
            continue
        d = {k: _from_plain(v) for k, v in obj.items()}
        cleaned.append(d)

    deleted = 0
    if mode == "replace":
        deleted = _delete_all_in_collection(collection)

    written = _batch_commit(cleaned, collection, mode=("merge" if mode == "merge" else "append"), preserve_ids=preserve_ids)
    return {"collection": collection, "mode": mode, "deleted": deleted, "written": written}