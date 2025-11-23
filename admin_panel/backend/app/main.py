import os
from fastapi import FastAPI
from starlette.staticfiles import StaticFiles
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
    analytics,
    attempts,
    feedback,
    flags,
    import_export,
)
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="LipReading Admin API")

ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in ALLOWED_ORIGINS.split(",")],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve local media read-only
MEDIA_ROOT = os.getenv("MEDIA_ROOT", "/data")
app.mount("/media", StaticFiles(directory=MEDIA_ROOT), name="media")


# Public/health
app.include_router(health.router, prefix="/health", tags=["health"])


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