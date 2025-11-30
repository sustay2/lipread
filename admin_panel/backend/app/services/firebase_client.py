"""Centralized Firebase initialization using provided service account file."""
from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict

import firebase_admin
from firebase_admin import credentials, firestore

# The provided service account is stored in the project root under admin_panel/
SERVICE_ACCOUNT_PATH = Path(__file__).resolve().parents[3] / "lipreadapp-441dd04e8b92.json"


@lru_cache(maxsize=1)
def _load_service_account_payload() -> Dict[str, Any]:
    if SERVICE_ACCOUNT_PATH.exists():
        return json.loads(SERVICE_ACCOUNT_PATH.read_text())

    # Fallback to environment variables if the JSON file is not present.
    project_id = os.getenv("FIREBASE_PROJECT_ID")
    client_email = os.getenv("FIREBASE_CLIENT_EMAIL")
    private_key = (os.getenv("FIREBASE_PRIVATE_KEY") or "").replace("\\n", "\n")

    if not (project_id and client_email and private_key):
        raise RuntimeError(
            "Firebase credentials not found. Ensure the provided service account file exists "
            "or FIREBASE_* environment variables are set."
        )

    return {
        "type": "service_account",
        "project_id": project_id,
        "client_email": client_email,
        "private_key": private_key,
        "token_uri": "https://oauth2.googleapis.com/token",
    }


def get_firebase_app() -> firebase_admin.App:
    if firebase_admin._apps:
        return firebase_admin.get_app()

    payload = _load_service_account_payload()
    cred = credentials.Certificate(payload)
    return firebase_admin.initialize_app(cred)


def get_firestore_client() -> firestore.Client:
    app = get_firebase_app()
    return firestore.client(app)
