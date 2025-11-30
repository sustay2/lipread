from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.services import admin_auth


BASE_DIR = Path(__file__).resolve().parents[1]
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

router = APIRouter()


@router.get("/login", response_class=HTMLResponse)
async def login_form(request: Request):
    if request.session.get("admin"):
        return RedirectResponse(url="/", status_code=status.HTTP_303_SEE_OTHER)
    return templates.TemplateResponse("login.html", {"request": request, "error": None})


@router.post("/login")
async def login(request: Request, email: str = Form(...), password: str = Form(...)):
    admin = admin_auth.verify_admin_credentials(email, password)
    if not admin:
        return templates.TemplateResponse(
            "login.html",
            {
                "request": request,
                "error": "Invalid email or password",
                "email": email,
            },
            status_code=status.HTTP_401_UNAUTHORIZED,
        )

    request.session["admin"] = {
        "id": admin.get("id"),
        "email": admin.get("email"),
        "name": admin.get("name")
        or admin.get("displayName")
        or admin.get("fullName")
        or admin.get("email"),
    }

    return RedirectResponse(url="/", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/logout")
async def logout(request: Request):
    request.session.clear()
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/forgot-password", response_class=HTMLResponse)
async def forgot_password_form(request: Request):
    if request.session.get("admin"):
        return RedirectResponse(url="/", status_code=status.HTTP_303_SEE_OTHER)
    return templates.TemplateResponse(
        "forgot_password.html", {"request": request, "error": None, "message": None}
    )


@router.post("/forgot-password")
async def forgot_password(request: Request, email: str = Form(...)):
    reset_token = admin_auth.create_password_reset(email)
    if reset_token:
        reset_url = str(request.url_for("reset_password_form")) + f"?token={reset_token}"
        admin_auth.send_password_reset_email(email, reset_url)

    return templates.TemplateResponse(
        "forgot_password.html",
        {
            "request": request,
            "message": "If the account exists, a reset link has been sent to the email provided.",
            "error": None,
            "email": email,
        },
    )


@router.get("/reset-password", response_class=HTMLResponse, name="reset_password_form")
async def reset_password_form(request: Request, token: str = ""):
    admin_doc = admin_auth.verify_reset_token(token) if token else None
    if not admin_doc:
        return templates.TemplateResponse(
            "reset_password.html",
            {
                "request": request,
                "error": "Invalid or expired reset link. Please request a new one.",
                "token": token,
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    return templates.TemplateResponse(
        "reset_password.html",
        {
            "request": request,
            "admin": admin_doc,
            "token": token,
            "error": None,
            "message": None,
        },
    )


@router.post("/reset-password")
async def reset_password(
    request: Request,
    token: str = Form(...),
    new_password: str = Form(...),
    confirm_password: str = Form(...),
):
    admin_doc = admin_auth.verify_reset_token(token)
    if not admin_doc:
        return templates.TemplateResponse(
            "reset_password.html",
            {
                "request": request,
                "error": "Invalid or expired reset link. Please request a new one.",
                "token": token,
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    if new_password != confirm_password:
        return templates.TemplateResponse(
            "reset_password.html",
            {
                "request": request,
                "error": "New password and confirmation must match.",
                "token": token,
                "admin": admin_doc,
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    if len(new_password) < 8:
        return templates.TemplateResponse(
            "reset_password.html",
            {
                "request": request,
                "error": "Password must be at least 8 characters long.",
                "token": token,
                "admin": admin_doc,
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    if not admin_auth.consume_reset_token(token, new_password):
        return templates.TemplateResponse(
            "reset_password.html",
            {
                "request": request,
                "error": "Unable to reset password. Please request a new link.",
                "token": token,
                "admin": admin_doc,
            },
            status_code=status.HTTP_400_BAD_REQUEST,
        )

    return templates.TemplateResponse(
        "reset_password.html",
        {
            "request": request,
            "message": "Password updated successfully. You can now log in with your new password.",
            "token": None,
            "admin": admin_doc,
        },
    )
