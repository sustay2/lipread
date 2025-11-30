from __future__ import annotations

from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from app.services import firestore_admin

BASE_DIR = Path(__file__).resolve().parents[1]
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

router = APIRouter()


@router.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    kpis = firestore_admin.summarize_kpis()
    engagement = firestore_admin.collect_engagement_metrics()
    courses = firestore_admin.list_courses_with_modules()
    users = firestore_admin.list_users(limit=5)

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "kpis": kpis,
            "engagement": engagement,
            "courses": courses[:4],
            "recent_users": users,
        },
    )


@router.get("/users", response_class=HTMLResponse)
async def user_management(
    request: Request,
    q: Optional[str] = Query(default=None, description="Search by email"),
    role: Optional[str] = Query(default=None, description="Filter by role"),
):
    users = firestore_admin.list_users(search=q, role=role, limit=200)
    return templates.TemplateResponse(
        "users/list.html",
        {
            "request": request,
            "users": users,
            "search": q or "",
            "role": role or "",
        },
    )


@router.get("/users/{uid}", response_class=HTMLResponse)
async def user_detail(request: Request, uid: str):
    user = firestore_admin.get_user_detail(uid)
    if not user:
        return templates.TemplateResponse(
            "users/detail.html", {"request": request, "user": None}, status_code=404
        )

    return templates.TemplateResponse(
        "users/detail.html",
        {
            "request": request,
            "user": user,
        },
    )


@router.get("/courses", response_class=HTMLResponse)
async def course_management(request: Request):
    courses = firestore_admin.list_courses_with_modules()
    return templates.TemplateResponse(
        "courses/list.html",
        {
            "request": request,
            "courses": courses,
        },
    )


@router.get("/analytics", response_class=HTMLResponse)
async def analytics_dashboard(request: Request):
    kpis = firestore_admin.summarize_kpis()
    engagement = firestore_admin.collect_engagement_metrics()
    return templates.TemplateResponse(
        "analytics.html",
        {
            "request": request,
            "kpis": kpis,
            "engagement": engagement,
        },
    )


@router.get("/reports", response_class=HTMLResponse)
async def reports(request: Request):
    return templates.TemplateResponse("reports.html", {"request": request})


@router.get("/subscriptions", response_class=HTMLResponse)
async def subscriptions(request: Request):
    return templates.TemplateResponse("subscriptions.html", {"request": request})


@router.get("/billing", response_class=HTMLResponse)
async def billing(request: Request):
    return templates.TemplateResponse("billing.html", {"request": request})
