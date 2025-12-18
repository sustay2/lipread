from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

from app.services.billing_service import STRIPE_DEFAULT_CURRENCY, stripe
from app.services.firebase_client import get_firestore_client
from app.services.firestore_admin import (
    get_subscription_metadata,
    list_courses_with_modules,
    list_users,
    subscription_analytics,
)


db = get_firestore_client()


@dataclass
class DateRange:
    start: date
    end: date

    @classmethod
    def from_bounds(cls, start: Optional[date], end: Optional[date]) -> "DateRange":
        today = datetime.now(timezone.utc).date()
        if end is None:
            end = today
        if start is None:
            start = end - timedelta(days=29)
        if start > end:
            start, end = end, start
        return cls(start=start, end=end)


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
    try:
        return datetime.fromisoformat(str(value))
    except Exception:
        return None


def _month_label(dt: date) -> str:
    return dt.strftime("%b %Y")


def get_user_metrics(date_range: DateRange | None = None) -> Dict[str, Any]:
    window = date_range or DateRange.from_bounds(None, None)
    users = list_users(limit=5000)
    total_users = len(users)

    new_users_counter: Counter[str] = Counter()
    active_users = 0
    streaks: List[int] = []
    xp_distribution: Counter[str] = Counter()
    tasks_completed = 0
    tasks_assigned = 0

    bucket_edges = [0, 100, 500, 1000, 5000]

    for user in users:
        created_at = _to_datetime(user.get("createdAt"))
        if created_at and window.start <= created_at.date() <= window.end:
            new_users_counter[_month_label(created_at.date())] += 1

        last_active = _to_datetime(user.get("lastActiveAt"))
        if last_active and window.start <= last_active.date() <= window.end:
            active_users += 1

        stats = user.get("stats") or {}
        xp_val = stats.get("xp") or 0
        bucket = "0+"
        for idx in range(len(bucket_edges) - 1):
            low, high = bucket_edges[idx], bucket_edges[idx + 1]
            if low <= xp_val < high:
                bucket = f"{low}-{high}"
                break
        else:
            bucket = f"{bucket_edges[-1]}+"
        xp_distribution[bucket] += 1

        tasks_completed += int(stats.get("tasksCompleted", 0))
        tasks_assigned += int(stats.get("tasksAssigned", stats.get("tasksTotal", 0)))

        uid = user["id"]
        for streak_doc in (
            db.collection("users").document(uid).collection("streaks").stream()
        ):
            sdata = streak_doc.to_dict() or {}
            streaks.append(int(sdata.get("count", 0)))

    avg_streak = round(sum(streaks) / len(streaks), 2) if streaks else 0.0
    completion_rate = (
        round((tasks_completed / tasks_assigned) * 100, 2)
        if tasks_assigned
        else 0.0
    )

    ordered_months = sorted(new_users_counter.keys())
    new_users_series = [
        {"label": label, "count": new_users_counter[label]}
        for label in ordered_months
    ]

    xp_series = [
        {"label": label, "count": xp_distribution.get(label, 0)}
        for label in sorted(xp_distribution.keys())
    ]

    return {
        "total_users": total_users,
        "new_users_per_month": new_users_series,
        "active_users": active_users,
        "avg_streak": avg_streak,
        "xp_distribution": xp_series,
        "task_completion_rate": completion_rate,
    }


def get_course_metrics(date_range: DateRange | None = None) -> Dict[str, Any]:
    window = date_range or DateRange.from_bounds(None, None)
    courses = list_courses_with_modules()
    total_modules = sum(len(course.get("modules", [])) for course in courses)
    total_lessons = sum(course.get("lesson_count", 0) for course in courses)
    premium_courses = len([c for c in courses if c.get("isPremium")])

    course_lookup = {c.get("id"): c for c in courses}
    engagement: Dict[str, Dict[str, int]] = defaultdict(lambda: {"enrolled": 0, "completed": 0})
    activity_heatmap: Counter[str] = Counter()

    users = list_users(limit=5000)
    for user in users:
        uid = user["id"]
        for enroll in (
            db.collection("users").document(uid).collection("enrollments").stream()
        ):
            edata = enroll.to_dict() or {}
            course_id = edata.get("courseId") or enroll.id
            progress = edata.get("progress")
            updated_at = _to_datetime(edata.get("updatedAt"))
            if updated_at and not (window.start <= updated_at.date() <= window.end):
                continue
            engagement[course_id]["enrolled"] += 1
            if progress is not None and progress >= 70:
                engagement[course_id]["completed"] += 1

        for attempt in (
            db.collection("users").document(uid).collection("attempts").stream()
        ):
            adata = attempt.to_dict() or {}
            created_at = _to_datetime(adata.get("createdAt"))
            if created_at and window.start <= created_at.date() <= window.end:
                atype = str(adata.get("type") or "quiz").lower()
                if atype.startswith("practice"):
                    atype = "practice"
                activity_heatmap[atype] += 1

    top_courses = sorted(
        [
            {
                "id": cid,
                "title": course_lookup.get(cid, {}).get("title", cid),
                "enrolled": payload["enrolled"],
                "completed": payload["completed"],
            }
            for cid, payload in engagement.items()
        ],
        key=lambda item: item["enrolled"],
        reverse=True,
    )[:5]

    return {
        "total_courses": len(courses),
        "total_modules": total_modules,
        "total_lessons": total_lessons,
        "premium_courses": premium_courses,
        "top_courses": top_courses,
        "activity_heatmap": dict(activity_heatmap),
    }


def get_subscription_metrics(date_range: DateRange | None = None) -> Dict[str, Any]:
    window = date_range or DateRange.from_bounds(None, None)

    start_dt = datetime.combine(window.start, datetime.min.time(), tzinfo=timezone.utc)
    end_dt   = datetime.combine(window.end,   datetime.max.time(), tzinfo=timezone.utc)

    # ---- Load readable plan names ----
    plan_name_lookup = {}
    try:
        for snap in db.collection("subscription_plans").stream():
            pdata = snap.to_dict() or {}
            plan_name_lookup[snap.id] = pdata.get("name", snap.id)
    except Exception:
        pass

    # ---- Load subscriptions from Firestore ----
    active_by_plan: Counter[str] = Counter()
    status_breakdown: Counter[str] = Counter()
    monthly_new: Counter[str] = Counter()

    try:
        for snap in db.collection("user_subscriptions").stream():
            sub = snap.to_dict() or {}

            status = sub.get("status", "unknown")
            plan_id = sub.get("plan_id") or "Unknown"
            created_at = _to_datetime(sub.get("createdAt") or sub.get("billing_cycle_anchor"))

            status_breakdown[status] += 1

            # If subscription is active, count per plan
            if status == "active":
                active_by_plan[plan_id] += 1

            # Monthly new subscriptions
            if created_at and (window.start <= created_at.date() <= window.end):
                monthly_new[_month_label(created_at.date())] += 1

    except Exception as e:
        print("Subscription metric error:", e)

    active_by_plan_list = [
        {
            "plan_id": pid,
            "plan": plan_name_lookup.get(pid, pid),
            "count": count,
        }
        for pid, count in active_by_plan.items()
    ]

    # Convert monthly data to sorted list
    monthly_new_list = [
        {"label": lbl, "count": monthly_new[lbl]}
        for lbl in sorted(monthly_new.keys())
    ]

    return {
        "total_subscribers": sum(active_by_plan.values()),
        "active_by_plan": active_by_plan_list,
        "free_to_paid_conversion": 0.0,  # No Stripe data available
        "trial_conversion": 0.0,
        "monthly_new_subscriptions": monthly_new_list,
        "status_breakdown": dict(status_breakdown),
    }   


def get_revenue_metrics(
    date_range: DateRange | None = None, total_users: int | None = None
) -> Dict[str, Any]:

    window = date_range or DateRange.from_bounds(None, None)

    revenue_total = 0.0
    monthly_buckets: Counter[str] = Counter()

    try:
        for snap in db.collection("payments").stream():
            payment = snap.to_dict() or {}

            created_at = _to_datetime(payment.get("createdAt"))
            if not created_at:
                continue

            if not (window.start <= created_at.date() <= window.end):
                continue

            amount = float(payment.get("amount") or 0)
            revenue_total += amount
            monthly_buckets[_month_label(created_at.date())] += amount

    except Exception as e:
        print("Revenue metrics error:", e)

    labels = sorted(monthly_buckets.keys())
    monthly_revenue = [
        {"label": lbl, "amount": round(monthly_buckets[lbl], 2)}
        for lbl in labels
    ]

    mrr = monthly_revenue[-1]["amount"] if monthly_revenue else 0.0

    if total_users is None:
        total_users = len(list_users(limit=5000))

    arpu = round(revenue_total / total_users, 2) if total_users else 0.0

    # Churn is impossible to compute without consistent Stripe lifecycle data
    churn_rate = 0.0

    return {
        "total_revenue": round(revenue_total, 2),
        "mrr": round(mrr, 2),
        "arpu": arpu,
        "churn_rate": churn_rate,
        "monthly_revenue": monthly_revenue,
    }


def get_transcription_metrics(date_range: DateRange | None = None) -> Dict[str, Any]:
    window = date_range or DateRange.from_bounds(None, None)
    limit_config = get_subscription_metadata()
    monthly_limit = limit_config.get("transcriptionLimit") or 0

    per_user_uploads: Counter[str] = Counter()
    premium_usage = 0
    total_uploads = 0

    try:
        for snap in db.collection_group("transcriptions").stream():
            data = snap.to_dict() or {}
            created_at = _to_datetime(data.get("createdAt") or data.get("created_at"))
            if created_at and not (window.start <= created_at.date() <= window.end):
                continue
            owner: str = data.get("userId") or data.get("uid") or "unknown"
            per_user_uploads[owner] += 1
            total_uploads += 1
            if data.get("isPremium") or data.get("plan"):
                premium_usage += 1
    except Exception:
        pass

    unique_users = len(per_user_uploads) or 1
    avg_uploads = round(total_uploads / unique_users, 2) if total_uploads else 0.0
    hitting_limit = len([u for u, count in per_user_uploads.items() if monthly_limit and count >= monthly_limit])

    return {
        "total_uploads": total_uploads,
        "avg_uploads_per_user": avg_uploads,
        "users_at_limit": hitting_limit,
        "premium_usage": premium_usage,
    }


def aggregate_all(date_range: Tuple[Optional[date], Optional[date]] | None) -> Dict[str, Any]:
    window = DateRange.from_bounds(
        date_range[0] if date_range else None, date_range[1] if date_range else None
    )
    user_metrics = get_user_metrics(window)
    course_metrics = get_course_metrics(window)
    subscription_metrics = get_subscription_metrics(window)
    revenue_metrics = get_revenue_metrics(window, total_users=user_metrics.get("total_users"))
    transcription_metrics = get_transcription_metrics(window)

    return {
        "date_range": {"start": window.start, "end": window.end},
        "user": user_metrics,
        "course": course_metrics,
        "subscription": subscription_metrics,
        "revenue": revenue_metrics,
        "transcription": transcription_metrics,
    }