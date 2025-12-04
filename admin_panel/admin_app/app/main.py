from fastapi import Depends, FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from app.config import get_settings
from app.routers import (
    dashboard,
    users,
    progress,
    engagement,
    courses,
    modules,
    lessons,
    activities,
    analytics,
    reports,
    subscriptions,
)

app = FastAPI(title="Lipread Admin Panel", version="2.0.0")
settings = get_settings()

app.mount("/static", StaticFiles(directory="app/static"), name="static")
templates = Jinja2Templates(directory="app/templates")


@app.middleware("http")
async def inject_templates(request: Request, call_next):
    request.state.templates = templates
    request.state.settings = settings
    response = await call_next(request)
    return response


app.include_router(dashboard.router)
app.include_router(users.router)
app.include_router(progress.router)
app.include_router(engagement.router)
app.include_router(courses.router)
app.include_router(modules.router)
app.include_router(lessons.router)
app.include_router(activities.router)
app.include_router(analytics.router)
app.include_router(reports.router)
app.include_router(subscriptions.router)
