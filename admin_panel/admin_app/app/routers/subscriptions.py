from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from app.services.subscriptions import SubscriptionService

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


def _render(request: Request, template: str, context: dict):
    templates = request.state.templates
    return templates.TemplateResponse(template, {"request": request, "settings": request.state.settings, **context})


@router.get("", response_class=HTMLResponse)
async def subscriptions_home(request: Request):
    service = SubscriptionService()
    return _render(request, "subscriptions/plans.html", {"plans": service.list_plans(), "payments": service.get_payments()})
