import os
import requests
import streamlit as st

_API_FROM_ENV = os.getenv("API_BASE_URL")
_API_FROM_SECRETS = None
try:
    _API_FROM_SECRETS = st.secrets.get("API_BASE_URL", None)
except Exception:
    _API_FROM_SECRETS = None

API_BASE_URL = (_API_FROM_ENV or _API_FROM_SECRETS or "http://api:8000").rstrip("/")

def _auth_header():
    tok = st.session_state.get("id_token")
    return {"Authorization": f"Bearer {tok}"} if tok else {}

def api(
    method: str,
    path: str,
    *,
    json=None,
    params=None,
    files=None,
    data=None,
    headers=None,
    timeout: int = 60,
):
    url = f"{API_BASE_URL}{path}"
    hdrs = {"Accept": "application/json"}
    hdrs.update(_auth_header())
    if headers:
        hdrs.update(headers)

    resp = requests.request(
        method.upper(),
        url,
        json=json,
        params=params,
        files=files,
        data=data,
        headers=hdrs,
        timeout=timeout,
    )

    if resp.status_code >= 400:
        try:
            detail = resp.json()
        except Exception:
            detail = resp.text
        raise RuntimeError(f"{resp.status_code} Error: {detail}")

    ctype = resp.headers.get("content-type", "")
    if "application/json" in ctype:
        return resp.json()
    return resp.text