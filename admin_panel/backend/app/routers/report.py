from datetime import date, datetime
from io import BytesIO
from pathlib import Path
from typing import Optional, Tuple, Dict, Any

from fastapi import APIRouter, Depends, Form, Query, Request
from fastapi.responses import HTMLResponse, Response
from fastapi.templating import Jinja2Templates

from reportlab.lib.pagesizes import A4
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    Image,
)
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib import colors

from app.deps.admin_session import require_admin_session
from app.services import analytics_report_service


BASE_DIR = Path(__file__).resolve().parents[1]
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))
router = APIRouter(dependencies=[Depends(require_admin_session)])


# ---------------------------
# Helpers
# ---------------------------
def _parse_range(start: Optional[str], end: Optional[str]) -> Tuple[Optional[date], Optional[date]]:
    start_date = None
    end_date = None
    try:
        start_date = datetime.fromisoformat(start).date() if start else None
    except Exception:
        start_date = None
    try:
        end_date = datetime.fromisoformat(end).date() if end else None
    except Exception:
        end_date = None
    return start_date, end_date


def _currency(value: float) -> str:
    return f"RM {value:,.2f}"


# ---------------------------
# PDF generator (ReportLab)
# ---------------------------
def build_pdf(metrics: Dict[str, Any], admin_email: str, logo_path: str) -> bytes:
    """
    Convert analytics data into a styled PDF using ReportLab.
    """

    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        rightMargin=36,
        leftMargin=36,
        topMargin=36,
        bottomMargin=36,
    )

    styles = getSampleStyleSheet()
    story = []

    # --- Header / Logo -----------------------------------
    try:
        story.append(Image(logo_path, width=120, height=40))
        story.append(Spacer(1, 12))
    except Exception:
        # logo is optional
        pass

    story.append(Paragraph("<b>LipRead Analytics Report</b>", styles["Title"]))
    story.append(Spacer(1, 6))

    story.append(
        Paragraph(
            f"Generated on {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}<br/>"
            f"Admin: {admin_email}",
            styles["Normal"],
        )
    )
    story.append(Spacer(1, 18))

    # --- Render Metrics ----------------------------------
    for section_title, data in metrics.items():
        if section_title == "date_range":
            continue

        story.append(Paragraph(f"<b>{section_title.replace('_', ' ').title()}</b>", styles["Heading2"]))
        story.append(Spacer(1, 6))

        if isinstance(data, dict):
            table_rows = [["Metric", "Value"]]
            for key, value in data.items():
                if isinstance(value, (int, float)):
                    value = _currency(value) if "revenue" in key.lower() else f"{value:,}"

                table_rows.append([key.replace("_", " ").title(), str(value)])

            table = Table(table_rows, colWidths=[180, 260])
            table.setStyle(
                TableStyle(
                    [
                        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#f1f5f9")),
                        ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#0d6efd")),
                        ("ALIGN", (0, 0), (-1, -1), "LEFT"),
                        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                        ("BOTTOMPADDING", (0, 0), (-1, 0), 8),
                        ("BACKGROUND", (0, 1), (-1, -1), colors.white),
                        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#d1d5db")),
                    ]
                )
            )
            story.append(table)
            story.append(Spacer(1, 18))

        else:
            story.append(Paragraph(str(data), styles["Normal"]))
            story.append(Spacer(1, 12))

    doc.build(story)
    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes


# ---------------------------
# Web Routes
# ---------------------------

@router.get("/reports", response_class=HTMLResponse)
async def reports(
    request: Request,
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
):
    date_range = _parse_range(start_date, end_date)
    metrics = analytics_report_service.aggregate_all(date_range)
    window = metrics.get("date_range", {})
    start_val = window.get("start")
    end_val = window.get("end")

    return templates.TemplateResponse(
        "reports/index.html",
        {
            "request": request,
            "metrics": metrics,
            "start_date": start_val.isoformat() if start_val else None,
            "end_date": end_val.isoformat() if end_val else None,
            "format_currency": _currency,
        },
    )


@router.post("/reports/export")
async def export_report(
    request: Request,
    start_date: Optional[str] = Form(None),
    end_date: Optional[str] = Form(None),
):
    date_range = _parse_range(start_date, end_date)
    metrics = analytics_report_service.aggregate_all(date_range)

    admin = request.session.get("admin") or {}
    admin_email = admin.get("email", "admin@lipread.app")

    generated_at = datetime.utcnow()
    logo_path = str((BASE_DIR / "static" / "img" / "logo.png").resolve())

    pdf_bytes = build_pdf(metrics, admin_email, logo_path)

    filename = f"lipread-analytics-{generated_at.date().isoformat()}.pdf"
    headers = {"Content-Disposition": f'attachment; filename="{filename}"'}

    return Response(content=pdf_bytes, media_type="application/pdf", headers=headers)