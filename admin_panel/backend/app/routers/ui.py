from __future__ import annotations

from pathlib import Path
from typing import Optional
import json

from fastapi import APIRouter, Form, Query, Request
from fastapi.responses import HTMLResponse, RedirectResponse
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
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    message: Optional[str] = None,
):
    users, total = firestore_admin.paginate_users(search=q, role=role, page=page, page_size=page_size)
    return templates.TemplateResponse(
        "users/list.html",
        {
            "request": request,
            "users": users,
            "search": q or "",
            "role": role or "",
            "page": page,
            "page_size": page_size,
            "total": total,
            "message": message,
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


@router.post("/users/{uid}/update")
async def user_update(
    uid: str,
    display_name: str = Form(None),
    role: str = Form(None),
    status: str = Form(None),
):
    firestore_admin.update_user(uid, display_name, role, status)
    return RedirectResponse(url=f"/users/{uid}?message=updated", status_code=303)


@router.post("/users/{uid}/disable")
async def user_disable(uid: str, disabled: bool = Form(True)):
    firestore_admin.soft_disable_user(uid, disabled)
    return RedirectResponse(url=f"/users/{uid}?message=status-updated", status_code=303)


@router.post("/users/{uid}/logout")
async def user_force_logout(uid: str):
    firestore_admin.force_logout_user(uid)
    return RedirectResponse(url=f"/users/{uid}?message=logout-forced", status_code=303)


@router.get("/courses", response_class=HTMLResponse)
async def course_management(request: Request, message: Optional[str] = None):
    courses = firestore_admin.list_courses_with_modules()
    return templates.TemplateResponse(
        "courses/list.html",
        {
            "request": request,
            "courses": courses,
            "message": message,
        },
    )


@router.get("/courses/new", response_class=HTMLResponse)
async def course_new(request: Request):
    return templates.TemplateResponse("courses/form.html", {"request": request, "course": None})


@router.post("/courses")
async def course_create(
    title: str = Form(...),
    description: str = Form(""),
    difficulty: str = Form(""),
    tags: str = Form(""),
    published: bool = Form(False),
):
    payload = {
        "title": title,
        "description": description,
        "difficulty": difficulty,
        "tags": [t.strip() for t in tags.split(",") if t.strip()],
        "published": bool(published),
    }
    course_id = firestore_admin.create_course(payload)
    return RedirectResponse(url=f"/courses/{course_id}/modules?message=created", status_code=303)


@router.get("/courses/{course_id}/edit", response_class=HTMLResponse)
async def course_edit(request: Request, course_id: str):
    course = firestore_admin.get_course(course_id)
    return templates.TemplateResponse(
        "courses/form.html", {"request": request, "course": course}
    )


@router.post("/courses/{course_id}/update")
async def course_update(
    course_id: str,
    title: str = Form(...),
    description: str = Form(""),
    difficulty: str = Form(""),
    tags: str = Form(""),
    published: bool = Form(False),
):
    payload = {
        "title": title,
        "description": description,
        "difficulty": difficulty,
        "tags": [t.strip() for t in tags.split(",") if t.strip()],
        "published": bool(published),
    }
    firestore_admin.update_course(course_id, payload)
    return RedirectResponse(url=f"/courses?message=updated", status_code=303)


@router.post("/courses/{course_id}/delete")
async def course_delete(course_id: str):
    firestore_admin.delete_course(course_id)
    return RedirectResponse(url="/courses?message=deleted", status_code=303)


@router.get("/courses/{course_id}/modules", response_class=HTMLResponse)
async def module_list(request: Request, course_id: str, message: Optional[str] = None):
    course = firestore_admin.get_course(course_id)
    modules = firestore_admin.list_modules(course_id)
    return templates.TemplateResponse(
        "modules/list.html",
        {
            "request": request,
            "course": course,
            "modules": modules,
            "message": message,
        },
    )


@router.post("/courses/{course_id}/modules")
async def module_create(
    course_id: str,
    title: str = Form(...),
    summary: str = Form(""),
    order: int = Form(0),
):
    firestore_admin.create_module(course_id, {"title": title, "summary": summary, "order": order})
    return RedirectResponse(url=f"/courses/{course_id}/modules?message=module-created", status_code=303)


@router.post("/courses/{course_id}/modules/{module_id}/update")
async def module_update(
    course_id: str,
    module_id: str,
    title: str = Form(...),
    summary: str = Form(""),
    order: int = Form(0),
):
    firestore_admin.update_module(course_id, module_id, {"title": title, "summary": summary, "order": order})
    return RedirectResponse(url=f"/courses/{course_id}/modules?message=module-updated", status_code=303)


@router.post("/courses/{course_id}/modules/{module_id}/delete")
async def module_delete(course_id: str, module_id: str):
    firestore_admin.delete_module(course_id, module_id)
    return RedirectResponse(url=f"/courses/{course_id}/modules?message=module-deleted", status_code=303)


@router.get("/courses/{course_id}/modules/{module_id}/lessons", response_class=HTMLResponse)
async def lesson_list(request: Request, course_id: str, module_id: str, message: Optional[str] = None):
    course = firestore_admin.get_course(course_id)
    modules = firestore_admin.list_modules(course_id)
    module = next((m for m in modules if m["id"] == module_id), None)
    lessons = firestore_admin.list_lessons(course_id, module_id)
    return templates.TemplateResponse(
        "lessons/list.html",
        {
            "request": request,
            "course": course,
            "module": module,
            "lessons": lessons,
            "message": message,
        },
    )


@router.post("/courses/{course_id}/modules/{module_id}/lessons")
async def lesson_create(
    course_id: str,
    module_id: str,
    title: str = Form(...),
    order: int = Form(0),
    estimatedMin: int = Form(0),
    objectives: str = Form(""),
):
    firestore_admin.create_lesson(
        course_id,
        module_id,
        {
            "title": title,
            "order": order,
            "estimatedMin": estimatedMin,
            "objectives": [o.strip() for o in objectives.split("\n") if o.strip()],
        },
    )
    return RedirectResponse(
        url=f"/courses/{course_id}/modules/{module_id}/lessons?message=lesson-created",
        status_code=303,
    )


@router.post("/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/update")
async def lesson_update(
    course_id: str,
    module_id: str,
    lesson_id: str,
    title: str = Form(...),
    order: int = Form(0),
    estimatedMin: int = Form(0),
    objectives: str = Form(""),
):
    firestore_admin.update_lesson(
        course_id,
        module_id,
        lesson_id,
        {
            "title": title,
            "order": order,
            "estimatedMin": estimatedMin,
            "objectives": [o.strip() for o in objectives.split("\n") if o.strip()],
        },
    )
    return RedirectResponse(
        url=f"/courses/{course_id}/modules/{module_id}/lessons?message=lesson-updated",
        status_code=303,
    )


@router.post("/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/delete")
async def lesson_delete(course_id: str, module_id: str, lesson_id: str):
    firestore_admin.delete_lesson(course_id, module_id, lesson_id)
    return RedirectResponse(
        url=f"/courses/{course_id}/modules/{module_id}/lessons?message=lesson-deleted",
        status_code=303,
    )


@router.get(
    "/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities",
    response_class=HTMLResponse,
)
async def activity_list(
    request: Request, course_id: str, module_id: str, lesson_id: str, message: Optional[str] = None
):
    course = firestore_admin.get_course(course_id)
    module = next((m for m in firestore_admin.list_modules(course_id) if m["id"] == module_id), None)
    lesson = next(
        (l for l in firestore_admin.list_lessons(course_id, module_id) if l["id"] == lesson_id),
        None,
    )
    activities = firestore_admin.list_activities(course_id, module_id, lesson_id)
    return templates.TemplateResponse(
        "activities/list.html",
        {
            "request": request,
            "course": course,
            "module": module,
            "lesson": lesson,
            "activities": activities,
            "message": message,
        },
    )


@router.post(
    "/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities",
)
async def activity_create(
    course_id: str,
    module_id: str,
    lesson_id: str,
    title: str = Form(""),
    type: str = Form(...),
    order: int = Form(0),
    videoId: str = Form(""),
    visemeSetId: str = Form(""),
    abVariant: str = Form(""),
    config: str = Form(""),
    scoring: str = Form(""),
):
    firestore_admin.create_activity(
        course_id,
        module_id,
        lesson_id,
        {
            "title": title or type,
            "type": type,
            "order": order,
            "videoId": videoId or None,
            "visemeSetId": visemeSetId or None,
            "abVariant": abVariant or None,
            "config": json.loads(config) if config else {},
            "scoring": json.loads(scoring) if scoring else {},
        },
    )
    return RedirectResponse(
        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=activity-created",
        status_code=303,
    )


@router.post(
    "/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}/update"
)
async def activity_update(
    course_id: str,
    module_id: str,
    lesson_id: str,
    activity_id: str,
    title: str = Form(""),
    type: str = Form(...),
    order: int = Form(0),
    videoId: str = Form(""),
    visemeSetId: str = Form(""),
    abVariant: str = Form(""),
    config: str = Form(""),
    scoring: str = Form(""),
):
    firestore_admin.update_activity(
        course_id,
        module_id,
        lesson_id,
        activity_id,
        {
            "title": title or type,
            "type": type,
            "order": order,
            "videoId": videoId or None,
            "visemeSetId": visemeSetId or None,
            "abVariant": abVariant or None,
            "config": json.loads(config) if config else {},
            "scoring": json.loads(scoring) if scoring else {},
        },
    )
    return RedirectResponse(
        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=activity-updated",
        status_code=303,
    )


@router.post(
    "/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}/delete"
)
async def activity_delete(course_id: str, module_id: str, lesson_id: str, activity_id: str):
    firestore_admin.delete_activity(course_id, module_id, lesson_id, activity_id)
    return RedirectResponse(
        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=activity-deleted",
        status_code=303,
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
async def subscriptions(request: Request, message: Optional[str] = None):
    plans = firestore_admin.list_subscription_plans()
    return templates.TemplateResponse(
        "subscriptions.html",
        {"request": request, "plans": plans, "message": message},
    )


@router.post("/subscriptions")
async def create_subscription_plan(
    plan_id: str = Form(None),
    name: str = Form(...),
    price: float = Form(...),
    currency: str = Form("USD"),
    interval: str = Form("month"),
    trialDays: int = Form(0),
    features: str = Form(""),
):
    firestore_admin.upsert_subscription_plan(
        plan_id,
        {
            "name": name,
            "price": price,
            "currency": currency,
            "interval": interval,
            "trialDays": trialDays,
            "features": [f.strip() for f in features.split("\n") if f.strip()],
        },
    )
    return RedirectResponse(url="/subscriptions?message=plan-saved", status_code=303)


@router.post("/subscriptions/{plan_id}/delete")
async def delete_subscription_plan(plan_id: str):
    firestore_admin.delete_subscription_plan(plan_id)
    return RedirectResponse(url="/subscriptions?message=plan-deleted", status_code=303)


@router.get("/billing", response_class=HTMLResponse)
async def billing(request: Request):
    payments = firestore_admin.list_payments(limit=200)
    return templates.TemplateResponse("billing.html", {"request": request, "payments": payments})
