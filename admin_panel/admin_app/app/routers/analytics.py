from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from app.services.backend_client import BackendClient

router = APIRouter(prefix="/analytics", tags=["analytics"])


def _render(request: Request, template: str, context: dict):
    templates = request.state.templates
    return templates.TemplateResponse(template, {"request": request, "settings": request.state.settings, **context})


@router.get("", response_class=HTMLResponse)
async def analytics_home(request: Request):
    client = BackendClient()
    try:
        data = client.fetch_analytics()
    except Exception:
        data = {
            "totals": {"users": 12450, "subscribers": 6400, "dau": 874, "mau": 3250},
            "course_popularity": [
                {"name": "Basics", "value": 42},
                {"name": "Advanced", "value": 31},
                {"name": "Practice", "value": 27},
            ],
            "quiz_distribution": [80, 70, 60, 65],
        }
    return _render(request, "analytics/advanced.html", {"analytics": data})
