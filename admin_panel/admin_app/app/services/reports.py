from datetime import datetime
from typing import Dict, List


class ReportService:
    def __init__(self):
        self.available_reports = [
            "user_progress",
            "course_completion",
            "quiz_scores",
            "revenue",
            "engagement",
        ]

    def generate_report(self, report_type: str, start_date: datetime, end_date: datetime, filters: Dict | None = None) -> Dict:
        if report_type not in self.available_reports:
            raise ValueError("Unsupported report type")
        return {
            "report_type": report_type,
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "filters": filters or {},
            "status": "ready",
            "download_url": f"/reports/{report_type}.pdf",
        }

    def list_templates(self) -> List[Dict]:
        return [
            {"name": "Weekly Progress", "type": "user_progress", "range": "7d"},
            {"name": "Monthly Revenue", "type": "revenue", "range": "30d"},
        ]
