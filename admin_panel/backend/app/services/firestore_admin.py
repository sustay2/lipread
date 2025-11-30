"""Admin-facing Firestore helpers mapped to the provided data model."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from google.cloud.firestore_v1.base_document import DocumentSnapshot

from app.services.firebase_client import get_firestore_client


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
                "difficulty": cdata.get("difficulty"),
                "modules": modules_payload,
                "lesson_count": lesson_count,
                "tags": cdata.get("tags", []),
                "createdAt": _iso(cdata.get("createdAt")),
            }
        )
    return output


def collect_engagement_metrics() -> Dict[str, Any]:
    users = list_users(limit=5000)
    today = datetime.now(timezone.utc).date()
    weekly_start = today.isocalendar().week

    lesson_completion: List[float] = []
    quiz_scores: List[int] = []

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
                quiz_scores.append(int(adata.get("score")))

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
