from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

router = APIRouter()


def _render(request: Request, template: str, context: dict):
    templates = request.state.templates
    return templates.TemplateResponse(template, {"request": request, "settings": request.state.settings, **context})


@router.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    metrics = {
        "users": 12450,
        "lessons": 328,
        "quizzes": 142,
        "daily_active": 874,
    }
    activity = [
        {"label": "Mon", "value": 120},
        {"label": "Tue", "value": 152},
        {"label": "Wed", "value": 180},
        {"label": "Thu", "value": 170},
        {"label": "Fri", "value": 210},
    ]
    return _render(
        request,
        "analytics/dashboard.html",
        {"metrics": metrics, "activity": activity, "title": "Dashboard"},
    )
