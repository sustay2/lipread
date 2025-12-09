"""Admin-facing Firestore helpers mapped to the provided data model."""
from __future__ import annotations

import json
from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

from firebase_admin import firestore
from google.cloud.firestore_v1 import Query

from google.cloud.firestore_v1.base_document import DocumentSnapshot

from app.services.firebase_client import get_firestore_client
from app.services.activities import activity_service
from app.services.billing_service import STRIPE_DEFAULT_CURRENCY, stripe


db = get_firestore_client()


# Utilities -----------------------------------------------------------------

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


def _iso(value: Any) -> Optional[str]:
    dt = _to_datetime(value)
    if dt:
        return dt.isoformat()
    return None


def _fetch_roles(uid: str) -> List[str]:
    roles: List[str] = []
    for snap in (
        db.collection("users")
        .document(uid)
        .collection("roles")
        .stream()
    ):
        role_val = (snap.to_dict() or {}).get("role")
        if role_val:
            roles.append(str(role_val).strip().lower())
    return roles


def _map_user(doc: DocumentSnapshot) -> Dict[str, Any]:
    data = doc.to_dict() or {}
    uid = doc.id
    roles = _fetch_roles(uid)
    created_dt = _to_datetime(data.get("createdAt"))
    last_active_dt = _to_datetime(data.get("lastActiveAt"))
    return {
        "id": uid,
        "email": data.get("email"),
        "displayName": data.get("displayName"),
        "photoURL": data.get("photoURL"),
        "locale": data.get("locale", "en"),
        "role": data.get("role") or (roles[0] if roles else "member"),
        "roles": roles,
        "status": data.get("status", "active"),
        "lastActiveAt": last_active_dt,
        "lastActiveAtIso": last_active_dt.isoformat() if last_active_dt else None,
        "createdAt": created_dt,
        "createdAtIso": created_dt.isoformat() if created_dt else None,
        "stats": data.get("stats", {}),
    }


# Queries -------------------------------------------------------------------

def list_users(search: str | None = None, role: str | None = None, limit: int = 100) -> List[Dict[str, Any]]:
    snaps = db.collection("users").stream()
    results: List[Dict[str, Any]] = []
    for snap in snaps:
        mapped = _map_user(snap)
        if search and search.lower() not in ((mapped.get("email") or "").lower()):
            continue
        if role and role.lower() not in [r.lower() for r in mapped.get("roles", [])]:
            continue
        results.append(mapped)
        if len(results) >= limit:
            break
    results.sort(key=lambda u: (u.get("email") or "").lower())
    return results


def paginate_users(
    search: str | None = None,
    role: str | None = None,
    page: int = 1,
    page_size: int = 20,
) -> Tuple[List[Dict[str, Any]], int]:
    users = list_users(search=search, role=role, limit=5000)
    total = len(users)
    start = max((page - 1) * page_size, 0)
    end = start + page_size
    return users[start:end], total


def update_user(uid: str, display_name: Optional[str], role: Optional[str], status: Optional[str]):
    doc_ref = db.collection("users").document(uid)
    doc = doc_ref.get()
    if not doc.exists:
        return False
    payload: Dict[str, Any] = {}
    if display_name is not None:
        payload["displayName"] = display_name
    if role is not None:
        payload["role"] = role
    if status is not None:
        payload["status"] = status
    if payload:
        payload["updatedAt"] = datetime.now(timezone.utc)
        doc_ref.update(payload)
    return True


def soft_disable_user(uid: str, disabled: bool = True):
    status = "disabled" if disabled else "active"
    return update_user(uid, None, None, status)


def force_logout_user(uid: str):
    doc_ref = db.collection("users").document(uid)
    if not doc_ref.get().exists:
        return False
    doc_ref.update({"forceLogoutAt": datetime.now(timezone.utc)})
    return True


def get_user_detail(uid: str) -> Optional[Dict[str, Any]]:
    snap = db.collection("users").document(uid).get()
    if not snap.exists:
        return None

    mapped = _map_user(snap)

    enrollments: List[Dict[str, Any]] = []
    for enr in (
        db.collection("users")
        .document(uid)
        .collection("enrollments")
        .stream()
    ):
        edata = enr.to_dict() or {}
        enrollments.append(
            {
                "courseId": edata.get("courseId") or enr.id,
                "status": edata.get("status", "unknown"),
                "progress": edata.get("progress", 0),
                "lastLessonId": edata.get("lastLessonId"),
                "updatedAt": _iso(edata.get("updatedAt")),
                "startedAt": _iso(edata.get("startedAt")),
            }
        )

    badges: List[Dict[str, Any]] = []
    for badge in (
        db.collection("users")
        .document(uid)
        .collection("badges")
        .stream()
    ):
        bdata = badge.to_dict() or {}
        badges.append(
            {
                "badgeId": bdata.get("badgeId") or badge.id,
                "earnedAt": _iso(bdata.get("earnedAt")),
            }
        )

    tasks: List[Dict[str, Any]] = []
    for task in (
        db.collection("users")
        .document(uid)
        .collection("tasks")
        .stream()
    ):
        tdata = task.to_dict() or {}
        tasks.append(
            {
                "title": tdata.get("title"),
                "completed": tdata.get("completed"),
                "points": tdata.get("points"),
                "frequency": tdata.get("frequency"),
                "order": tdata.get("order"),
            }
        )

    mapped.update(
        {
            "enrollments": enrollments,
            "badges": badges,
            "tasks": tasks,
        }
    )
    return mapped


def summarize_kpis() -> Dict[str, Any]:
    users = list_users(limit=5000)
    total_users = len(users)

    courses = list(db.collection("courses").stream())
    modules = list(db.collection("modules").stream())
    videos = list(db.collection("videos").stream())
    media_assets = list(db.collection("media").stream())

    today = datetime.now(timezone.utc).date()
    daily_active = 0
    for user in users:
        last_active = _to_datetime(user.get("lastActiveAt"))
        if last_active and last_active.date() == today:
            daily_active += 1

    return {
        "total_users": total_users,
        "total_courses": len(courses),
        "total_modules": len(modules),
        "total_videos": len(videos),
        "total_media": len(media_assets),
        "daily_active": daily_active,
    }


def list_courses_with_modules() -> List[Dict[str, Any]]:
    output: List[Dict[str, Any]] = []
    for course_snap in db.collection("courses").stream():
        cdata = course_snap.to_dict() or {}
        modules_snaps = (
            db.collection("courses")
            .document(course_snap.id)
            .collection("modules")
            .stream()
        )
        modules_payload: List[Dict[str, Any]] = []
        lesson_count = 0
        for module_snap in modules_snaps:
            mdata = module_snap.to_dict() or {}
            lessons_snaps = (
                db.collection("courses")
                .document(course_snap.id)
                .collection("modules")
                .document(module_snap.id)
                .collection("lessons")
                .stream()
            )
            lessons_payload: List[Dict[str, Any]] = []
            for lesson_snap in lessons_snaps:
                ldata = lesson_snap.to_dict() or {}
                lessons_payload.append(
                    {
                        "id": lesson_snap.id,
                        "title": ldata.get("title"),
                        "estimatedMin": ldata.get("estimatedMin"),
                        "order": ldata.get("order"),
                        "objectives": ldata.get("objectives", []),
                    }
                )
                lesson_count += 1

            modules_payload.append(
                {
                    "id": module_snap.id,
                    "title": mdata.get("title"),
                    "order": mdata.get("order"),
                    "summary": mdata.get("summary"),
                    "lessons": lessons_payload,
                }
            )

        output.append(
            {
                "id": course_snap.id,
                "title": cdata.get("title"),
                "description": cdata.get("description"),
                "published": cdata.get("published", False),
                "isPremium": cdata.get("isPremium", False),
                "difficulty": cdata.get("difficulty"),
                "modules": modules_payload,
                "lesson_count": lesson_count,
                "tags": cdata.get("tags", []),
                "createdAt": _iso(cdata.get("createdAt")),
                "mediaId": cdata.get("mediaId"),
            }
        )
    return output


def get_media(media_id: str) -> Optional[Dict[str, Any]]:
    snap = db.collection("media").document(media_id).get()
    if not snap.exists:
        return None
    data = snap.to_dict() or {}
    return {
        "id": snap.id,
        "type": data.get("type", "file"),
        "name": data.get("name"),
        "contentType": data.get("contentType"),
        "url": data.get("url"),
        "storagePath": data.get("storagePath"),
        "sizeBytes": data.get("sizeBytes"),
        "createdAt": _iso(data.get("createdAt")),
    }


def list_media_library(limit: int = 200) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    for snap in db.collection("media").order_by("createdAt", direction=Query.DESCENDING).limit(limit).stream():
        data = snap.to_dict() or {}
        items.append(
            {
                "id": snap.id,
                "type": data.get("type", "file"),
                "name": data.get("name") or data.get("fileName"),
                "url": data.get("url"),
                "contentType": data.get("contentType"),
                "sizeBytes": data.get("sizeBytes"),
                "createdAt": _iso(data.get("createdAt")),
                "source": "media",
            }
        )

    for snap in db.collection("videos").order_by("createdAt", direction=Query.DESCENDING).limit(limit).stream():
        data = snap.to_dict() or {}
        items.append(
            {
                "id": snap.id,
                "type": "video",
                "name": data.get("title") or snap.id,
                "url": data.get("url"),
                "contentType": "video/mp4",
                "sizeBytes": data.get("sizeBytes"),
                "createdAt": _iso(data.get("createdAt")),
                "source": "videos",
                "thumbUrl": data.get("thumbUrl") or data.get("thumbPath"),
            }
        )

    items.sort(key=lambda i: i.get("createdAt") or "", reverse=True)
    return items


def get_course(course_id: str) -> Optional[Dict[str, Any]]:
    snap = db.collection("courses").document(course_id).get()
    if not snap.exists:
        return None
    data = snap.to_dict() or {}
    return {
        "id": snap.id,
        "title": data.get("title"),
        "description": data.get("description"),
        "difficulty": data.get("difficulty"),
        "published": data.get("published", False),
        "isPremium": data.get("isPremium", False),
        "tags": data.get("tags", []),
        "summary": data.get("summary"),
        "locale": data.get("locale"),
        "order": data.get("order"),
        "mediaId": data.get("mediaId"),
        "createdAt": _iso(data.get("createdAt")),
        "updatedAt": _iso(data.get("updatedAt")),
    }


def create_course(payload: Dict[str, Any]) -> str:
    now = datetime.now(timezone.utc)
    payload.setdefault("createdAt", now)
    payload.setdefault("updatedAt", now)
    doc_ref = db.collection("courses").document()
    doc_ref.set(payload)
    return doc_ref.id


def update_course(course_id: str, payload: Dict[str, Any]) -> bool:
    doc_ref = db.collection("courses").document(course_id)
    if not doc_ref.get().exists:
        return False
    payload["updatedAt"] = datetime.now(timezone.utc)
    doc_ref.update(payload)
    return True


def delete_course(course_id: str) -> bool:
    doc_ref = db.collection("courses").document(course_id)
    if not doc_ref.get().exists:
        return False
    # delete subcollections modules/lessons/activities
    for module in doc_ref.collection("modules").stream():
        module_ref = doc_ref.collection("modules").document(module.id)
        for lesson in module_ref.collection("lessons").stream():
            lesson_ref = module_ref.collection("lessons").document(lesson.id)
            for activity in lesson_ref.collection("activities").stream():
                lesson_ref.collection("activities").document(activity.id).delete()
            lesson_ref.delete()
        module_ref.delete()
    doc_ref.delete()
    return True


def list_modules(course_id: str) -> List[Dict[str, Any]]:
    modules: List[Dict[str, Any]] = []
    for module in (
        db.collection("courses").document(course_id).collection("modules").stream()
    ):
        mdata = module.to_dict() or {}
        modules.append(
            {
                "id": module.id,
                "title": mdata.get("title"),
                "summary": mdata.get("summary"),
                "order": mdata.get("order"),
                "createdAt": _iso(mdata.get("createdAt")),
            }
        )
    modules.sort(key=lambda m: (m.get("order") or 0))
    return modules


def create_module(course_id: str, payload: Dict[str, Any]) -> str:
    now = datetime.now(timezone.utc)
    payload.setdefault("createdAt", now)
    payload.setdefault("updatedAt", now)
    doc_ref = (
        db.collection("courses").document(course_id).collection("modules").document()
    )
    doc_ref.set(payload)
    return doc_ref.id


def get_next_module_order(course_id: str) -> int:
    collection = db.collection("courses").document(course_id).collection("modules")
    try:
        snap = (
            collection.order_by("order", direction=Query.DESCENDING)
            .limit(1)
            .stream()
        )
        last = next(iter(snap), None)
        if last:
            data = last.to_dict() or {}
            return int(data.get("order") or 0) + 1
    except Exception:
        pass
    return 0


def update_module(course_id: str, module_id: str, payload: Dict[str, Any]) -> bool:
    doc_ref = (
        db.collection("courses")
        .document(course_id)
        .collection("modules")
        .document(module_id)
    )
    if not doc_ref.get().exists:
        return False
    payload["updatedAt"] = datetime.now(timezone.utc)
    doc_ref.update(payload)
    return True


def delete_module(course_id: str, module_id: str) -> bool:
    doc_ref = (
        db.collection("courses")
        .document(course_id)
        .collection("modules")
        .document(module_id)
    )
    if not doc_ref.get().exists:
        return False
    for lesson in doc_ref.collection("lessons").stream():
        lesson_ref = doc_ref.collection("lessons").document(lesson.id)
        for activity in lesson_ref.collection("activities").stream():
            lesson_ref.collection("activities").document(activity.id).delete()
        lesson_ref.delete()
    doc_ref.delete()
    return True


def list_lessons(course_id: str, module_id: str) -> List[Dict[str, Any]]:
    lessons: List[Dict[str, Any]] = []
    for lesson in (
        db.collection("courses")
        .document(course_id)
        .collection("modules")
        .document(module_id)
        .collection("lessons")
        .stream()
    ):
        ldata = lesson.to_dict() or {}
        lessons.append(
            {
                "id": lesson.id,
                "title": ldata.get("title"),
                "order": ldata.get("order"),
                "estimatedMin": ldata.get("estimatedMin"),
                "objectives": ldata.get("objectives", []),
            }
        )
    lessons.sort(key=lambda l: (l.get("order") or 0))
    return lessons


def create_lesson(course_id: str, module_id: str, payload: Dict[str, Any]) -> str:
    now = datetime.now(timezone.utc)
    payload.setdefault("createdAt", now)
    payload.setdefault("updatedAt", now)
    doc_ref = (
        db.collection("courses")
        .document(course_id)
        .collection("modules")
        .document(module_id)
        .collection("lessons")
        .document()
    )
    doc_ref.set(payload)
    return doc_ref.id


def get_next_lesson_order(course_id: str, module_id: str) -> int:
    collection = (
        db.collection("courses")
        .document(course_id)
        .collection("modules")
        .document(module_id)
        .collection("lessons")
    )
    try:
        snap = (
            collection.order_by("order", direction=Query.DESCENDING)
            .limit(1)
            .stream()
        )
        last = next(iter(snap), None)
        if last:
            data = last.to_dict() or {}
            return int(data.get("order") or 0) + 1
    except Exception:
        pass
    return 0


def update_lesson(course_id: str, module_id: str, lesson_id: str, payload: Dict[str, Any]) -> bool:
    doc_ref = (
        db.collection("courses")
        .document(course_id)
        .collection("modules")
        .document(module_id)
        .collection("lessons")
        .document(lesson_id)
    )
    if not doc_ref.get().exists:
        return False
    payload["updatedAt"] = datetime.now(timezone.utc)
    doc_ref.update(payload)
    return True


def delete_lesson(course_id: str, module_id: str, lesson_id: str) -> bool:
    doc_ref = (
        db.collection("courses")
        .document(course_id)
        .collection("modules")
        .document(module_id)
        .collection("lessons")
        .document(lesson_id)
    )
    if not doc_ref.get().exists:
        return False
    for activity in doc_ref.collection("activities").stream():
        doc_ref.collection("activities").document(activity.id).delete()
    doc_ref.delete()
    return True


def list_activities(course_id: str, module_id: str, lesson_id: str) -> List[Dict[str, Any]]:
    activities = activity_service.list_activities(course_id, module_id, lesson_id)
    return [
        {
            "id": item.id,
            "title": item.title,
            "type": item.type,
            "order": item.order,
            "config": item.config,
            "scoring": item.scoring,
            "itemCount": item.itemCount,
            "createdAt": item.createdAt,
            "updatedAt": item.updatedAt,
        }
        for item in activities
    ]


def get_activity_detail(
    course_id: str, module_id: str, lesson_id: str, activity_id: str
) -> Optional[Dict[str, Any]]:
    return activity_service.get_activity(course_id, module_id, lesson_id, activity_id)


def create_activity(course_id: str, module_id: str, lesson_id: str, payload: Dict[str, Any]) -> str:
    return activity_service.create_activity(
        course_id,
        module_id,
        lesson_id,
        title=payload.get("title") or payload.get("type", "activity"),
        type=payload.get("type", "activity"),
        order=int(payload.get("order", 0)),
        scoring=payload.get("scoring") or {},
        config=payload.get("config") or {},
        question_bank_id=(payload.get("config") or {}).get("questionBankId"),
        question_ids=payload.get("questionIds") or [],
        embed_questions=bool((payload.get("config") or {}).get("embedQuestions")),
        ab_variant=payload.get("abVariant"),
        created_by=payload.get("createdBy"),
    )


def get_next_activity_order(course_id: str, module_id: str, lesson_id: str) -> int:
    return activity_service.next_order(course_id, module_id, lesson_id)


def update_activity(
    course_id: str, module_id: str, lesson_id: str, activity_id: str, payload: Dict[str, Any]
) -> bool:
    return activity_service.update_activity(
        course_id,
        module_id,
        lesson_id,
        activity_id,
        title=payload.get("title") or payload.get("type", "activity"),
        type=payload.get("type", "activity"),
        order=int(payload.get("order", 0)),
        scoring=payload.get("scoring") or {},
        config=payload.get("config") or {},
        question_bank_id=(payload.get("config") or {}).get("questionBankId"),
        question_ids=payload.get("questionIds") or [],
        embed_questions=bool((payload.get("config") or {}).get("embedQuestions")),
        ab_variant=payload.get("abVariant"),
    )


def delete_activity(course_id: str, module_id: str, lesson_id: str, activity_id: str) -> bool:
    return activity_service.delete_activity(course_id, module_id, lesson_id, activity_id)


def collect_engagement_metrics() -> Dict[str, Any]:
    users = list_users(limit=5000)
    today = datetime.now(timezone.utc).date()
    weekly_start = today.isocalendar().week

    lesson_completion: List[float] = []
    quiz_scores: List[float] = []

    def _score_to_pct(raw: Any) -> float:
        try:
            val = float(raw)
        except (TypeError, ValueError):
            return 0.0
        return val * 100 if val <= 1 else val

    for user in users:
        uid = user["id"]
        for enroll in (
            db.collection("users")
            .document(uid)
            .collection("enrollments")
            .stream()
        ):
            edata = enroll.to_dict() or {}
            progress = edata.get("progress")
            if progress is not None:
                lesson_completion.append(float(progress))

        for attempt in (
            db.collection("users")
            .document(uid)
            .collection("attempts")
            .stream()
        ):
            adata = attempt.to_dict() or {}
            if adata.get("score") is not None:
                quiz_scores.append(_score_to_pct(adata.get("score")))

    avg_completion = sum(lesson_completion) / len(lesson_completion) if lesson_completion else 0
    avg_quiz_score = sum(quiz_scores) / len(quiz_scores) if quiz_scores else 0

    daily_active = 0
    for u in users:
        last_active = _to_datetime(u.get("lastActiveAt"))
        if last_active and last_active.date() == today:
            daily_active += 1

    streaks = []
    for user in users:
        uid = user["id"]
        streak_docs = (
            db.collection("users")
            .document(uid)
            .collection("streaks")
            .stream()
        )
        for streak in streak_docs:
            sdata = streak.to_dict() or {}
            streaks.append(int(sdata.get("count", 0)))

    avg_streak = sum(streaks) / len(streaks) if streaks else 0

    return {
        "daily_active": daily_active,
        "weekly_start": weekly_start,
        "avg_completion": round(avg_completion, 2),
        "avg_quiz_score": round(avg_quiz_score, 2),
        "avg_streak": round(avg_streak, 2),
    }


def analytics_timeseries(days: int = 14, start_date: Optional[date] = None, end_date: Optional[date] = None) -> Dict[str, List[Any]]:
    if start_date and end_date:
        days = max((end_date - start_date).days + 1, 1)
    end_date = end_date or datetime.now(timezone.utc).date()
    start_date = start_date or (end_date - timedelta(days=days - 1))

    dau: Dict[date, int] = {start_date + timedelta(days=i): 0 for i in range(days)}
    completions: Dict[date, int] = {start_date + timedelta(days=i): 0 for i in range(days)}
    quiz_accuracy: Dict[date, List[int]] = {start_date + timedelta(days=i): [] for i in range(days)}

    users = list_users(limit=5000)

    def _score_to_pct(raw: Any) -> float:
        try:
            val = float(raw)
        except (TypeError, ValueError):
            return 0.0
        return val * 100 if val <= 1 else val
    for user in users:
        last_active = _to_datetime(user.get("lastActiveAt"))
        if last_active:
            d = last_active.date()
            if start_date <= d <= end_date:
                dau[d] = dau.get(d, 0) + 1

        uid = user["id"]
        for enroll in (
            db.collection("users")
            .document(uid)
            .collection("enrollments")
            .stream()
        ):
            edata = enroll.to_dict() or {}
            progress = edata.get("progress")
            updated_at = _to_datetime(edata.get("updatedAt"))
            if progress is not None and progress >= 99 and updated_at:
                d = updated_at.date()
                if start_date <= d <= end_date:
                    completions[d] = completions.get(d, 0) + 1

        for attempt in (
            db.collection("users")
            .document(uid)
            .collection("attempts")
            .stream()
        ):
            adata = attempt.to_dict() or {}
            created_at = _to_datetime(adata.get("createdAt"))
            if created_at:
                d = created_at.date()
                if start_date <= d <= end_date and adata.get("score") is not None:
                    quiz_accuracy[d].append(_score_to_pct(adata.get("score")))

    labels = [(start_date + timedelta(days=i)).isoformat() for i in range(days)]
    avg_accuracy = []
    for label in labels:
        d = datetime.fromisoformat(label).date()
        scores = quiz_accuracy.get(d, [])
        avg_accuracy.append(round(sum(scores) / len(scores), 2) if scores else 0)

    return {
        "labels": labels,
        "dau": [dau.get(datetime.fromisoformat(l).date(), 0) for l in labels],
        "completions": [completions.get(datetime.fromisoformat(l).date(), 0) for l in labels],
        "quiz_accuracy": avg_accuracy,
    }


# Daily tasks ----------------------------------------------------------------


def _normalize_task_action(action: Any) -> tuple[Any, int]:
    action_type = None
    action_count = 1
    if isinstance(action, dict):
        action_type = action.get("type") or action.get("action")
        try:
            action_count = int(action.get("count") or 1)
        except (TypeError, ValueError):
            action_count = 1
    else:
        action_type = action

    return action_type, max(action_count, 1)


def list_user_tasks() -> List[Dict[str, Any]]:
    tasks: List[Dict[str, Any]] = []
    snaps = (
        db.collection("user_tasks")
        .order_by("createdAt", direction=Query.DESCENDING)
        .stream()
    )
    for snap in snaps:
        data = snap.to_dict() or {}
        action_raw = data.get("action")
        action_type, action_count = _normalize_task_action(action_raw)
        tasks.append(
            {
                "id": snap.id,
                "title": data.get("title"),
                "points": int(data.get("points") or 0),
                "frequency": data.get("frequency", "daily"),
                "action": {"type": action_type, "count": action_count},
                "createdAt": _iso(data.get("createdAt")),
            }
        )
    return tasks


def get_user_task(task_id: str) -> Optional[Dict[str, Any]]:
    snap = db.collection("user_tasks").document(task_id).get()
    if not snap.exists:
        return None
    data = snap.to_dict() or {}
    action_raw = data.get("action")
    action_type, action_count = _normalize_task_action(action_raw)
    return {
        "id": snap.id,
        "title": data.get("title"),
        "points": int(data.get("points") or 0),
        "frequency": data.get("frequency", "daily"),
        "action": {"type": action_type, "count": action_count},
        "createdAt": _iso(data.get("createdAt")),
        "updatedAt": _iso(data.get("updatedAt")),
    }


def create_user_task(payload: Dict[str, Any]) -> str:
    now = datetime.now(timezone.utc)
    payload.setdefault("createdAt", now)
    payload.setdefault("frequency", "daily")
    action_raw = payload.get("action") or {}
    action_type, action_count = _normalize_task_action(action_raw)
    payload["action"] = {"type": action_type, "count": action_count}
    doc_ref = db.collection("user_tasks").document()
    doc_ref.set(payload)
    return doc_ref.id


def update_user_task(task_id: str, payload: Dict[str, Any]) -> bool:
    ref = db.collection("user_tasks").document(task_id)
    if not ref.get().exists:
        return False
    action_raw = payload.get("action") or {}
    action_type, action_count = _normalize_task_action(action_raw)
    payload = {
        **payload,
        "updatedAt": datetime.now(timezone.utc),
        "action": {"type": action_type, "count": action_count},
    }
    ref.update(payload)
    return True


def delete_user_task(task_id: str) -> bool:
    ref = db.collection("user_tasks").document(task_id)
    if not ref.get().exists:
        return False
    ref.delete()
    return True


# Billing analytics ----------------------------------------------------------


def subscription_analytics(months: int = 12) -> Dict[str, Any]:
    """Aggregate subscription and revenue analytics.

    Generates month-by-month series (most recent month last) for revenue and new
    subscriptions plus summary breakdowns for active vs canceled and trial
    conversions.
    """

    today = datetime.now(timezone.utc).date()
    current_year, current_month = today.year, today.month
    month_buckets: List[Tuple[int, int]] = []
    for _ in range(max(months, 1)):
        month_buckets.append((current_year, current_month))
        if current_month == 1:
            current_year -= 1
            current_month = 12
        else:
            current_month -= 1
    month_buckets.reverse()

    labels = [datetime(y, m, 1, tzinfo=timezone.utc).strftime("%b %Y") for y, m in month_buckets]
    start_date = date(month_buckets[0][0], month_buckets[0][1], 1)
    revenue_by_month = {label: 0.0 for label in labels}
    new_subs_by_month = {label: 0 for label in labels}
    total_revenue = 0.0

    def _label_for(dt: datetime) -> Optional[str]:
        lbl = datetime(dt.year, dt.month, 1, tzinfo=timezone.utc).strftime("%b %Y")
        return lbl if lbl in revenue_by_month else None

    start_dt = datetime.combine(start_date, datetime.min.time(), tzinfo=timezone.utc)
    start_ts = int(start_dt.timestamp())

    # Stripe-derived revenue and subscription counts (preferred)
    try:
        invoices = stripe.Invoice.list(
            status="paid",
            created={"gte": start_ts},
            limit=100,
        )
        for inv in invoices.auto_paging_iter():
            created = inv.get("created")
            created_at = datetime.fromtimestamp(int(created), tz=timezone.utc) if created else None
            label = _label_for(created_at) if created_at else None
            if not label:
                continue
            currency = str(inv.get("currency") or "").lower()
            if currency and currency != STRIPE_DEFAULT_CURRENCY.lower():
                continue
            amount_paid = inv.get("amount_paid")
            if amount_paid is None:
                amount_paid = inv.get("total")
            try:
                amount_val = float(amount_paid or 0) / 100.0
            except (TypeError, ValueError):
                continue
            revenue_by_month[label] += amount_val
            total_revenue += amount_val
    except Exception:
        paid_statuses = {"paid", "succeeded", "completed"}
        for snap in db.collection("payment_events").where("createdAt", ">=", start_dt).stream():
            pdata = snap.to_dict() or {}
            created_at = _to_datetime(pdata.get("createdAt"))
            label = _label_for(created_at) if created_at else None
            if not label:
                continue
            status = str(pdata.get("status", "")).lower()
            if paid_statuses and status and status not in paid_statuses:
                continue
            amount = pdata.get("amount_myr")
            if amount is None:
                amount = pdata.get("amount")
            try:
                amount_val = float(amount or 0)
            except (TypeError, ValueError):
                continue
            revenue_by_month[label] += amount_val
            total_revenue += amount_val

    active_count = 0
    canceled_count = 0
    trial_total = 0
    trial_converted = 0
    trialing_count = 0

    try:
        subs = stripe.Subscription.list(status="all", created={"gte": start_ts}, limit=100)
        for sub in subs.auto_paging_iter():
            created = sub.get("created")
            created_at = datetime.fromtimestamp(int(created), tz=timezone.utc) if created else None
            label = _label_for(created_at) if created_at else None
            if label:
                new_subs_by_month[label] += 1
            status = str(sub.get("status", "")).lower()
            if status == "active":
                active_count += 1
            elif status == "canceled":
                canceled_count += 1
            elif status == "trialing":
                trialing_count += 1
            trial_end_val = sub.get("trial_end")
            if trial_end_val:
                trial_total += 1
                if status == "active":
                    trial_converted += 1
    except Exception:
        for snap in db.collection("user_subscriptions").stream():
            sdata = snap.to_dict() or {}
            status = str(sdata.get("status", "")).lower()
            created_at = _to_datetime(sdata.get("createdAt"))
            label = _label_for(created_at) if created_at else None
            if label:
                new_subs_by_month[label] += 1

            if status == "active":
                active_count += 1
            elif status == "canceled":
                canceled_count += 1
            elif status == "trialing":
                trialing_count += 1

            trial_end = _to_datetime(sdata.get("trial_end_at") or sdata.get("trialEndAt"))
            if trial_end:
                trial_total += 1
                if status == "active":
                    trial_converted += 1

    conversion_pct = round((trial_converted / trial_total) * 100, 2) if trial_total else 0.0
    monthly_revenue_list = [round(revenue_by_month[label], 2) for label in labels]
    current_month_revenue = revenue_by_month.get(labels[-1], 0.0) if labels else 0.0

    return {
        "labels": labels,
        "monthly_revenue": monthly_revenue_list,
        "new_subscriptions": [new_subs_by_month[label] for label in labels],
        "status_breakdown": {
            "active": active_count,
            "canceled": canceled_count,
        },
        "trial_conversion": {
            "converted": trial_converted,
            "total_trials": trial_total,
            "percentage": conversion_pct,
        },
        "subscription_counts": {
            "active": active_count,
            "trialing": trialing_count,
            "canceled": canceled_count,
        },
        "total_revenue": round(total_revenue, 2),
        "current_month_revenue": round(current_month_revenue, 2),
    }


# Subscription metadata ------------------------------------------------------


def get_subscription_metadata() -> Dict[str, Any]:
    ref = db.collection("config").document("subscription_metadata")
    snap = ref.get()
    defaults = {
        # Default to the free plan limit (10/month) so the admin UI and
        # client-side enforcement stay aligned even before metadata is saved.
        "transcriptionLimit": 10,
        "canAccessPremiumCourses": False,
        "freeTrialDays": 0,
    }
    if not snap.exists:
        return defaults

    data = snap.to_dict() or {}
    limit_val = data.get("transcriptionLimit")
    if limit_val is None and "transcription_limit" in data:
        limit_val = data.get("transcription_limit")
    return {
        "transcriptionLimit": limit_val,
        "canAccessPremiumCourses": data.get(
            "canAccessPremiumCourses", data.get("can_access_premium_courses", False)
        ),
        "freeTrialDays": data.get("freeTrialDays", data.get("trial_period_days", 0)),
        "updatedAt": _iso(data.get("updatedAt")),
    }


def update_subscription_metadata(payload: Dict[str, Any]) -> None:
    ref = db.collection("config").document("subscription_metadata")
    ref.set(
        {
            **payload,
            "updatedAt": firestore.SERVER_TIMESTAMP,
            "createdAt": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )


# Subscriptions & billing ----------------------------------------------------


def list_subscription_plans() -> List[Dict[str, Any]]:
    plans: List[Dict[str, Any]] = []
    for snap in db.collection("subscription_plans").stream():
        data = snap.to_dict() or {}
        plans.append(
            {
                "id": snap.id,
                "name": data.get("name"),
                "price_myr": data.get("price_myr"),
                "stripe_product_id": data.get("stripe_product_id"),
                "stripe_price_id": data.get("stripe_price_id"),
                "transcription_limit": data.get("transcription_limit"),
                "is_transcription_unlimited": data.get("is_transcription_unlimited", False),
                "can_access_premium_courses": data.get("can_access_premium_courses", False),
                "trial_period_days": data.get("trial_period_days", 0),
                "is_active": data.get("is_active", False),
                "createdAt": data.get("createdAt"),
                "updatedAt": data.get("updatedAt"),
            }
        )
    return plans


def get_subscription_plan(plan_id: str) -> Optional[Dict[str, Any]]:
    snap = db.collection("subscription_plans").document(plan_id).get()
    if not snap.exists:
        return None
    data = snap.to_dict() or {}
    return {
        "id": snap.id,
        "name": data.get("name"),
        "price_myr": data.get("price_myr"),
        "stripe_product_id": data.get("stripe_product_id"),
        "stripe_price_id": data.get("stripe_price_id"),
        "transcription_limit": data.get("transcription_limit"),
        "is_transcription_unlimited": data.get("is_transcription_unlimited", False),
        "can_access_premium_courses": data.get("can_access_premium_courses", False),
        "trial_period_days": data.get("trial_period_days", 0),
        "is_active": data.get("is_active", False),
        "createdAt": data.get("createdAt"),
        "updatedAt": data.get("updatedAt"),
    }


def upsert_subscription_plan(plan_id: Optional[str], payload: Dict[str, Any]) -> str:
    timestamps = {"updatedAt": firestore.SERVER_TIMESTAMP}
    if not plan_id:
        ref = db.collection("subscription_plans").document()
        ref.set({**payload, **timestamps, "createdAt": firestore.SERVER_TIMESTAMP})
        return ref.id

    ref = db.collection("subscription_plans").document(plan_id)
    ref.set({**payload, **timestamps}, merge=True)
    return plan_id


def delete_subscription_plan(plan_id: str) -> bool:
    ref = db.collection("subscription_plans").document(plan_id)
    if not ref.get().exists:
        return False
    ref.delete()
    return True


def list_payments(limit: int = 200) -> List[Dict[str, Any]]:
    payments: List[Dict[str, Any]] = []
    snaps = (
        db.collection("payments")
        .order_by("createdAt", direction=Query.DESCENDING)
        .limit(limit)
        .stream()
    )
    for snap in snaps:
        data = snap.to_dict() or {}
        payments.append(
            {
                "id": snap.id,
                "userId": data.get("userId"),
                "planId": data.get("planId"),
                "amount": data.get("amount"),
                "currency": data.get("currency", "USD"),
                "status": data.get("status", "pending"),
                "transactionId": data.get("transactionId"),
                "createdAt": _iso(data.get("createdAt")),
            }
        )
    return payments


def list_payment_events(page: int = 1, page_size: int = 20) -> tuple[List[Dict[str, Any]], bool]:
    """Paginate payment events ordered by creation time (newest first).

    Returns a tuple of (events, has_next) to support pagination controls.
    """

    offset = max(page - 1, 0) * page_size
    query = (
        db.collection("payment_events")
        .order_by("createdAt", direction=Query.DESCENDING)
        .offset(offset)
        .limit(page_size + 1)
    )
    snaps = list(query.stream())
    has_next = len(snaps) > page_size
    events: List[Dict[str, Any]] = []

    for snap in snaps[:page_size]:
        data = snap.to_dict() or {}
        events.append(
            {
                "id": snap.id,
                "user_email": data.get("user_email") or data.get("userEmail"),
                "stripe_invoice_id": data.get("stripe_invoice_id") or data.get("invoice_id"),
                "amount_myr": data.get("amount_myr") or data.get("amount") or 0,
                "status": data.get("status", "unknown"),
                "createdAt": _iso(data.get("createdAt")),
            }
        )

    return events, has_next


def list_revenue_logs(limit: int = 500) -> Dict[str, Any]:
    """Return revenue log entries ordered by creation time (newest first)."""

    try:
        plan_snaps = list(db.collection("subscription_plans").stream())
    except Exception:
        plan_snaps = []

    price_plan_map: Dict[str, Dict[str, Any]] = {}
    for snap in plan_snaps:
        pdata = snap.to_dict() or {}
        price_id = pdata.get("stripe_price_id")
        if price_id:
            price_plan_map[price_id] = {"id": snap.id, "name": pdata.get("name")}

    try:
        snaps = (
            db.collection("revenue_logs")
            .order_by("createdAt", direction=Query.DESCENDING)
            .limit(limit)
            .stream()
        )
    except FailedPrecondition as exc:
        raise FailedPrecondition(
            f"Firestore index required for revenue_logs.createdAt: {exc.message}"
        )

    user_cache: Dict[str, Optional[str]] = {}
    logs: List[Dict[str, Any]] = []
    revenue_total = 0.0

    for snap in snaps:
        data = snap.to_dict() or {}
        user_id = data.get("userId") or data.get("user_id")
        price_id = data.get("priceId") or data.get("price_id")
        amount = data.get("amount") or 0
        try:
            amount_val = float(amount)
        except (TypeError, ValueError):
            amount_val = 0.0
        revenue_total += amount_val

        if user_id not in user_cache:
            user_snap = db.collection("users").document(str(user_id)).get()
            user_cache[user_id] = (user_snap.to_dict() or {}).get("email") if user_snap.exists else None

        plan_info = price_plan_map.get(price_id) or {}
        logs.append(
            {
                "id": snap.id,
                "user_id": user_id,
                "user_email": user_cache.get(user_id),
                "price_id": price_id,
                "plan_name": plan_info.get("name"),
                "plan_id": plan_info.get("id"),
                "amount": amount_val,
                "currency": data.get("currency", "MYR"),
                "stripe_subscription_id": data.get("stripeSubscriptionId")
                or data.get("stripe_subscription_id"),
                "createdAt": _iso(data.get("createdAt")),
            }
        )

    return {"items": logs, "total_myr": revenue_total}
