from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from app.services.backend_client import BackendClient

router = APIRouter(prefix="/progress", tags=["progress"])


def _render(request: Request, template: str, context: dict):
    templates = request.state.templates
    return templates.TemplateResponse(template, {"request": request, "settings": request.state.settings, **context})


@router.get("", response_class=HTMLResponse)
async def user_progress_overview(request: Request):
    client = BackendClient()
    try:
        progress = client.fetch_attempts({"summary": True})
    except Exception:
        progress = {
            "totals": {"courses": 12, "modules": 64, "lessons": 420},
            "reports": [
                {"user": "learner@example.com", "courses": 3, "quizzes": 12, "score": 88},
                {"user": "polyglot@example.com", "courses": 5, "quizzes": 22, "score": 92},
            ],
        }
    return _render(request, "progress/overview.html", {"progress": progress})


@router.get("/{user_id}", response_class=HTMLResponse)
async def user_progress_detail(request: Request, user_id: str):
    try:
        timeline = BackendClient().fetch_attempts({"user_id": user_id})
    except Exception:
        timeline = {
            "lessons": [
                {"title": "Vowels 101", "status": "completed", "completed_at": "2024-11-01"},
                {"title": "Consonants", "status": "in-progress", "completed_at": None},
            ],
            "quizzes": [
                {"title": "Quiz 1", "score": 90, "taken_at": "2024-11-01"},
                {"title": "Quiz 2", "score": 84, "taken_at": "2024-11-02"},
            ],
        }
    return _render(request, "progress/detail.html", {"user_id": user_id, "timeline": timeline})
