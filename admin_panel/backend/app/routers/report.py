from __future__ import annotations

import base64
import io
from datetime import datetime
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from fastapi import APIRouter, Depends, Form, Query, Request
from fastapi.responses import HTMLResponse, Response
from weasyprint import HTML

from app.deps.admin_session import require_admin_session
from app.services import analytics_report_service
from fastapi.templating import Jinja2Templates

router = APIRouter(dependencies=[Depends(require_admin_session)])

BASE_DIR = Path(__file__).resolve().parents[1]
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

# -------------------------------------------------------
# Reuse original helpers (_currency, _parse_range)
# -------------------------------------------------------
def _currency(value):
    try:
        return f"RM {float(value or 0):,.2f}"
    except Exception:
        return "RM 0.00"

def _parse_range(start, end):
    from datetime import datetime, date
    s = None
    e = None
    try:
        s = datetime.fromisoformat(start).date() if start else None
    except:
        pass
    try:
        e = datetime.fromisoformat(end).date() if end else None
    except:
        pass
    return s, e

# -------------------------------------------------------
# Chart helper: convert figure → base64 PNG
# -------------------------------------------------------
def fig_to_base64(fig):
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=160, bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    return "data:image/png;base64," + base64.b64encode(buf.read()).decode()


# -------------------------------------------------------
# Chart styling (Option B)
# -------------------------------------------------------
def new_figure():
    plt.style.use("default")
    fig, ax = plt.subplots(figsize=(5.2, 2.2), dpi=110)

    ax.set_facecolor("#ffffff")
    fig.patch.set_facecolor("#ffffff")

    ax.grid(True, color="#e5e7eb", linewidth=0.65, alpha=0.75)

    for spine in ["top", "right"]:
        ax.spines[spine].set_visible(False)

    return fig, ax


def smooth_line(x, y, color="#0d6efd"):
    from scipy.ndimage import gaussian_filter1d
    y_smooth = gaussian_filter1d(y, sigma=1)

    plt.plot(x, y_smooth, color=color, linewidth=2.4)
    plt.scatter(x, y_smooth, color=color, s=12, zorder=4)


def rounded_bars(ax, x, values, color="#0d6efd"):
    for i, val in enumerate(values):
        ax.bar(
            x[i], val, width=0.55, color=color,
            alpha=0.85, edgecolor="none"
        )


# -------------------------------------------------------
# Generate charts using existing metrics
# -------------------------------------------------------
def generate_charts(metrics):
    charts = {}

    # ---------- 1. User Growth ----------
    new_users_list = metrics["user"].get("new_users_per_month", [])
    months = [row["label"] for row in new_users_list]
    counts = [row["count"] for row in new_users_list]

    if months:
        fig, ax = new_figure()
        x = np.arange(len(months))
        smooth_line(x, counts, color="#0d6efd")
        ax.set_xticks(x)
        ax.set_xticklabels(months, rotation=25, fontsize=8)
        charts["user_growth"] = fig_to_base64(fig)
    else:
        charts["user_growth"] = None

    # ---------- 2. New Users (bar) ----------
    if months:
        fig, ax = new_figure()
        x = np.arange(len(months))
        rounded_bars(ax, x, counts, color="#3b82f6")
        ax.set_xticks(x)
        ax.set_xticklabels(months, rotation=25, fontsize=8)
        charts["new_users"] = fig_to_base64(fig)
    else:
        charts["new_users"] = None

    # ---------- 3. XP distribution ----------
    xp_list = metrics["user"].get("xp_distribution", [])
    xp_labels = [row["label"] for row in xp_list]
    xp_counts = [row["count"] for row in xp_list]

    if xp_labels:
        fig, ax = new_figure()
        x = np.arange(len(xp_labels))
        rounded_bars(ax, x, xp_counts, color="#10b981")
        ax.set_xticks(x)
        ax.set_xticklabels(xp_labels, rotation=25, fontsize=8)
        charts["xp_distribution"] = fig_to_base64(fig)
    else:
        charts["xp_distribution"] = None

    # ---------- 4. Activity Heatmap ----------
    heatmap = metrics["course"].get("activity_heatmap", {})
    ah_labels = list(heatmap.keys())
    ah_counts = list(heatmap.values())

    if ah_labels:
        fig, ax = new_figure()
        x = np.arange(len(ah_labels))
        rounded_bars(ax, x, ah_counts, color="#f59e0b")
        ax.set_xticks(x)
        ax.set_xticklabels(ah_labels, rotation=25, fontsize=8)
        charts["activity_heatmap"] = fig_to_base64(fig)
    else:
        charts["activity_heatmap"] = None

    # ---------- 5. Subscription Active By Plan ----------
    plans = metrics["subscription"].get("active_by_plan", [])
    plan_labels = [row["plan"] for row in plans]
    plan_counts = [row["count"] for row in plans]

    if plan_labels:
        fig, ax = new_figure()
        x = np.arange(len(plan_labels))
        rounded_bars(ax, x, plan_counts, color="#6366f1")
        ax.set_xticks(x)
        ax.set_xticklabels(plan_labels, rotation=15, fontsize=8)
        charts["plans"] = fig_to_base64(fig)
    else:
        charts["plans"] = None

    # ---------- 6. Subscription Growth ----------
    subs_list = metrics["subscription"].get("monthly_new_subscriptions", [])
    sub_months = [row["label"] for row in subs_list]
    sub_counts = [row["count"] for row in subs_list]

    if sub_months:
        fig, ax = new_figure()
        x = np.arange(len(sub_months))
        smooth_line(x, sub_counts, color="#8b5cf6")
        ax.set_xticks(x)
        ax.set_xticklabels(sub_months, rotation=25, fontsize=8)
        charts["subscriptions"] = fig_to_base64(fig)
    else:
        charts["subscriptions"] = None

    # ---------- 7. Revenue ----------
    revenue_list = metrics["revenue"].get("monthly_revenue", [])
    rev_months = [row["label"] for row in revenue_list]
    rev_amounts = [row["amount"] for row in revenue_list]

    if rev_months:
        fig, ax = new_figure()
        x = np.arange(len(rev_months))
        smooth_line(x, rev_amounts, color="#ef4444")
        ax.set_xticks(x)
        ax.set_xticklabels(rev_months, rotation=25, fontsize=8)
        charts["revenue"] = fig_to_base64(fig)
    else:
        charts["revenue"] = None

    return charts


# -------------------------------------------------------
# EXISTING REPORT INDEX ROUTE (unchanged)
# -------------------------------------------------------
@router.get("/reports", response_class=HTMLResponse)
async def reports_index(
    request: Request,
    start_date: str | None = Query(None),
    end_date: str | None = Query(None),
):
    start, end = _parse_range(start_date, end_date)
    metrics = analytics_report_service.aggregate_all((start, end))

    return templates.TemplateResponse(
        "reports/index.html",
        {
            "request": request,
            "metrics": metrics,
            "start_date": start_date,
            "end_date": end_date,
            "format_currency": _currency,
        },
    )


# -------------------------------------------------------
# EXPORT PDF USING WEASYPRINT + CHARTS
# -------------------------------------------------------
@router.post("/reports/export")
async def export_report(
    request: Request,
    start_date: str | None = Form(None),
    end_date: str | None = Form(None),
):
    start, end = _parse_range(start_date, end_date)
    metrics = analytics_report_service.aggregate_all((start, end))

    charts = generate_charts(metrics)

    html = templates.get_template("reports/report_pdf.html").render(
        metrics=metrics,
        charts=charts,
        start_date=start_date,
        end_date=end_date,
        generated_label=datetime.utcnow().strftime("%d %b %Y, %H:%M UTC"),
        admin_email=request.session.get("admin", {}).get("email", "admin"),
        logo_url="../static/img/logo.png",
        format_currency=_currency,
    )

    pdf_bytes = HTML(string=html).write_pdf()

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": "attachment; filename=lipread_report.pdf"},
    )