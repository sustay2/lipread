from typing import Any, Dict, Optional


class FirebaseAuthService:
    """Placeholder Firebase auth integration for FastAPI templates."""

    def __init__(self, id_token: Optional[str] = None):
        self.id_token = id_token

    def current_user(self) -> Dict[str, Any]:
        if not self.id_token:
            return {}
        return {"email": "admin@example.com", "uid": "demo-admin", "roles": ["admin"]}

    def refresh_token(self) -> Optional[str]:
        return self.id_token
