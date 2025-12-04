from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

router = APIRouter(prefix="/engagement", tags=["engagement"])


def _render(request: Request, template: str, context: dict):
    templates = request.state.templates
    return templates.TemplateResponse(template, {"request": request, "settings": request.state.settings, **context})


@router.get("", response_class=HTMLResponse)
async def engagement_dashboard(request: Request):
    metrics = {
        "daily_active_users": 874,
        "lesson_completion_rate": 78,
        "quiz_participation": 64,
        "avg_time": "32m",
    }
    active_users = [
        {"name": "Grace Lee", "email": "grace@example.com", "streak": 5},
        {"name": "Tom M", "email": "tom@example.com", "streak": 12},
    ]
    return _render(request, "analytics/engagement.html", {"metrics": metrics, "active_users": active_users})
