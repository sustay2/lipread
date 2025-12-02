"""Lightweight PDF report generation for admin reports."""
from __future__ import annotations

import uuid
from datetime import date
from pathlib import Path
from typing import Dict, List

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

BASE_DIR = Path(__file__).resolve().parents[1]
REPORT_DIR = BASE_DIR / "static" / "reports"
REPORT_DIR.mkdir(parents=True, exist_ok=True)


def generate_pdf_report(
    report_type: str,
    start_date: date,
    end_date: date,
    course: str,
    template_name: str,
    chart: Dict[str, List],
) -> str:
    filename = f"report-{uuid.uuid4().hex[:8]}.pdf"
    out_path = REPORT_DIR / filename

    # Build the PDF content
    fig, ax = plt.subplots(figsize=(8.27, 11.69))  # A4 portrait
    ax.axis("off")

    lines = [
        "LipRead Analytics Report",
        f"Type: {report_type}",
        f"Course filter: {course or 'All courses'}",
        f"Date range: {start_date.isoformat()} to {end_date.isoformat()}",
        f"Template: {template_name or 'Ad-hoc'}",
        "",
        "Daily Active Users & Completions",
    ]
    ax.text(0.02, 0.98, "\n".join(lines), va="top", fontsize=12)

    try:
        days = chart.get("labels", [])
        dau = chart.get("dau", [])
        completions = chart.get("completions", [])
        accuracy = chart.get("quiz_accuracy", [])

        inset = fig.add_axes([0.08, 0.35, 0.84, 0.5])
        inset.plot(days, dau, label="DAU", color="#0d6efd", linewidth=2)
        inset.bar(days, completions, label="Completions", alpha=0.3, color="#20c997")
        inset.set_xticklabels(days, rotation=45, ha="right", fontsize=7)
        inset.set_ylabel("Count")
        inset.legend(loc="upper left")

        ax2 = fig.add_axes([0.08, 0.2, 0.84, 0.12])
        ax2.plot(days, accuracy, color="#6f42c1", marker="o")
        ax2.set_ylabel("Quiz Accuracy %")
        ax2.set_xticklabels([])
        ax2.grid(True, axis="y", linestyle="--", alpha=0.6)
    except Exception:
        # Fallback safe text when plotting fails
        ax.text(0.02, 0.3, "Unable to render charts with provided data", fontsize=10, color="red")

    fig.tight_layout()
    fig.savefig(out_path, format="pdf")
    plt.close(fig)
    return filename
