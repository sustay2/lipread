from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from app.services.backend_client import BackendClient

router = APIRouter(prefix="/courses/{course_id}/modules", tags=["modules"])


def _render(request: Request, template: str, context: dict):
    templates = request.state.templates
    return templates.TemplateResponse(template, {"request": request, "settings": request.state.settings, **context})


@router.get("", response_class=HTMLResponse)
async def module_list(request: Request, course_id: str):
    client = BackendClient()
    try:
        modules = client.get_modules(course_id)
    except Exception:
        modules = [
            {"id": "mod-1", "title": "Intro", "description": "Basics", "lesson_count": 5},
            {"id": "mod-2", "title": "Vowels", "description": "Practice", "lesson_count": 8},
        ]
    return _render(request, "modules/list.html", {"modules": modules, "course_id": course_id})
