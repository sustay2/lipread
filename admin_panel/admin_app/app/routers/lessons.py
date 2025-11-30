from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from app.services.backend_client import BackendClient

router = APIRouter(prefix="/modules/{module_id}/lessons", tags=["lessons"])


def _render(request: Request, template: str, context: dict):
    templates = request.state.templates
    return templates.TemplateResponse(template, {"request": request, "settings": request.state.settings, **context})


@router.get("", response_class=HTMLResponse)
async def lesson_list(request: Request, module_id: str):
    client = BackendClient()
    try:
        lessons = client.get_lessons(module_id)
    except Exception:
        lessons = [
            {"id": "lesson-1", "title": "Vowel Basics", "type": "video", "duration": "6:00", "activities": 3},
            {"id": "lesson-2", "title": "Consonant Drill", "type": "text", "duration": "8:30", "activities": 2},
        ]
    breadcrumb = {"module_id": module_id, "course_id": "course-1"}
    return _render(request, "lessons/list.html", {"lessons": lessons, "breadcrumb": breadcrumb})
