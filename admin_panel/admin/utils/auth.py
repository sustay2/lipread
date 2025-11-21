import os, time, secrets, requests, streamlit as st
from typing import List, Optional
from .firebase_rest import (
    sign_in_email_password,
    refresh_id_token,
    send_password_reset,
    update_profile,
    change_password,
)

API_BASE = os.getenv("API_BASE", "http://api:8000")

_get_cookie = getattr(st, "experimental_get_cookie", None)
_set_cookie = getattr(st, "experimental_set_cookie", None)
_del_cookie = getattr(st, "experimental_delete_cookie", None)

def _cookie_get(name: str) -> Optional[str]:
    if _get_cookie:
        try:
            return _get_cookie(name)
        except Exception:
            return None
    return st.session_state.get(f"__cookie_{name}")

def _cookie_set(name: str, value: str, days: int = 7):
    if _set_cookie:
        _set_cookie(name, value, max_age_days=days, secure=True, httponly=True, samesite="lax")
    else:
        st.session_state[f"__cookie_{name}"] = value

def _cookie_del(name: str):
    if _del_cookie:
        _del_cookie(name)
    else:
        st.session_state.pop(f"__cookie_{name}", None)

@st.cache_resource
def _session_store() -> dict:
    return {}

def _now() -> int:
    return int(time.time())

_SID_COOKIE = "lipread_sid"

def _get_sid() -> Optional[str]:
    sid = None
    if hasattr(st, "query_params"):
        sid = st.query_params.get("sid")
    if sid:
        return sid

    return _cookie_get(_SID_COOKIE)

def _set_sid(sid: str):
    _cookie_set(_SID_COOKIE, sid, days=14)

    if hasattr(st, "query_params"):
        qp = dict(st.query_params)
        qp["sid"] = sid
        st.query_params.clear()
        st.query_params.update(qp)

def _clear_sid():
    _cookie_del(_SID_COOKIE)
    if hasattr(st, "query_params"):
        qp = dict(st.query_params)
        if "sid" in qp:
            qp.pop("sid")
            st.query_params.clear()
            if qp:
                st.query_params.update(qp)

def _save_to_store(sid: str, data: dict):
    store = _session_store()
    store[sid] = data

def _load_from_store(sid: str) -> Optional[dict]:
    return _session_store().get(sid)

def _delete_from_store(sid: str):
    store = _session_store()
    if sid in store:
        del store[sid]

def _fetch_roles(id_token: str) -> List[str]:
    r = requests.get(
        f"{API_BASE}/admin/users/me/roles",
        headers={"Authorization": f"Bearer {id_token}"},
        timeout=10,
    )
    r.raise_for_status()
    roles = r.json().get("roles", [])
    return [str(x).lower() for x in roles]

def _hydrate_session(sid: str, data: dict):
    st.session_state["sid"] = sid
    st.session_state["id_token"] = data["idToken"]
    st.session_state["refresh_token"] = data.get("refreshToken")
    st.session_state["token_exp"] = int(data.get("_expires_at", _now() + 3600))
    st.session_state["user"] = {
        "uid": data.get("localId") or data.get("userId"),
        "email": data.get("email"),
    }
    st.session_state["claims"] = {"uid": st.session_state["user"]["uid"]}

def _persist_session(email: str, login_resp: dict):
    login_resp["email"] = email
    login_resp["_expires_at"] = _now() + int(login_resp.get("expiresIn", 3600)) - 30
    sid = secrets.token_urlsafe(16)
    _save_to_store(sid, login_resp)
    _set_sid(sid)
    _hydrate_session(sid, login_resp)

def sign_out():
    sid = st.session_state.get("sid") or _get_sid()
    if sid:
        _delete_from_store(sid)
    _clear_sid()
    for k in ["sid","user","id_token","refresh_token","token_exp","claims","roles",
              "profile_display_name","profile_photo_url"]:
        st.session_state.pop(k, None)

def ensure_login_ui():
    if not st.session_state.get("user"):
        sid = _get_sid()
        if sid:
            data = _load_from_store(sid)
            if data:
                # refresh if near expiry
                if _now() >= int(data.get("_expires_at", 0)) - 15:
                    try:
                        freshed = refresh_id_token(data["refreshToken"])
                        freshed["email"] = data.get("email")
                        freshed["_expires_at"] = _now() + int(freshed.get("expiresIn", 3600)) - 30
                        _save_to_store(sid, freshed)
                        data = freshed
                    except Exception:
                        sign_out()
                        return _render_login()
                _hydrate_session(sid, data)

    if not st.session_state.get("user"):
        return _render_login()

    if not st.session_state.get("roles"):
        try:
            roles = _fetch_roles(st.session_state["id_token"])
            if not roles:
                st.error("No roles assigned. Contact an administrator.")
                sign_out()
                return _render_login()
            st.session_state["roles"] = roles
        except Exception as e:
            st.warning(f"Role fetch failed: {e}")
    return st.session_state["user"]

def current_roles():
    return st.session_state.get("roles", [])

def require_role_ui(*required: str) -> bool:
    roles = set(current_roles())
    needed = {r.lower() for r in required}
    ok = bool(roles & needed)
    if not ok:
        st.error("You don't have permission to view this section.")
    return ok

def _render_login():
    st.title("🔐 Login")
    with st.form("login_form"):
        email = st.text_input("Email", key="login_email")
        password = st.text_input("Password", type="password", key="login_password")

        left, spacer, right = st.columns([1, 6, 1])
        with left:
            submitted = st.form_submit_button("Sign In")
        with right:
            forgot = st.form_submit_button("Forgot password?", type="secondary")

    if forgot:
        if not st.session_state.get("login_email"):
            st.warning("Enter your email above first, then click the link.")
        else:
            try:
                send_password_reset(st.session_state["login_email"])
                st.success("Password reset email sent.")
            except Exception as e:
                st.error(f"Failed to send reset email: {e}")

    if submitted and email and password:
        try:
            with st.spinner("Signing in..."):
                data = sign_in_email_password(email, password)
                _persist_session(email, data)
                roles = _fetch_roles(st.session_state["id_token"])
                if not roles:
                    st.error("No roles assigned. Contact an administrator.")
                    sign_out()
                    st.stop()
                st.session_state["roles"] = roles
            st.success("Login successful")
            st.rerun()
        except Exception as e:
            st.error(str(e))
    st.stop()

def render_sidebar_profile():
    user = st.session_state.get("user") or {}
    email = user.get("email", "")
    roles = ", ".join(st.session_state.get("roles", [])) or "—"

    st.sidebar.markdown("### 👤 Profile")
    avatar = st.session_state.get("profile_photo_url") or ""
    if avatar:
        st.sidebar.image(avatar, width=64)
    st.sidebar.write(f"**{email}**")
    st.sidebar.caption(f"Roles: {roles}")

    with st.sidebar.expander("Edit", expanded=False):
        with st.form("sb_profile_edit"):
            disp = st.text_input("Display name", value=st.session_state.get("profile_display_name", ""))
            photo = st.text_input("Photo URL", value=avatar)
            save = st.form_submit_button("Save")
        if save:
            try:
                resp = update_profile(st.session_state["id_token"], display_name=disp or None, photo_url=photo or None)
                st.session_state["profile_display_name"] = resp.get("displayName", disp)
                st.session_state["profile_photo_url"] = resp.get("photoUrl", photo)
                st.success("Profile updated.")
            except Exception as e:
                st.error(f"Update failed: {e}")

        with st.form("sb_profile_pw"):
            new_pw = st.text_input("New password", type="password")
            new_pw2 = st.text_input("Confirm new password", type="password")
            change = st.form_submit_button("Change password")
        if change:
            if not new_pw or new_pw != new_pw2:
                st.error("Passwords do not match.")
            else:
                try:
                    j = change_password(st.session_state["id_token"], new_pw)
                    sid = st.session_state.get("sid") or secrets.token_urlsafe(8)
                    j["email"] = email
                    j["_expires_at"] = _now() + int(j.get("expiresIn", 3600)) - 30
                    _save_to_store(sid, j)
                    _set_sid(sid)
                    _hydrate_session(sid, j)
                    st.success("Password changed.")
                except Exception as e:
                    st.error(f"Change failed: {e}")

    if st.sidebar.button("Sign out"):
        sign_out()
        st.success("Signed out.")
        st.rerun()