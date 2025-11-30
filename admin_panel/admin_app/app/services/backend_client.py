from typing import Any, Dict, List, Optional
import requests

from app.config import get_settings


class BackendClient:
    """Lightweight client for the existing FastAPI admin API."""

    def __init__(self, id_token: Optional[str] = None):
        settings = get_settings()
        self.base_url = settings.api_base_url.rstrip("/")
        self.id_token = id_token

    def _headers(self) -> Dict[str, str]:
        headers = {"Accept": "application/json"}
        if self.id_token:
            headers["Authorization"] = f"Bearer {self.id_token}"
        return headers

    def get_users(self, query: str | None = None, role: str | None = None) -> List[Dict[str, Any]]:
        params = {}
        if query:
            params["q"] = query
        if role:
            params["role"] = role
        resp = requests.get(f"{self.base_url}/admin/users", headers=self._headers(), params=params, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        if isinstance(data, dict) and "items" in data:
            return data["items"]
        if isinstance(data, list):
            return data
        return []

    def get_user(self, user_id: str) -> Dict[str, Any]:
        resp = requests.get(f"{self.base_url}/admin/users/{user_id}", headers=self._headers(), timeout=30)
        resp.raise_for_status()
        return resp.json()

    def patch_user(self, user_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        resp = requests.patch(
            f"{self.base_url}/admin/users/{user_id}", headers=self._headers(), json=payload, timeout=30
        )
        resp.raise_for_status()
        return resp.json()

    def reset_password(self, email: str) -> Dict[str, Any]:
        resp = requests.post(
            f"{self.base_url}/admin/users/{email}/reset-password", headers=self._headers(), timeout=30
        )
        resp.raise_for_status()
        return resp.json()

    def get_courses(self) -> List[Dict[str, Any]]:
        resp = requests.get(f"{self.base_url}/admin/courses", headers=self._headers(), timeout=30)
        resp.raise_for_status()
        data = resp.json()
        if isinstance(data, dict) and "items" in data:
            return data["items"]
        if isinstance(data, list):
            return data
        return []

    def get_course(self, course_id: str) -> Dict[str, Any]:
        resp = requests.get(f"{self.base_url}/admin/courses/{course_id}", headers=self._headers(), timeout=30)
        resp.raise_for_status()
        return resp.json()

    def upsert_course(self, course_id: Optional[str], payload: Dict[str, Any]) -> Dict[str, Any]:
        if course_id:
            resp = requests.patch(
                f"{self.base_url}/admin/courses/{course_id}", headers=self._headers(), json=payload, timeout=30
            )
        else:
            resp = requests.post(f"{self.base_url}/admin/courses", headers=self._headers(), json=payload, timeout=30)
        resp.raise_for_status()
        return resp.json()

    def get_modules(self, course_id: str) -> List[Dict[str, Any]]:
        resp = requests.get(
            f"{self.base_url}/admin/modules", headers=self._headers(), params={"courseId": course_id}, timeout=30
        )
        resp.raise_for_status()
        data = resp.json()
        if isinstance(data, dict) and "items" in data:
            return data["items"]
        if isinstance(data, list):
            return data
        return []

    def get_lessons(self, module_id: str) -> List[Dict[str, Any]]:
        resp = requests.get(
            f"{self.base_url}/admin/lessons", headers=self._headers(), params={"moduleId": module_id}, timeout=30
        )
        resp.raise_for_status()
        data = resp.json()
        if isinstance(data, dict) and "items" in data:
            return data["items"]
        if isinstance(data, list):
            return data
        return []

    def get_activities(self, lesson_id: str) -> List[Dict[str, Any]]:
        resp = requests.get(
            f"{self.base_url}/admin/activities", headers=self._headers(), params={"lessonId": lesson_id}, timeout=30
        )
        resp.raise_for_status()
        data = resp.json()
        if isinstance(data, dict) and "items" in data:
            return data["items"]
        if isinstance(data, list):
            return data
        return []

    def fetch_analytics(self, params: Dict[str, Any] | None = None) -> Dict[str, Any]:
        resp = requests.get(
            f"{self.base_url}/admin/analytics", headers=self._headers(), params=params or {}, timeout=30
        )
        resp.raise_for_status()
        return resp.json()

    def fetch_attempts(self, params: Dict[str, Any] | None = None) -> Dict[str, Any]:
        resp = requests.get(
            f"{self.base_url}/admin/attempts", headers=self._headers(), params=params or {}, timeout=30
        )
        resp.raise_for_status()
        return resp.json()
