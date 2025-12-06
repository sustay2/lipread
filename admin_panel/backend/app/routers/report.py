from __future__ import annotations

from datetime import date, datetime
from io import BytesIO
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

from fastapi import APIRouter, Depends, Form, Query, Request
from fastapi.responses import HTMLResponse, Response
from fastapi.templating import Jinja2Templates
from reportlab.graphics.charts.barcharts import VerticalBarChart
from reportlab.graphics.charts.linecharts import HorizontalLineChart
from reportlab.graphics.charts.piecharts import Pie
from reportlab.graphics.shapes import Drawing
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, StyleSheet1, getSampleStyleSheet
from reportlab.pdfgen import canvas
from reportlab.platypus import (
    Image,
    KeepTogether,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

from app.deps.admin_session import require_admin_session
from app.services import analytics_report_service

BASE_DIR = Path(__file__).resolve().parents[1]
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))
router = APIRouter(dependencies=[Depends(require_admin_session)])

PRIMARY_COLOR = colors.HexColor("#0d6efd")
TEXT_DARK = colors.HexColor("#111827")
BORDER_COLOR = colors.HexColor("#d1d5db")
LIGHT_BG = colors.HexColor("#f8f9fa")
ACCENT_GREY = colors.HexColor("#6c757d")


# ---------------------------
# Helpers
# ---------------------------
class NumberedCanvas(canvas.Canvas):
    """Canvas that records page states to render 'Page X of Y' footers."""

    def __init__(self, *args, **kwargs):  # type: ignore[override]
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):  # type: ignore[override]
        self._saved_page_states.append(dict(self.__dict__))
        super().showPage()

    def save(self):  # type: ignore[override]
        self._saved_page_states.append(dict(self.__dict__))
        page_count = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self._draw_page_number(page_count)
            super().showPage()
        super().save()

    def _draw_page_number(self, page_count: int) -> None:
        self.saveState()
        footer_text = f"LipRead © 2025 — Page {self._pageNumber} of {page_count}"
        self.setFont("Helvetica", 9)
        self.setFillColor(colors.HexColor("#4b5563"))
        self.drawRightString(A4[0] - 40, 20, footer_text)
        self.restoreState()


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


def _currency(value: float | int | None) -> str:
    try:
        return f"RM {float(value or 0):,.2f}"
    except Exception:
        return "RM 0.00"


def _build_styles() -> StyleSheet1:
    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name="H1",
            fontName="Helvetica-Bold",
            fontSize=22,
            textColor=TEXT_DARK,
            spaceAfter=8,
        )
    )
    styles.add(
        ParagraphStyle(
            name="H2",
            fontName="Helvetica-Bold",
            fontSize=16,
            textColor=TEXT_DARK,
            spaceAfter=8,
        )
    )
    styles.add(
        ParagraphStyle(
            name="H3",
            fontName="Helvetica-Bold",
            fontSize=14,
            textColor=TEXT_DARK,
            spaceAfter=6,
        )
    )
    styles.add(
        ParagraphStyle(
            name="Body",
            fontName="Helvetica",
            fontSize=11,
            leading=14,
            textColor=colors.HexColor("#374151"),
        )
    )
    styles.add(
        ParagraphStyle(
            name="Caption",
            fontName="Helvetica-Bold",
            fontSize=11,
            textColor=PRIMARY_COLOR,
            spaceAfter=6,
            alignment=1,
        )
    )
    return styles


def _section_spacer(height: float = 14) -> Spacer:
    return Spacer(1, height)


def _kpi_rows(metrics: Dict[str, Any]) -> list[list[str]]:
    revenue = metrics.get("revenue", {})
    user = metrics.get("user", {})
    subscription = metrics.get("subscription", {})
    course = metrics.get("course", {})
    transcription = metrics.get("transcription", {})

    premium_users = subscription.get("total_subscribers") or 0
    total_users = user.get("total_users") or 0
    free_users = max(total_users - premium_users, 0)

    return [
        ["Total revenue", _currency(revenue.get("total_revenue"))],
        ["Monthly recurring revenue", _currency(revenue.get("mrr"))],
        ["Average revenue per user", _currency(revenue.get("arpu"))],
        ["Total users", f"{total_users:,}"],
        ["Active users", f"{user.get('active_users', 0):,}"],
        ["Premium users", f"{premium_users:,}"],
        ["Free users", f"{free_users:,}"],
        ["Total courses", f"{course.get('total_courses', 0):,}"],
        ["Total modules", f"{course.get('total_modules', 0):,}"],
        ["Total lessons", f"{course.get('total_lessons', 0):,}"],
        ["Completed activities", f"{sum((course.get('activity_heatmap') or {}).values()):,}"],
        ["Transcription count", f"{transcription.get('total_uploads', 0):,}"],
    ]


def _build_kpi_table(metrics: Dict[str, Any], styles: StyleSheet1) -> Table:
    rows = [["Metric", "Value"]] + _kpi_rows(metrics)
    table = Table(rows, colWidths=[250, 250])
    table.hAlign = "CENTER"
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), LIGHT_BG),
                ("TEXTCOLOR", (0, 0), (-1, 0), PRIMARY_COLOR),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTSIZE", (0, 0), (-1, 0), 12),
                ("ALIGN", (0, 0), (-1, 0), "LEFT"),
                ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#eef2ff")]),
                ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
                ("FONTSIZE", (0, 1), (-1, -1), 11),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    return table


def _pie_chart(premium_users: int, free_users: int) -> Drawing:
    drawing = Drawing(440, 240)
    pie = Pie()
    pie.x = 140
    pie.y = 30
    pie.width = 160
    pie.height = 160
    data = [float(premium_users or 0), float(free_users or 0)]
    pie.data = data if any(data) else [1, 1]
    pie.labels = ["Premium", "Free"]
    pie.slices.strokeWidth = 0.5
    pie.slices[0].fillColor = PRIMARY_COLOR
    pie.slices[1].fillColor = ACCENT_GREY
    pie.slices[0].popout = 6
    pie.slices[1].popout = 0
    pie.sideLabels = True
    drawing.add(pie)
    drawing.hAlign = "CENTER"
    return drawing


def _bar_chart(months: list[str], values: list[float]) -> Drawing:
    drawing = Drawing(460, 260)
    chart = VerticalBarChart()
    chart.x = 50
    chart.y = 50
    chart.height = 170
    chart.width = 360
    chart.data = [values or [0.0]]
    chart.categoryAxis.categoryNames = months or ["-"]
    chart.barSpacing = 6
    chart.groupSpacing = 10
    chart.valueAxis.valueMin = 0
    chart.valueAxis.strokeWidth = 0.5
    chart.categoryAxis.strokeWidth = 0.5
    chart.valueAxis.labels.fontName = "Helvetica"
    chart.categoryAxis.labels.fontName = "Helvetica"
    chart.categoryAxis.labels.angle = 30
    chart.categoryAxis.labels.dy = -10
    chart.bars[0].fillColor = PRIMARY_COLOR
    chart.bars[0].strokeColor = colors.white
    chart.bars[0].strokeWidth = 0.2
    drawing.add(chart)
    drawing.hAlign = "CENTER"
    return drawing


def _line_chart(labels: list[str], values: list[float]) -> Drawing:
    drawing = Drawing(460, 260)
    chart = HorizontalLineChart()
    chart.x = 50
    chart.y = 50
    chart.height = 170
    chart.width = 360
    chart.data = [values or [0.0]]
    chart.categoryAxis.categoryNames = labels or ["-"]
    chart.categoryAxis.labels.fontName = "Helvetica"
    chart.categoryAxis.labels.angle = 30
    chart.categoryAxis.labels.dy = -8
    chart.valueAxis.labels.fontName = "Helvetica"
    chart.valueAxis.valueMin = 0
    chart.lines[0].strokeColor = PRIMARY_COLOR
    chart.lines[0].strokeWidth = 2
    chart.lines[0].symbol = None
    chart.joinedLines = True
    chart.gridFirst = True
    chart.valueAxis.visibleGrid = True
    chart.valueAxis.gridStrokeColor = BORDER_COLOR
    chart.valueAxis.gridStrokeWidth = 0.5
    drawing.add(chart)
    drawing.hAlign = "CENTER"
    return drawing


def _build_revenue_table(metrics: Dict[str, Any]) -> Table:
    monthly = metrics.get("revenue", {}).get("monthly_revenue", []) or []
    rows = [["Month", "Revenue", "Growth %"]]
    prev = None
    for entry in monthly:
        label = entry.get("label", "-")
        amount = float(entry.get("amount") or 0)
        growth = 0.0 if prev in (None, 0) else round(((amount - prev) / prev) * 100, 2)
        rows.append([label, _currency(amount), f"{growth:.2f}%"])
        prev = amount if amount is not None else prev
    if len(rows) == 1:
        rows.append(["-", "RM 0.00", "0.00%"])

    table = Table(rows, colWidths=[200, 140, 140])
    table.hAlign = "CENTER"
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), LIGHT_BG),
                ("TEXTCOLOR", (0, 0), (-1, 0), PRIMARY_COLOR),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#eef2ff")]),
                ("FONTSIZE", (0, 0), (-1, -1), 10),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    return table


def _build_user_table(metrics: Dict[str, Any]) -> Table:
    user = metrics.get("user", {})
    series = user.get("new_users_per_month", []) or []
    rows = [["Day", "Active users", "New signups"]]
    if series:
        for entry in series:
            rows.append(
                [entry.get("label", "-"), f"{user.get('active_users', 0):,}", f"{entry.get('count', 0):,}"]
            )
    else:
        rows.append(["-", f"{user.get('active_users', 0):,}", "0"])

    table = Table(rows, colWidths=[200, 140, 140])
    table.hAlign = "CENTER"
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), LIGHT_BG),
                ("TEXTCOLOR", (0, 0), (-1, 0), PRIMARY_COLOR),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#eef2ff")]),
                ("FONTSIZE", (0, 0), (-1, -1), 10),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    return table


def _build_course_table(metrics: Dict[str, Any]) -> Table:
    courses = metrics.get("course", {}).get("top_courses", []) or []
    rows = [["Course title", "Enrollments", "Completed lessons"]]
    for course in courses:
        rows.append(
            [
                course.get("title", course.get("id", "-")),
                f"{course.get('enrolled', 0):,}",
                f"{course.get('completed', 0):,}",
            ]
        )
    if len(rows) == 1:
        rows.append(["-", "0", "0"])

    table = Table(rows, colWidths=[240, 120, 120])
    table.hAlign = "CENTER"
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), LIGHT_BG),
                ("TEXTCOLOR", (0, 0), (-1, 0), PRIMARY_COLOR),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#eef2ff")]),
                ("FONTSIZE", (0, 0), (-1, -1), 10),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    return table


# ---------------------------
# PDF generator (ReportLab)
# ---------------------------
def build_pdf(metrics: Dict[str, Any], admin_email: str, logo_path: str) -> bytes:
    """Convert analytics data into a styled PDF using ReportLab."""

    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        rightMargin=40,
        leftMargin=40,
        topMargin=40,
        bottomMargin=50,
    )

    styles = _build_styles()
    story = []

    # Header
    header_items = []
    if Path(logo_path).exists():
        header_logo = Image(logo_path, width=160, kind="proportional")
        header_logo.hAlign = "CENTER"
        header_items.extend([header_logo, _section_spacer(10)])
    header_items.append(Paragraph("LipRead Analytics Report", styles["H1"]))
    generated_on = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
    header_items.append(
        Paragraph(
            f"Generated on {generated_on}<br/>Admin: {admin_email}",
            styles["Body"],
        )
    )
    header_items.append(_section_spacer(16))
    story.append(KeepTogether(header_items))

    # KPI summary
    story.append(Paragraph("Executive Summary", styles["H2"]))
    story.append(_section_spacer(8))
    story.append(_build_kpi_table(metrics, styles))
    story.append(_section_spacer(16))

    # Charts
    user_metrics = metrics.get("user", {})
    subscription_metrics = metrics.get("subscription", {})
    revenue_metrics = metrics.get("revenue", {})
    course_metrics = metrics.get("course", {})

    premium_users = subscription_metrics.get("total_subscribers") or 0
    total_users = user_metrics.get("total_users") or 0
    free_users = max(total_users - premium_users, 0)

    monthly_revenue = revenue_metrics.get("monthly_revenue", []) or []
    revenue_labels = [entry.get("label", "-") for entry in monthly_revenue]
    revenue_values = [float(entry.get("amount") or 0) for entry in monthly_revenue]

    activity_map = course_metrics.get("activity_heatmap", {}) or {}
    activity_labels = list(activity_map.keys())
    activity_values = [float(v) for v in activity_map.values()]
    if not activity_labels or not activity_values:
        activity_labels = revenue_labels or ["Week 1", "Week 2", "Week 3", "Week 4"]
        activity_values = revenue_values or [0, 0, 0, 0]

    story.append(Paragraph("Charts", styles["H2"]))
    story.append(_section_spacer(12))

    story.append(
        KeepTogether(
            [
                Paragraph("User Distribution", styles["H3"]),
                Paragraph("Premium vs Free", styles["Caption"]),
                _pie_chart(premium_users, free_users),
                _section_spacer(16),
            ]
        )
    )

    story.append(
        KeepTogether(
            [
                Paragraph("Revenue Trends", styles["H3"]),
                Paragraph("Monthly revenue", styles["Caption"]),
                _bar_chart(revenue_labels, revenue_values),
                _section_spacer(16),
            ]
        )
    )

    story.append(
        KeepTogether(
            [
                Paragraph("Engagement", styles["H3"]),
                Paragraph("Activity / transcription trend", styles["Caption"]),
                _line_chart(activity_labels, activity_values),
                _section_spacer(16),
            ]
        )
    )

    # Detailed tables
    story.append(Paragraph("Detailed Tables", styles["H2"]))
    story.append(_section_spacer(12))

    story.append(Paragraph("Revenue breakdown", styles["H3"]))
    story.append(_section_spacer(8))
    story.append(_build_revenue_table(metrics))
    story.append(_section_spacer(16))

    story.append(Paragraph("User analytics", styles["H3"]))
    story.append(_section_spacer(8))
    story.append(_build_user_table(metrics))
    story.append(_section_spacer(16))

    story.append(Paragraph("Course analytics", styles["H3"]))
    story.append(_section_spacer(8))
    story.append(_build_course_table(metrics))
    story.append(_section_spacer(16))

    doc.build(story, canvasmaker=NumberedCanvas)
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
