from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse

from app.services.backend_client import BackendClient
from app.services.subscriptions import SubscriptionService

router = APIRouter(prefix="/users", tags=["users"])


def _render(request: Request, template: str, context: dict):
    templates = request.state.templates
    return templates.TemplateResponse(template, {"request": request, "settings": request.state.settings, **context})


def _client(request: Request) -> BackendClient:
    return BackendClient()


@router.get("", response_class=HTMLResponse)
async def list_users(request: Request, q: str | None = None, role: str | None = None):
    client = _client(request)
    try:
        users = client.get_users(q, role)
    except Exception:
        users = [
            {
                "id": "demo-1",
                "name": "Demo Admin",
                "email": "admin@example.com",
                "role": "admin",
                "status": "active",
                "last_login": "2024-11-02",
            }
        ]
    return _render(request, "users/list.html", {"users": users, "query": q, "role": role})


@router.get("/{user_id}", response_class=HTMLResponse)
async def user_detail(request: Request, user_id: str):
    client = _client(request)
    subscriptions = SubscriptionService()
    try:
        user = client.get_user(user_id)
    except Exception:
        user = {
            "id": user_id,
            "name": "Learner Zero",
            "email": "learner@example.com",
            "role": "student",
            "status": "active",
            "subscription": "Pro",
        }
    progress = {
        "courses": 4,
        "completed": 18,
        "quizzes": 42,
        "average_score": 87,
    }
    history = subscriptions.list_billing_history(user_id)
    return _render(
        request,
        "users/detail.html",
        {"user": user, "progress": progress, "billing": history},
    )


@router.post("/{user_id}/edit", response_class=JSONResponse)
async def update_user(
    request: Request,
    user_id: str,
    name: str = Form(...),
    role: str = Form(...),
    status: str = Form(...),
):
    client = _client(request)
    payload = {"name": name, "role": role, "status": status}
    try:
        updated = client.patch_user(user_id, payload)
    except Exception:
        updated = {"id": user_id, **payload}
    return JSONResponse(updated)


@router.post("/{user_id}/reset-password", response_class=JSONResponse)
async def reset_password(user_id: str, email: str = Form(...)):
    client = BackendClient()
    try:
        result = client.reset_password(email)
    except Exception:
        result = {"status": "queued", "email": email}
    return JSONResponse(result)
