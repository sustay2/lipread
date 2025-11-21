import os, time, requests

FIREBASE_API_KEY = None

def _api_key():
    global FIREBASE_API_KEY
    if FIREBASE_API_KEY: 
        return FIREBASE_API_KEY
    try:
        import streamlit as st
        FIREBASE_API_KEY = st.secrets["FIREBASE"]["api_key"]
    except Exception:
        FIREBASE_API_KEY = os.getenv("FIREBASE_API_KEY", "")
    return FIREBASE_API_KEY

def sign_in_email_password(email: str, password: str):
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={_api_key()}"
    r = requests.post(url, json={"email": email, "password": password, "returnSecureToken": True}, timeout=15)
    r.raise_for_status()
    data = r.json()

    data["expiresIn"] = int(data.get("expiresIn", "3600"))
    data["_expires_at"] = int(time.time()) + data["expiresIn"] - 30
    return data

def refresh_id_token(refresh_token: str):
    url = f"https://securetoken.googleapis.com/v1/token?key={_api_key()}"
    r = requests.post(url, data={"grant_type": "refresh_token", "refresh_token": refresh_token}, timeout=15)
    r.raise_for_status()
    j = r.json()

    return {
        "idToken": j["id_token"],
        "refreshToken": j.get("refresh_token", refresh_token),
        "localId": j["user_id"],
        "expiresIn": int(j.get("expires_in", "3600")),
        "_expires_at": int(time.time()) + int(j.get("expires_in", "3600")) - 30,
    }

def send_password_reset(email: str):
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key={_api_key()}"
    r = requests.post(url, json={"requestType": "PASSWORD_RESET", "email": email}, timeout=15)
    r.raise_for_status()
    return True

def update_profile(id_token: str, display_name: str | None = None, photo_url: str | None = None):
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:update?key={_api_key()}"
    payload = {"idToken": id_token, "returnSecureToken": True}
    if display_name is not None:
        payload["displayName"] = display_name
    if photo_url is not None:
        payload["photoUrl"] = photo_url
    r = requests.post(url, json=payload, timeout=15)
    r.raise_for_status()
    return r.json()

def change_password(id_token: str, new_password: str):
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:update?key={_api_key()}"
    r = requests.post(url, json={"idToken": id_token, "password": new_password, "returnSecureToken": True}, timeout=15)
    r.raise_for_status()
    j = r.json()

    out = {
        "idToken": j.get("idToken"),
        "refreshToken": j.get("refreshToken"),
        "localId": j.get("localId"),
        "expiresIn": int(j.get("expiresIn", "3600")),
    }
    out["_expires_at"] = int(time.time()) + out["expiresIn"] - 30
    return out
import os, time, requests

FIREBASE_API_KEY = None

def _api_key():
    global FIREBASE_API_KEY
    if FIREBASE_API_KEY: 
        return FIREBASE_API_KEY
    try:
        import streamlit as st
        FIREBASE_API_KEY = st.secrets["FIREBASE"]["api_key"]
    except Exception:
        FIREBASE_API_KEY = os.getenv("FIREBASE_API_KEY", "")
    return FIREBASE_API_KEY

def sign_in_email_password(email: str, password: str):
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={_api_key()}"
    r = requests.post(url, json={"email": email, "password": password, "returnSecureToken": True}, timeout=15)
    r.raise_for_status()
    data = r.json()

    data["expiresIn"] = int(data.get("expiresIn", "3600"))
    data["_expires_at"] = int(time.time()) + data["expiresIn"] - 30
    return data

def refresh_id_token(refresh_token: str):
    url = f"https://securetoken.googleapis.com/v1/token?key={_api_key()}"
    r = requests.post(url, data={"grant_type": "refresh_token", "refresh_token": refresh_token}, timeout=15)
    r.raise_for_status()
    j = r.json()

    return {
        "idToken": j["id_token"],
        "refreshToken": j.get("refresh_token", refresh_token),
        "localId": j["user_id"],
        "expiresIn": int(j.get("expires_in", "3600")),
        "_expires_at": int(time.time()) + int(j.get("expires_in", "3600")) - 30,
    }

def send_password_reset(email: str):
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key={_api_key()}"
    r = requests.post(url, json={"requestType": "PASSWORD_RESET", "email": email}, timeout=15)
    r.raise_for_status()
    return True

def update_profile(id_token: str, display_name: str | None = None, photo_url: str | None = None):
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:update?key={_api_key()}"
    payload = {"idToken": id_token, "returnSecureToken": True}
    if display_name is not None:
        payload["displayName"] = display_name
    if photo_url is not None:
        payload["photoUrl"] = photo_url
    r = requests.post(url, json=payload, timeout=15)
    r.raise_for_status()
    return r.json()

def change_password(id_token: str, new_password: str):
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:update?key={_api_key()}"
    r = requests.post(url, json={"idToken": id_token, "password": new_password, "returnSecureToken": True}, timeout=15)
    r.raise_for_status()
    j = r.json()

    out = {
        "idToken": j.get("idToken"),
        "refreshToken": j.get("refreshToken"),
        "localId": j.get("localId"),
        "expiresIn": int(j.get("expiresIn", "3600")),
    }
    out["_expires_at"] = int(time.time()) + out["expiresIn"] - 30
    return out