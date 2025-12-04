from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from app.services.backend_client import BackendClient

router = APIRouter(prefix="/lessons/{lesson_id}/activities", tags=["activities"])


def _render(request: Request, template: str, context: dict):
    templates = request.state.templates
    return templates.TemplateResponse(template, {"request": request, "settings": request.state.settings, **context})


@router.get("", response_class=HTMLResponse)
async def activity_list(request: Request, lesson_id: str):
    client = BackendClient()
    try:
        activities = client.get_activities(lesson_id)
    except Exception:
        activities = [
            {"id": "act-1", "type": "mcq", "question": "Identify the word", "status": "published"},
            {"id": "act-2", "type": "fill", "question": "Match the lips", "status": "draft"},
        ]
    return _render(request, "activities/list.html", {"activities": activities, "lesson_id": lesson_id})
