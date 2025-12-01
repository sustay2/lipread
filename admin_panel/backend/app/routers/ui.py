from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict
import json

from fastapi import APIRouter, Depends, Form, Query, Request, UploadFile, File
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.deps.admin_session import require_admin_session
from app.services import firestore_admin
from app.services.media_library import save_media_file
from app.services import reporting
from app.services.lessons import lesson_service
from app.services.activities import activity_service
from app.services.question_banks import question_bank_service

BASE_DIR = Path(__file__).resolve().parents[1]
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

router = APIRouter(dependencies=[Depends(require_admin_session)])


@router.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    kpis = firestore_admin.summarize_kpis()
    engagement = firestore_admin.collect_engagement_metrics()
    courses = firestore_admin.list_courses_with_modules()
    users = firestore_admin.list_users(limit=5)
    chart = firestore_admin.analytics_timeseries(days=14)

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "kpis": kpis,
            "engagement": engagement,
            "courses": courses[:4],
            "recent_users": users,
            "chart": chart,
        },
    )


@router.get("/content-library", response_class=HTMLResponse)
async def content_library(request: Request):
    media_items = firestore_admin.list_media_library()
    return templates.TemplateResponse(
        "content_library.html",
        {"request": request, "media_items": media_items},
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
    return templates.TemplateResponse(
        "courses/form.html",
        {
            "request": request,
            "course": None,
            "thumbnail": None,
        },
    )


@router.post("/courses")
async def course_create(
    title: str = Form(...),
    description: str = Form(""),
    difficulty: str = Form("beginner"),
    tags: str = Form(""),
    published: bool = Form(False),
    thumbnail: UploadFile = File(None),
):
    media_id = None
    if thumbnail and thumbnail.filename:
        media = save_media_file(thumbnail, media_type="images")
        media_id = media.get("id")
    payload = {
        "title": title,
        "description": description,
        "difficulty": difficulty,
        "tags": [t.strip() for t in tags.split(",") if t.strip()],
        "published": bool(published),
        "mediaId": media_id,
    }
    course_id = firestore_admin.create_course(payload)
    return RedirectResponse(url=f"/courses/{course_id}/modules?message=created", status_code=303)


@router.get("/courses/{course_id}/edit", response_class=HTMLResponse)
async def course_edit(request: Request, course_id: str):
    course = firestore_admin.get_course(course_id)
    thumbnail = firestore_admin.get_media(course.get("mediaId")) if course and course.get("mediaId") else None
    return templates.TemplateResponse(
        "courses/form.html", {"request": request, "course": course, "thumbnail": thumbnail}
    )


@router.post("/courses/{course_id}/update")
async def course_update(
    course_id: str,
    title: str = Form(...),
    description: str = Form(""),
    difficulty: str = Form("beginner"),
    tags: str = Form(""),
    published: bool = Form(False),
    thumbnail: UploadFile = File(None),
):
    media_id = None
    if thumbnail and thumbnail.filename:
        media = save_media_file(thumbnail, media_type="images")
        media_id = media.get("id")
    payload = {
        "title": title,
        "description": description,
        "difficulty": difficulty,
        "tags": [t.strip() for t in tags.split(",") if t.strip()],
        "published": bool(published),
    }
    if media_id:
        payload["mediaId"] = media_id
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
    next_order = firestore_admin.get_next_module_order(course_id)
    return templates.TemplateResponse(
        "modules/list.html",
        {
            "request": request,
            "course": course,
            "modules": modules,
            "message": message,
            "next_order": next_order,
        },
    )


@router.post("/courses/{course_id}/modules")
async def module_create(
    course_id: str,
    title: str = Form(...),
    summary: str = Form(""),
):
    order = firestore_admin.get_next_module_order(course_id)
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
async def lesson_list(
    request: Request,
    course_id: str,
    module_id: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    message: Optional[str] = None,
):
    course = firestore_admin.get_course(course_id)
    module = lesson_service.get_module(course_id, module_id)
    next_order = 0
    if not course or not module:
        module_ctx = module or {"id": module_id, "title": "Unknown module"}
        course_ctx = course or {"id": course_id, "title": "Unknown course"}
        return templates.TemplateResponse(
            "lessons/list.html",
            {
                "request": request,
                "course": course_ctx,
                "module": module_ctx,
                "lessons": [],
                "message": "Module not found",
                "page": page,
                "page_size": page_size,
                "total": 0,
                "next_order": next_order,
            },
            status_code=404,
        )
    lessons, total = lesson_service.list_lessons(course_id, module_id, page=page, page_size=page_size)
    next_order = firestore_admin.get_next_lesson_order(course_id, module_id)
    return templates.TemplateResponse(
        "lessons/list.html",
        {
            "request": request,
            "course": course,
            "module": module,
            "lessons": lessons,
            "message": message,
            "page": page,
            "page_size": page_size,
            "total": total,
            "next_order": next_order,
        },
    )


@router.get(
    "/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}",
    response_class=HTMLResponse,
)
async def lesson_detail(
    request: Request,
    course_id: str,
    module_id: str,
    lesson_id: str,
    message: Optional[str] = None,
):
    course = firestore_admin.get_course(course_id)
    module = lesson_service.get_module(course_id, module_id)
    lesson = lesson_service.get_lesson(course_id, module_id, lesson_id)
    if not course or not module or not lesson:
        course_ctx = course or {"id": course_id, "title": "Unknown course"}
        module_ctx = module or {"id": module_id, "title": "Unknown module"}
        return templates.TemplateResponse(
            "lessons/form.html",
            {"request": request, "course": course_ctx, "module": module_ctx, "lesson": lesson},
            status_code=404,
        )
    return templates.TemplateResponse(
        "lessons/form.html",
        {
            "request": request,
            "course": course,
            "module": module,
            "lesson": lesson,
            "message": message,
        },
    )


@router.post("/courses/{course_id}/modules/{module_id}/lessons")
async def lesson_create(
    course_id: str,
    module_id: str,
    title: str = Form(...),
    estimatedMin: int = Form(0),
    objectives: str = Form(""),
):
    order = firestore_admin.get_next_lesson_order(course_id, module_id)
    lesson_service.create_lesson(
        course_id,
        module_id,
        {
            "title": title,
            "order": int(order),
            "estimatedMin": int(estimatedMin),
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
    lesson_service.update_lesson(
        course_id,
        module_id,
        lesson_id,
        {
            "title": title,
            "order": int(order),
            "estimatedMin": int(estimatedMin),
            "objectives": [o.strip() for o in objectives.split("\n") if o.strip()],
        },
    )
    return RedirectResponse(
        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}?message=lesson-updated",
        status_code=303,
    )


@router.post("/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/delete")
async def lesson_delete(course_id: str, module_id: str, lesson_id: str):
    lesson_service.delete_lesson(course_id, module_id, lesson_id)
    lesson_service.reindex_orders(course_id, module_id)
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
    module = lesson_service.get_module(course_id, module_id)
    lesson = lesson_service.get_lesson(course_id, module_id, lesson_id)
    activities = activity_service.list_activities(course_id, module_id, lesson_id)
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


@router.get(
    "/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/new",
    response_class=HTMLResponse,
)
async def activity_create_view(request: Request, course_id: str, module_id: str, lesson_id: str):
    course = firestore_admin.get_course(course_id)
    module = lesson_service.get_module(course_id, module_id)
    lesson = lesson_service.get_lesson(course_id, module_id, lesson_id)
    next_order = activity_service.next_order(course_id, module_id, lesson_id)
    return templates.TemplateResponse(
        "activities/activity_create.html",
        {
            "request": request,
            "course": course,
            "module": module,
            "lesson": lesson,
            "next_order": next_order,
        },
    )


@router.post(
    "/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities",
)
async def activity_create(
    request: Request,
    course_id: str,
    module_id: str,
    lesson_id: str,
    title: str = Form(""),
    type: str = Form(...),
    order: int = Form(0),
    maxScore: int = Form(100),
    passingScore: int = Form(60),
    bankTitle: str = Form(...),
    bankDifficulty: int = Form(1),
    bankTags: str = Form(""),
    bankDescription: str = Form(""),
):
    admin = request.session.get("admin") if request.session else None
    tags = [t.strip() for t in bankTags.split(",") if t.strip()]
    bank_id = question_bank_service.create_bank(
        title=bankTitle.strip(),
        difficulty=int(bankDifficulty),
        tags=tags,
        description=bankDescription.strip() or None,
        created_by=(admin or {}).get("uid"),
    )
    scoring_payload = {"maxScore": int(maxScore), "passingScore": int(passingScore)}
    activity_id = activity_service.create_activity(
        course_id,
        module_id,
        lesson_id,
        title=title or type,
        type=type,
        order=order,
        scoring=scoring_payload,
        config={},
        question_bank_id=bank_id,
        question_ids=[],
        embed_questions=False,
        created_by=(admin or {}).get("uid"),
    )
    return RedirectResponse(
        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=activity-created",
        status_code=303,
    )


@router.get(
    "/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}",
    response_class=HTMLResponse,
)
async def activity_detail(
    request: Request,
    course_id: str,
    module_id: str,
    lesson_id: str,
    activity_id: str,
    message: Optional[str] = None,
):
    course = firestore_admin.get_course(course_id)
    module = lesson_service.get_module(course_id, module_id)
    lesson = lesson_service.get_lesson(course_id, module_id, lesson_id)
    activity = activity_service.get_activity(course_id, module_id, lesson_id, activity_id)
    return templates.TemplateResponse(
        "activities/activity_detail.html",
        {
            "request": request,
            "course": course,
            "module": module,
            "lesson": lesson,
            "activity": activity,
            "message": message,
        },
    )


@router.get(
    "/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}/edit",
    response_class=HTMLResponse,
)
async def activity_edit_view(request: Request, course_id: str, module_id: str, lesson_id: str, activity_id: str):
    course = firestore_admin.get_course(course_id)
    module = lesson_service.get_module(course_id, module_id)
    lesson = lesson_service.get_lesson(course_id, module_id, lesson_id)
    activity = activity_service.get_activity(course_id, module_id, lesson_id, activity_id)
    banks = question_bank_service.list_banks()
    questions_by_bank = {b.id: question_bank_service.list_questions(b.id, as_dict=True) for b in banks}
    return templates.TemplateResponse(
        "activities/activity_edit.html",
        {
            "request": request,
            "course": course,
            "module": module,
            "lesson": lesson,
            "activity": activity,
            "banks": banks,
            "questions_by_bank": questions_by_bank,
        },
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
    maxScore: int = Form(100),
    passingScore: int = Form(60),
    questionBankId: Optional[str] = Form(None),
    questionIds: List[str] = Form([]),
    embedQuestions: bool = Form(False),
):
    scoring_payload = {"maxScore": int(maxScore), "passingScore": int(passingScore)}
    activity_service.update_activity(
        course_id,
        module_id,
        lesson_id,
        activity_id,
        title=title or type,
        type=type,
        order=order,
        scoring=scoring_payload,
        config={"questionBankId": questionBankId, "embedQuestions": embedQuestions},
        question_bank_id=questionBankId,
        question_ids=questionIds,
        embed_questions=embedQuestions,
    )
    return RedirectResponse(
        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=activity-updated",
        status_code=303,
    )


@router.post(
    "/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}/delete"
)
async def activity_delete(course_id: str, module_id: str, lesson_id: str, activity_id: str):
    activity_service.delete_activity(course_id, module_id, lesson_id, activity_id)
    return RedirectResponse(
        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=activity-deleted",
        status_code=303,
    )


@router.get("/analytics", response_class=HTMLResponse)
async def analytics_dashboard(
    request: Request,
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
):
    kpis = firestore_admin.summarize_kpis()
    engagement = firestore_admin.collect_engagement_metrics()
    start_dt = datetime.fromisoformat(start_date) if start_date else None
    end_dt = datetime.fromisoformat(end_date) if end_date else None
    chart = firestore_admin.analytics_timeseries(days=30, start_date=start_dt.date() if start_dt else None, end_date=end_dt.date() if end_dt else None)
    return templates.TemplateResponse(
        "analytics.html",
        {
            "request": request,
            "kpis": kpis,
            "engagement": engagement,
            "chart": chart,
        },
    )


@router.get("/reports", response_class=HTMLResponse)
async def reports(request: Request):
    report_name = request.query_params.get("report")
    message = request.query_params.get("message")
    today_str = datetime.utcnow().date().isoformat()
    default_start = request.query_params.get("start_date") or today_str
    default_end = request.query_params.get("end_date") or today_str
    return templates.TemplateResponse(
        "reports.html",
        {
            "request": request,
            "report_name": report_name,
            "message": message,
            "start_date": default_start,
            "end_date": default_end,
        },
    )


@router.post("/reports")
async def generate_report(
    report_type: str = Form(...),
    start_date: str = Form(...),
    end_date: str = Form(...),
    course: str = Form(""),
    template_name: str = Form(""),
):
    start_dt = datetime.fromisoformat(start_date)
    end_dt = datetime.fromisoformat(end_date)
    chart = firestore_admin.analytics_timeseries(
        days=(end_dt - start_dt).days + 1,
        start_date=start_dt.date(),
        end_date=end_dt.date(),
    )
    file_name = reporting.generate_pdf_report(
        report_type=report_type,
        start_date=start_dt.date(),
        end_date=end_dt.date(),
        course=course,
        template_name=template_name,
        chart=chart,
    )
    return RedirectResponse(
        url=f"/reports?report={file_name}&message=generated",
        status_code=303,
    )


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
