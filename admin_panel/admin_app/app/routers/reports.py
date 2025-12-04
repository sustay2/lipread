from datetime import datetime
from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse

from app.services.reports import ReportService

router = APIRouter(prefix="/reports", tags=["reports"])


def _render(request: Request, template: str, context: dict):
    templates = request.state.templates
    return templates.TemplateResponse(template, {"request": request, "settings": request.state.settings, **context})


@router.get("", response_class=HTMLResponse)
async def report_builder(request: Request):
    service = ReportService()
    templates = service.list_templates()
    return _render(request, "reports/builder.html", {"templates": templates})


@router.post("/generate", response_class=JSONResponse)
async def generate_report(
    report_type: str = Form(...),
    start_date: str = Form(...),
    end_date: str = Form(...),
):
    service = ReportService()
    result = service.generate_report(report_type, datetime.fromisoformat(start_date), datetime.fromisoformat(end_date))
    return JSONResponse(result)
