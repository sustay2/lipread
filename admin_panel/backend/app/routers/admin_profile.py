from __future__ import annotations

from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.deps.admin_session import require_admin_session
from app.services import admin_auth


BASE_DIR = Path(__file__).resolve().parents[1]
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

router = APIRouter(prefix="/profile", dependencies=[Depends(require_admin_session)])


def _resolve_admin_from_session(request: Request):
    session_admin = request.session.get("admin", {}) if request.session else {}
    admin = None
    admin_id = session_admin.get("id")
    if admin_id:
        admin = admin_auth.get_admin_by_id(admin_id)
    if not admin and session_admin.get("email"):
        admin = admin_auth.get_admin_by_email(session_admin.get("email"))
    return admin


@router.get("", response_class=HTMLResponse)
async def profile_detail(request: Request, message: Optional[str] = None):
    admin = _resolve_admin_from_session(request)
    if not admin:
        return RedirectResponse(url="/logout", status_code=status.HTTP_303_SEE_OTHER)

    return templates.TemplateResponse(
        "admin_profile.html",
        {
            "request": request,
            "admin": admin,
            "message": message,
        },
    )


@router.get("/edit", response_class=HTMLResponse)
async def profile_edit(request: Request, message: Optional[str] = None, error: Optional[str] = None):
    admin = _resolve_admin_from_session(request)
    if not admin:
        return RedirectResponse(url="/logout", status_code=status.HTTP_303_SEE_OTHER)

    return templates.TemplateResponse(
        "admin_profile_edit.html",
        {
            "request": request,
            "admin": admin,
            "message": message,
            "error": error,
        },
    )


@router.post("/update")
async def update_profile(
    request: Request,
    display_name: str = Form(""),
    photo_url: Optional[str] = Form(None),
):
    admin = _resolve_admin_from_session(request)
    if not admin:
        return RedirectResponse(url="/logout", status_code=status.HTTP_303_SEE_OTHER)

    updated = admin_auth.update_admin_profile(admin.get("id"), display_name, photo_url)
    if updated:
        request.session["admin"]["name"] = updated.get("name") or updated.get("displayName") or updated.get("email")
    return RedirectResponse(url="/profile?message=profile-updated", status_code=status.HTTP_303_SEE_OTHER)


@router.post("/password")
async def change_password(
    request: Request,
    current_password: str = Form(...),
    new_password: str = Form(...),
    confirm_password: str = Form(...),
):
    admin = _resolve_admin_from_session(request)
    if not admin:
        return RedirectResponse(url="/logout", status_code=status.HTTP_303_SEE_OTHER)

    try:
        for value in (current_password, new_password, confirm_password):
            if len(value.encode("utf-8")) > admin_auth.MAX_PASSWORD_BYTES:
                raise ValueError
    except Exception:
        return templates.TemplateResponse(
            "admin_profile_edit.html",
            {
                "request": request,
                "admin": admin,
                "error": "Password must not exceed 72 characters.",
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    if new_password != confirm_password:
        return templates.TemplateResponse(
            "admin_profile_edit.html",
            {
                "request": request,
                "admin": admin,
                "error": "New password and confirmation do not match.",
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    if len(new_password) < 8:
        return templates.TemplateResponse(
            "admin_profile_edit.html",
            {
                "request": request,
                "admin": admin,
                "error": "Password must be at least 8 characters long.",
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    stored_hash = admin.get("passwordHash")
    if not stored_hash or not admin_auth.verify_password(current_password, stored_hash):
        return templates.TemplateResponse(
            "admin_profile_edit.html",
            {
                "request": request,
                "admin": admin,
                "error": "Current password is incorrect.",
            },
            status_code=status.HTTP_401_UNAUTHORIZED,
        )

    admin_auth.update_admin_password(admin.get("id"), new_password)

    return RedirectResponse(url="/profile?message=password-updated", status_code=status.HTTP_303_SEE_OTHER)
