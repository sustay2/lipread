from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse

from app.services.backend_client import BackendClient

router = APIRouter(prefix="/courses", tags=["courses"])


def _render(request: Request, template: str, context: dict):
    templates = request.state.templates
    return templates.TemplateResponse(template, {"request": request, "settings": request.state.settings, **context})


def _client() -> BackendClient:
    return BackendClient()


@router.get("", response_class=HTMLResponse)
async def course_list(request: Request):
    client = _client()
    try:
        courses = client.get_courses()
    except Exception:
        courses = [
            {"id": "course-1", "title": "Lip Reading Basics", "description": "Foundations", "status": "draft"},
            {"id": "course-2", "title": "Advanced Practice", "description": "Deep dives", "status": "published"},
        ]
    return _render(request, "courses/list.html", {"courses": courses})


@router.get("/{course_id}", response_class=HTMLResponse)
async def course_detail(request: Request, course_id: str):
    client = _client()
    try:
        course = client.get_course(course_id)
    except Exception:
        course = {
            "id": course_id,
            "title": "Lip Reading Basics",
            "description": "Foundations",
            "difficulty": "beginner",
            "published": True,
            "thumbnail": None,
        }
    return _render(request, "courses/detail.html", {"course": course})


@router.post("", response_class=JSONResponse)
async def create_course(
    title: str = Form(...),
    description: str = Form(""),
    difficulty: str = Form("beginner"),
    published: bool = Form(False),
):
    payload = {
        "title": title,
        "summary": description,
        "difficulty": difficulty,
        "published": published,
    }
    try:
        created = _client().upsert_course(None, payload)
    except Exception:
        created = {"id": "new-course", **payload}
    return JSONResponse(created)
