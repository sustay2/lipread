from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from pathlib import Path
from typing import Optional, List, Dict, Any
import json

from fastapi import APIRouter, Depends, Form, Query, Request, UploadFile, File, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from firebase_admin import firestore as admin_firestore

from app.services.billing_service import STRIPE_DEFAULT_CURRENCY, stripe
from app.services.firebase_client import get_firestore_client

from app.deps.admin_session import require_admin_session
from app.services import firestore_admin
from app.services.media_library import save_media_file
from app.services.lessons import lesson_service
from app.services.activities import activity_service
from app.services.question_banks import question_bank_service
from app.services import analytics_report_service

BASE_DIR = Path(__file__).resolve().parents[1]
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))
db = get_firestore_client()

router = APIRouter(dependencies=[Depends(require_admin_session)])

def _validate_scoring(scoring: Dict[str, Any] | None, default_max: int = 100) -> Dict[str, int]:
    base_max = default_max if default_max is not None else 100
    payload = scoring or {}
    max_score = int(payload.get("maxScore", base_max))
    passing = int(payload.get("passingScore", max_score))
    return {"maxScore": max_score, "passingScore": passing}


@router.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    kpis = firestore_admin.summarize_kpis()
    engagement = firestore_admin.collect_engagement_metrics()
    courses = firestore_admin.list_courses_with_modules()
    users = firestore_admin.list_users(limit=5)
    chart = firestore_admin.analytics_timeseries(days=14)

    metrics = analytics_report_service.aggregate_all((None, None))

    # helper currency formatter (just reuse the reports one)
    from app.routers.report import _currency as format_currency

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "kpis": kpis,
            "engagement": engagement,
            "courses": courses[:4],
            "recent_users": users,
            "chart": chart,
            "metrics": metrics,
            "format_currency": format_currency,
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
    is_premium: bool = Form(False),
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
        "published": _parse_bool(published),
        "isPremium": _parse_bool(is_premium),
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
    is_premium: bool = Form(False),
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
        "published": _parse_bool(published),
        "isPremium": _parse_bool(is_premium),
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
    payload: str = Form(...),
    questionMedia: List[UploadFile] = File([]),
    dictationMedia: List[UploadFile] = File([]),
    practiceMedia: List[UploadFile] = File([]),
):
    admin = request.session.get("admin") if request.session else None
    data: Dict[str, Any] = json.loads(payload)
    activity_type = (data.get("type") or "").strip()
    if not activity_type:
        return RedirectResponse(
            url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=missing-type",
            status_code=303,
        )

    title = (data.get("title") or activity_type).strip()
    order = (
        int(data.get("order"))
        if data.get("order") is not None
        else activity_service.next_order(course_id, module_id, lesson_id)
    )
    scoring = data.get("scoring") or {}
    config = data.get("config") or {}
    if data.get("difficultyLevel"):
        config["difficultyLevel"] = data.get("difficultyLevel")
    embed_questions = bool(config.get("embedQuestions"))

    def _save_video(file: UploadFile, error_code: str) -> Optional[str]:
        if not file or not file.filename:
            return None
        if not (file.content_type or "").startswith("video/"):
            raise ValueError(error_code)
        media = save_media_file(file, media_type="videos")
        return media.get("id")

    if activity_type == "dictation":
        dict_items = data.get("dictationItems") or []
        if len(dict_items) != len(dictationMedia):
            return RedirectResponse(
                url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=dictation-media-mismatch",
                status_code=303,
            )
        scoring_payload = _validate_scoring(scoring, default_max=len(dict_items) or 100)
        for idx, item in enumerate(dict_items):
            try:
                media_id = _save_video(dictationMedia[idx], "dictation-media-invalid")
            except ValueError:
                return RedirectResponse(
                    url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=dictation-media-invalid",
                    status_code=303,
                )
            if not media_id:
                return RedirectResponse(
                    url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=dictation-media-missing",
                    status_code=303,
                )
            item["mediaId"] = media_id
        activity_id = activity_service.create_activity(
            course_id,
            module_id,
            lesson_id,
            title=title,
            type=activity_type,
            order=order,
            scoring=scoring_payload,
            config=config,
            dictation_items=dict_items,
            created_by=(admin or {}).get("uid"),
        )
    elif activity_type == "practice_lip":
        practice_items = data.get("practiceItems") or []
        if len(practice_items) != len(practiceMedia):
            return RedirectResponse(
                url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=practice-media-mismatch",
                status_code=303,
            )
        scoring_payload = _validate_scoring(scoring, default_max=len(practice_items) or 100)
        for idx, item in enumerate(practice_items):
            try:
                media_id = _save_video(practiceMedia[idx], "practice-media-invalid")
            except ValueError:
                return RedirectResponse(
                    url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=practice-media-invalid",
                    status_code=303,
                )
            if not media_id:
                return RedirectResponse(
                    url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=practice-media-missing",
                    status_code=303,
                )
            item["mediaId"] = media_id
        activity_id = activity_service.create_activity(
            course_id,
            module_id,
            lesson_id,
            title=title,
            type=activity_type,
            order=order,
            scoring=scoring_payload,
            config=config,
            practice_items=practice_items,
            created_by=(admin or {}).get("uid"),
        )
    else:
        bank_data = data.get("questionBank") or {}
        bank_title = (bank_data.get("title") or "").strip()
        if not bank_title:
            return RedirectResponse(
                url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=missing-bank-title",
                status_code=303,
            )
        bank_tags = bank_data.get("tags") or []
        bank_id = question_bank_service.create_bank(
            title=bank_title,
            difficulty=int(bank_data.get("difficulty") or 1),
            tags=bank_tags,
            description=(bank_data.get("description") or "").strip() or None,
            created_by=(admin or {}).get("uid"),
        )

        questions = data.get("questions") or []
        if len(questions) != len(questionMedia):
            return RedirectResponse(
                url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=question-media-mismatch",
                status_code=303,
            )

        created_questions: List[str] = []
        for idx, q in enumerate(questions):
            try:
                media_id = _save_video(questionMedia[idx], "question-media-invalid")
            except ValueError:
                return RedirectResponse(
                    url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=question-media-invalid",
                    status_code=303,
                )
            if not media_id:
                return RedirectResponse(
                    url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=question-media-missing",
                    status_code=303,
                )
            qid = question_bank_service.create_question(
                bank_id,
                stem=q.get("stem", ""),
                options=q.get("options") or [],
                answers=q.get("answers") or [],
                answer_pattern=q.get("answerPattern"),
                explanation=q.get("explanation"),
                tags=q.get("tags") or [],
                difficulty=int(q.get("difficulty") or 1),
                media_id=media_id,
                question_type=q.get("type", "mcq"),
            )
            created_questions.append(qid)

        scoring_payload = _validate_scoring(scoring)
        activity_id = activity_service.create_activity(
            course_id,
            module_id,
            lesson_id,
            title=title,
            type=activity_type,
            order=order,
            scoring=scoring_payload,
            config=config,
            question_bank_id=bank_id,
            question_ids=created_questions,
            embed_questions=embed_questions,
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
    if not activity:
        return RedirectResponse(
            url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities?message=activity-missing",
            status_code=303,
        )

    def _build_initial_activity() -> Dict[str, Any]:
        scoring = activity.get("scoring") or {"maxScore": 100, "passingScore": 60}
        difficulty_level = (activity.get("config") or {}).get("difficultyLevel") or "beginner"
        initial: Dict[str, Any] = {
            "title": activity.get("title") or "",
            "type": activity.get("type") or "quiz",
            "order": activity.get("order") or 0,
            "scoring": {
                "maxScore": scoring.get("maxScore", 100),
                "passingScore": scoring.get("passingScore", 60),
            },
            "config": activity.get("config") or {},
            "difficultyLevel": difficulty_level,
            "questionBank": None,
            "questions": [],
            "dictationItems": activity.get("dictationItems") or [],
            "practiceItems": activity.get("practiceItems") or [],
        }

        if initial["type"] == "quiz":
            bank_id = initial["config"].get("questionBankId") or activity.get("questionBankId")
            if bank_id:
                bank = question_bank_service.get_bank(bank_id)
                if bank:
                    initial["questionBank"] = {
                        "id": bank.id,
                        "title": bank.title,
                        "difficulty": bank.difficulty,
                        "tags": bank.tags,
                        "description": bank.description,
                    }
                    initial["difficultyLevel"] = initial.get("difficultyLevel") or (
                        "advanced"
                        if bank.difficulty >= 3
                        else "intermediate"
                        if bank.difficulty >= 2
                        else "beginner"
                    )
            questions_payload: List[Dict[str, Any]] = []
            for q in activity.get("questions") or []:
                resolved = (q.resolvedQuestion if hasattr(q, "resolvedQuestion") else None)
                if resolved is None and isinstance(q, dict):
                    resolved = q.get("resolvedQuestion") or q.get("data")
                resolved = resolved or {}
                question_id = getattr(q, "questionId", None)
                if question_id is None and isinstance(q, dict):
                    question_id = q.get("questionId") or q.get("id")
                questions_payload.append(
                    {
                        "id": question_id,
                        "stem": resolved.get("stem", ""),
                        "options": resolved.get("options") or [],
                        "answers": resolved.get("answers") or [],
                        "explanation": resolved.get("explanation") or "",
                        "answerPattern": resolved.get("answerPattern"),
                        "difficulty": resolved.get("difficulty"),
                        "tags": resolved.get("tags") or [],
                        "mediaId": resolved.get("mediaId"),
                    }
                )
            initial["questions"] = questions_payload
        return initial

    initial_activity = _build_initial_activity()
    return templates.TemplateResponse(
        "activities/activity_edit.html",
        {
            "request": request,
            "course": course,
            "module": module,
            "lesson": lesson,
            "activity": activity,
            "initial_activity": initial_activity,
        },
    )


@router.post(
    "/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}/update"
)
async def activity_update(
    request: Request,
    course_id: str,
    module_id: str,
    lesson_id: str,
    activity_id: str,
    payload: str = Form(...),
    questionMedia: List[UploadFile] = File([]),
    dictationMedia: List[UploadFile] = File([]),
    practiceMedia: List[UploadFile] = File([]),
):
    """Unified update handler with Fix-A applied for ALL activity types."""
    admin = request.session.get("admin") if request.session else None
    data: Dict[str, Any] = json.loads(payload or "{}")

    activity_type = (data.get("type") or "").strip()
    if not activity_type:
        return RedirectResponse(
            url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=missing-type",
            status_code=303,
        )

    # Get current activity for resolving existing items/media
    current_activity = activity_service.get_activity(course_id, module_id, lesson_id, activity_id)

    def _save_video(file: UploadFile, error_code: str) -> Optional[str]:
        if not file or not file.filename:
            return None
        if not (file.content_type or "").startswith("video/"):
            raise ValueError(error_code)
        media = save_media_file(file, media_type="videos")
        return media.get("id")

    # Shared fields
    title = (data.get("title") or activity_type).strip()
    order = int(data.get("order") or 0)
    scoring = data.get("scoring") or {}
    config = data.get("config") or {}
    if data.get("difficultyLevel"):
        config["difficultyLevel"] = data.get("difficultyLevel")

    if activity_type == "dictation":
        items = data.get("dictationItems") or []
        upload_idx = 0
        processed = []

        for item in items:
            existing = item.get("existingMediaId")
            media_id = item.get("mediaId") or existing
            needs_upload = bool(item.get("needsUpload"))

            # Upload only if required
            if needs_upload:
                if upload_idx >= len(dictationMedia):
                    return RedirectResponse(
                        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=dictation-upload-mismatch",
                        status_code=303,
                    )
                try:
                    media_id = _save_video(dictationMedia[upload_idx], "dictation-media-invalid")
                except ValueError:
                    return RedirectResponse(
                        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=dictation-media-invalid",
                        status_code=303,
                    )
                upload_idx += 1

            if not media_id:  # New items MUST have media
                return RedirectResponse(
                    url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=dictation-media-missing",
                    status_code=303,
                )

            processed.append(
                {
                    "id": item.get("id"),
                    "correctText": item.get("correctText", ""),
                    "hints": item.get("hints"),
                    "mediaId": media_id,
                }
            )

        scoring_payload = _validate_scoring(scoring, default_max=len(processed) or 100)
        activity_service.update_activity(
            course_id,
            module_id,
            lesson_id,
            activity_id,
            title=title,
            type=activity_type,
            order=order,
            scoring=scoring_payload,
            config=config,
            dictation_items=processed,
        )

    elif activity_type == "practice_lip":
        items = data.get("practiceItems") or []
        upload_idx = 0
        processed = []

        for item in items:
            existing = item.get("existingMediaId")
            media_id = item.get("mediaId") or existing
            needs_upload = bool(item.get("needsUpload"))

            if needs_upload:
                if upload_idx >= len(practiceMedia):
                    return RedirectResponse(
                        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=practice-upload-mismatch",
                        status_code=303,
                    )
                try:
                    media_id = _save_video(practiceMedia[upload_idx], "practice-media-invalid")
                except ValueError:
                    return RedirectResponse(
                        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=practice-media-invalid",
                        status_code=303,
                    )
                upload_idx += 1

            if not media_id:
                return RedirectResponse(
                    url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=practice-media-missing",
                    status_code=303,
                )

            processed.append(
                {
                    "id": item.get("id"),
                    "description": item.get("description", ""),
                    "targetWord": item.get("targetWord"),
                    "mediaId": media_id,
                }
            )

        scoring_payload = _validate_scoring(scoring, default_max=len(processed) or 100)
        activity_service.update_activity(
            course_id,
            module_id,
            lesson_id,
            activity_id,
            title=title,
            type=activity_type,
            order=order,
            scoring=scoring_payload,
            config=config,
            practice_items=processed,
        )

    else:
        bank_payload = data.get("questionBank") or {}
        bank_id = (
            bank_payload.get("id")
            or config.get("questionBankId")
            or (current_activity.get("config", {}).get("questionBankId") if current_activity else None)
        )

        # Update existing bank or create new
        if bank_id:
            question_bank_service.update_bank(
                bank_id,
                title=(bank_payload.get("title") or "Untitled bank"),
                difficulty=int(bank_payload.get("difficulty") or 1),
                tags=bank_payload.get("tags") or [],
                description=bank_payload.get("description") or None,
            )
        else:
            bank_id = question_bank_service.create_bank(
                title=bank_payload.get("title") or "Untitled bank",
                difficulty=int(bank_payload.get("difficulty") or 1),
                tags=bank_payload.get("tags") or [],
                description=bank_payload.get("description") or None,
                created_by=(admin or {}).get("uid"),
            )

        config["questionBankId"] = bank_id

        # Process questions
        items = data.get("questions") or []
        upload_idx = 0
        processed_questions = []

        for item in items:
            existing = item.get("existingMediaId")
            media_id = item.get("mediaId") or existing
            needs_upload = bool(item.get("needsUpload"))

            # Upload new video if required
            if needs_upload:
                if upload_idx >= len(questionMedia):
                    return RedirectResponse(
                        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=question-upload-mismatch",
                        status_code=303,
                    )
                try:
                    media_id = _save_video(questionMedia[upload_idx], "question-media-invalid")
                except ValueError:
                    return RedirectResponse(
                        url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=question-media-invalid",
                        status_code=303,
                    )
                upload_idx += 1

            if not media_id:
                return RedirectResponse(
                    url=f"/courses/{course_id}/modules/{module_id}/lessons/{lesson_id}/activities/{activity_id}?message=question-media-missing",
                    status_code=303,
                )

            processed_questions.append(
                {
                    "id": item.get("id"),
                    "stem": item.get("stem", ""),
                    "options": item.get("options") or [],
                    "answers": item.get("answers") or [],
                    "answerPattern": item.get("answerPattern"),
                    "explanation": item.get("explanation"),
                    "tags": item.get("tags") or [],
                    "difficulty": int(item.get("difficulty") or 1),
                    "mediaId": media_id,
                    "type": item.get("type", "mcq"),
                }
            )

        # Commit questions
        question_ids = question_bank_service.upsert_questions(bank_id, processed_questions)
        scoring_payload = _validate_scoring(scoring)

        activity_service.update_activity(
            course_id,
            module_id,
            lesson_id,
            activity_id,
            title=title,
            type=activity_type,
            order=order,
            scoring=scoring_payload,
            config=config,
            question_bank_id=bank_id,
            question_ids=question_ids,
            embed_questions=bool(config.get("embedQuestions")),
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
    subscription_chart = firestore_admin.subscription_analytics(months=12)
    return templates.TemplateResponse(
        "analytics.html",
        {
            "request": request,
            "kpis": kpis,
            "engagement": engagement,
            "chart": chart,
            "subscription_chart": subscription_chart,
            "currency": STRIPE_DEFAULT_CURRENCY.upper(),
        },
    )


def _to_unit_amount(price_myr: float) -> int:
    return int((Decimal(str(price_myr)).quantize(Decimal("0.01"))) * 100)


def _serialize_plan_doc(doc) -> Dict[str, Any]:
    data = doc.to_dict() or {}
    return {
        "id": doc.id,
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


def _ensure_price_and_product(name: str, price_myr: float, product_id: Optional[str]) -> Dict[str, str]:
    unit_amount = _to_unit_amount(price_myr)

    if product_id:
        price = stripe.Price.create(
            currency=STRIPE_DEFAULT_CURRENCY,
            unit_amount=unit_amount,
            recurring={"interval": "month"},
            product=product_id,
        )
        return {"product_id": product_id, "price_id": price["id"]}

    product = stripe.Product.create(name=name)
    price = stripe.Price.create(
        currency=STRIPE_DEFAULT_CURRENCY,
        unit_amount=unit_amount,
        recurring={"interval": "month"},
        product=product["id"],
    )
    return {"product_id": product["id"], "price_id": price["id"]}


def _parse_bool(value: Any) -> bool:
    return str(value).lower() in ("true", "1", "on", "yes")


@router.get("/subscriptions", response_class=HTMLResponse)
async def subscription_plans(request: Request, message: Optional[str] = None):
    snaps = (
        db.collection("subscription_plans")
        .order_by("createdAt", direction=admin_firestore.Query.DESCENDING)
        .stream()
    )
    plans = [_serialize_plan_doc(doc) for doc in snaps]
    metadata = firestore_admin.get_subscription_metadata()
    return templates.TemplateResponse(
        "subscription_plans.html",
        {
            "request": request,
            "plans": plans,
            "message": message,
            "subscription_metadata": metadata,
        },
    )


@router.post("/subscriptions/metadata")
async def update_subscription_metadata(
    request: Request,
    transcription_limit: Optional[str] = Form(None),
    transcription_unlimited: bool = Form(False),
    can_access_premium_courses: bool = Form(False),
    free_trial_days: Optional[str] = Form("0"),
):
    errors: list[str] = []
    limit_val: Any = None
    if _parse_bool(transcription_unlimited):
        limit_val = "unlimited"
    elif transcription_limit is not None and str(transcription_limit).strip() != "":
        try:
            limit_val = int(str(transcription_limit).strip())
            if limit_val < 0:
                errors.append("Transcription limit cannot be negative")
        except ValueError:
            errors.append("Transcription limit must be a number")

    trial_days_val = 0
    try:
        trial_days_val = int(str(free_trial_days or 0))
        if trial_days_val < 0:
            errors.append("Free trial days cannot be negative")
    except ValueError:
        errors.append("Free trial days must be a number")

    payload = {
        "transcriptionLimit": limit_val,
        "canAccessPremiumCourses": _parse_bool(can_access_premium_courses),
        "freeTrialDays": trial_days_val,
    }

    if errors:
        snaps = (
            db.collection("subscription_plans")
            .order_by("createdAt", direction=admin_firestore.Query.DESCENDING)
            .stream()
        )
        plans = [_serialize_plan_doc(doc) for doc in snaps]
        return templates.TemplateResponse(
            "subscription_plans.html",
            {
                "request": request,
                "plans": plans,
                "message": None,
                "subscription_metadata": payload,
                "errors": errors,
            },
            status_code=400,
        )

    firestore_admin.update_subscription_metadata(payload)
    return RedirectResponse(url="/subscriptions?message=metadata-updated", status_code=303)


@router.get("/subscriptions/new", response_class=HTMLResponse)
async def new_subscription_plan(request: Request):
    return templates.TemplateResponse(
        "subscription_plan_edit.html", {"request": request, "plan": None}
    )


@router.get("/subscriptions/{plan_id}/edit", response_class=HTMLResponse)
async def edit_subscription_plan(request: Request, plan_id: str):
    snap = db.collection("subscription_plans").document(plan_id).get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Subscription plan not found")
    plan = _serialize_plan_doc(snap)
    return templates.TemplateResponse(
        "subscription_plan_edit.html", {"request": request, "plan": plan}
    )


@router.post("/subscriptions")
async def create_subscription_plan(
    name: str = Form(...),
    price_myr: float = Form(...),
    transcription_limit: Optional[int] = Form(None),
    is_transcription_unlimited: bool = Form(False),
    can_access_premium_courses: bool = Form(False),
    trial_period_days: int = Form(0),
    is_active: bool = Form(False),
):
    stripe_ids = _ensure_price_and_product(name, price_myr, product_id=None)
    payload = {
        "name": name,
        "price_myr": price_myr,
        "stripe_product_id": stripe_ids["product_id"],
        "stripe_price_id": stripe_ids["price_id"],
        "transcription_limit": transcription_limit,
        "is_transcription_unlimited": _parse_bool(is_transcription_unlimited),
        "can_access_premium_courses": _parse_bool(can_access_premium_courses),
        "trial_period_days": trial_period_days,
        "is_active": _parse_bool(is_active),
    }
    firestore_admin.upsert_subscription_plan(None, payload)
    return RedirectResponse(url="/subscriptions?message=plan-created", status_code=303)


@router.post("/subscriptions/{plan_id}")
async def update_subscription_plan(
    plan_id: str,
    name: str = Form(...),
    price_myr: float = Form(...),
    transcription_limit: Optional[int] = Form(None),
    is_transcription_unlimited: bool = Form(False),
    can_access_premium_courses: bool = Form(False),
    trial_period_days: int = Form(0),
    is_active: bool = Form(False),
):
    ref = db.collection("subscription_plans").document(plan_id)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Subscription plan not found")

    current_data = snap.to_dict() or {}
    current_price = Decimal(str(current_data.get("price_myr") or 0)).quantize(Decimal("0.01"))
    incoming_price = Decimal(str(price_myr)).quantize(Decimal("0.01"))
    price_changed = current_price != incoming_price

    product_id = current_data.get("stripe_product_id")
    price_id = current_data.get("stripe_price_id")

    if price_changed or not (product_id and price_id):
        stripe_ids = _ensure_price_and_product(name, price_myr, product_id=product_id)
        product_id = stripe_ids["product_id"]
        price_id = stripe_ids["price_id"]

    payload = {
        "name": name,
        "price_myr": price_myr,
        "stripe_product_id": product_id,
        "stripe_price_id": price_id,
        "transcription_limit": transcription_limit,
        "is_transcription_unlimited": _parse_bool(is_transcription_unlimited),
        "can_access_premium_courses": _parse_bool(can_access_premium_courses),
        "trial_period_days": trial_period_days,
        "is_active": _parse_bool(is_active),
    }
    firestore_admin.upsert_subscription_plan(plan_id, payload)
    return RedirectResponse(url="/subscriptions?message=plan-updated", status_code=303)


@router.get("/billing", response_class=HTMLResponse)
async def billing(request: Request):
    logs = firestore_admin.list_revenue_logs(limit=200)
    return templates.TemplateResponse(
        "billing/index.html", {"request": request, "transactions": logs}
    )


@router.get("/admin/payments", response_class=HTMLResponse)
async def payment_events(
    request: Request,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    events, has_next = firestore_admin.list_payment_events(page=page, page_size=page_size)
    return templates.TemplateResponse(
        "payment_events.html",
        {
            "request": request,
            "events": events,
            "page": page,
            "page_size": page_size,
            "has_next": has_next,
        },
    )


