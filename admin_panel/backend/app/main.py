import os
import pathlib
from fastapi import FastAPI, HTTPException, Request, status, Response
from fastapi.responses import StreamingResponse, FileResponse
from starlette.responses import PlainTextResponse
from typing import Optional
from fastapi.exception_handlers import http_exception_handler
from starlette.staticfiles import StaticFiles
from starlette.middleware.sessions import SessionMiddleware
from fastapi.templating import Jinja2Templates

import re
from app.routers import (
    health,
    users,
    videos,
    visemes,
    courses,
    modules,
    lessons,
    activities,
    question_banks,
    inference_jobs,
    import_export,
    tasks,
    ui,
    report,
    admin_auth,
    admin_profile,
    public_api,
    billing,
    stripe_webhooks,
)
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="LipReading Admin API")

BASE_DIR = pathlib.Path(__file__).resolve().parent
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in ALLOWED_ORIGINS.split(",")],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

SESSION_SECRET = os.getenv("ADMIN_SESSION_SECRET", "change-me-please")
SESSION_COOKIE = os.getenv("ADMIN_SESSION_COOKIE", "lipread_admin_session")
SESSION_MAX_AGE = int(os.getenv("ADMIN_SESSION_MAX_AGE", str(60 * 60 * 8)))
SESSION_HTTPS_ONLY = os.getenv("ADMIN_SESSION_HTTPS_ONLY", "false").lower() == "true"

app.add_middleware(
    SessionMiddleware,
    secret_key=SESSION_SECRET,
    session_cookie=SESSION_COOKIE,
    max_age=SESSION_MAX_AGE,
    same_site="lax",
    https_only=SESSION_HTTPS_ONLY,
)

# Serve local media read-only
DEFAULT_MEDIA_ROOT = "C:/lipread_media"
MEDIA_ROOT = os.getenv("MEDIA_ROOT", DEFAULT_MEDIA_ROOT)
STATIC_ROOT = pathlib.Path(__file__).resolve().parent / "static"

import mimetypes

@app.get("/media/{full_path:path}")
async def media_handler(full_path: str, range: Optional[str] = None):
    file_path = pathlib.Path(MEDIA_ROOT) / full_path

    if not file_path.exists():
        return PlainTextResponse("File not found", status_code=404)

    content_type = mimetypes.guess_type(str(file_path))[0] or "application/octet-stream"
    file_size = file_path.stat().st_size

    is_video = content_type.startswith("video/")

    # -------------------------
    # IMAGE OR NO RANGE HEADER
    # -------------------------
    if not is_video:
        return FileResponse(
            file_path,
            media_type=content_type,
            filename=os.path.basename(str(file_path)),
        )

    if range is None:
        return FileResponse(
            file_path,
            media_type=content_type,
            filename=os.path.basename(str(file_path)),
        )

    # -------------------------
    # VIDEO RANGE REQUEST
    # -------------------------
    import re
    match = re.match(r"bytes=(\d+)-(\d*)", range)
    if not match:
        return PlainTextResponse("Invalid range header", status_code=416)

    start = int(match.group(1))
    end = match.group(2)
    end = int(end) if end else file_size - 1

    if start >= file_size:
        return PlainTextResponse("Range out of bounds", status_code=416)

    chunk_size = (end - start) + 1

    def iter_file():
        with open(file_path, "rb") as f:
            f.seek(start)
            remaining = chunk_size
            while remaining > 0:
                data = f.read(min(1024 * 1024, remaining))
                if not data:
                    break
                remaining -= len(data)
                yield data

    headers = {
        "Content-Range": f"bytes {start}-{end}/{file_size}",
        "Accept-Ranges": "bytes",
        "Content-Length": str(chunk_size),
    }

    return StreamingResponse(
        iter_file(),
        media_type=content_type,
        status_code=206,
        headers=headers,
    )

app.mount("/media", StaticFiles(directory=MEDIA_ROOT, check_dir=False), name="media")
app.mount("/static", StaticFiles(directory=STATIC_ROOT, check_dir=False), name="static")

# Legacy badge icon paths
BADGE_ICON_ROOT = os.path.join(MEDIA_ROOT, "badge_icons")
app.mount("/badge_icons", StaticFiles(directory=BADGE_ICON_ROOT, check_dir=False), name="badge_icons")

# Auth routes
app.include_router(admin_auth.router, tags=["auth"])
app.include_router(admin_profile.router, tags=["admin-profile"])

# Public/health
app.include_router(health.router, prefix="/health", tags=["health"])

# Public/mobile API
app.include_router(public_api.router, prefix="/api", tags=["public-api"])
app.include_router(billing.router, tags=["billing"])
app.include_router(billing.admin_router, tags=["billing"])
app.include_router(stripe_webhooks.router, tags=["billing"])


# Admin routers
app.include_router(users.router, prefix="/admin/users", tags=["users"])
app.include_router(courses.router, prefix="/admin/courses", tags=["courses"])
app.include_router(modules.router, prefix="/admin/modules", tags=["modules"])
app.include_router(lessons.router, prefix="/admin/lessons", tags=["lessons"])
app.include_router(activities.router, prefix="/admin/activities", tags=["activities"])
app.include_router(question_banks.router, prefix="/admin/question_banks", tags=["question_banks"])
app.include_router(videos.router, prefix="/admin/videos", tags=["videos"])
app.include_router(visemes.router, prefix="/admin/visemes", tags=["visemes"])
# app.include_router(inference_jobs.router, prefix="/admin/inference_jobs", tags=["inference_jobs"])
# app.include_router(attempts.router, prefix="/admin/attempts", tags=["attempts"])
# app.include_router(analytics.router, prefix="/admin/analytics", tags=["analytics"])
# app.include_router(flags.router, prefix="/admin/flags", tags=["flags"])
app.include_router(import_export.router, prefix="/admin", tags=["import_export"])
# app.include_router(feedback.router, prefix="/admin/feedback", tags=["feedback"])
app.include_router(tasks.router, tags=["tasks"])
app.include_router(ui.router, tags=["ui"])
app.include_router(report.router, tags=["reports"])
app.include_router(stripe_webhooks.router, prefix="/api/stripe", tags=["Stripe Webhooks"])


@app.exception_handler(HTTPException)
async def auth_exception_handler(request: Request, exc: HTTPException):
    if exc.status_code == status.HTTP_401_UNAUTHORIZED:
        return templates.TemplateResponse(
            "unauthorized.html", {"request": request}, status_code=status.HTTP_401_UNAUTHORIZED
        )
    return await http_exception_handler(request, exc)
