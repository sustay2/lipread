from .firebase_client import get_firebase_app, get_firestore_client  # noqa: F401
from .firestore_admin import (  # noqa: F401
    list_users,
    get_user_detail,
    summarize_kpis,
    list_courses_with_modules,
    collect_engagement_metrics,
)
