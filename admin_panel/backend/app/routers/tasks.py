from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.deps.admin_session import require_admin_session
from app.services import firestore_admin

BASE_DIR = Path(__file__).resolve().parents[1]
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

router = APIRouter(prefix="/admin/tasks", dependencies=[Depends(require_admin_session)])

TASK_ACTIONS: Dict[str, str] = {
    "quiz": "Complete a quiz",
    "practice": "Finish practice",
    "dictation": "Complete dictation",
}

VALID_FREQUENCIES = {"daily", "weekly"}


def _validate_task_payload(
    title: str,
    points: str,
    frequency: str,
    action_type: str,
    action_count: str,
) -> tuple[list[str], Dict[str, Any]]:
    errors: list[str] = []
    cleaned_title = (title or "").strip()
    if not cleaned_title:
        errors.append("Title is required")

    try:
        points_val = int(points)
        if points_val < 0:
            errors.append("Points must be zero or greater")
    except (TypeError, ValueError):
        points_val = 0
        errors.append("Points must be a number")

    freq_val = (frequency or "").strip().lower()
    if freq_val not in VALID_FREQUENCIES:
        errors.append("Frequency must be daily or weekly")

    action_val = (action_type or "").strip()
    if action_val not in TASK_ACTIONS:
        errors.append("Select a valid action")

    try:
        count_val = int(action_count)
        if count_val < 1:
            errors.append("Count must be at least 1")
    except (TypeError, ValueError):
        count_val = 1
        errors.append("Count must be a number")

    payload = {
        "title": cleaned_title,
        "points": points_val,
        "frequency": freq_val,
        "action": {"type": action_val, "count": max(count_val, 1)},
    }
    return errors, payload


@router.get("", response_class=HTMLResponse)
async def list_tasks(request: Request, message: Optional[str] = None):
    tasks = firestore_admin.list_user_tasks()
    return templates.TemplateResponse(
        "tasks/list.html",
        {
            "request": request,
            "tasks": tasks,
            "message": message,
            "actions": TASK_ACTIONS,
        },
    )


@router.get("/new", response_class=HTMLResponse)
async def new_task(request: Request):
    return templates.TemplateResponse(
        "tasks/form.html",
        {
            "request": request,
            "task": None,
            "errors": [],
            "actions": TASK_ACTIONS,
        },
    )


@router.post("")
async def create_task(
    request: Request,
    title: str = Form(""),
    points: str = Form("0"),
    frequency: str = Form("daily"),
    action_type: str = Form(""),
    action_count: str = Form("1"),
):
    errors, payload = _validate_task_payload(
        title, points, frequency, action_type, action_count
    )
    if errors:
        return templates.TemplateResponse(
            "tasks/form.html",
            {
                "request": request,
                "task": payload,
                "errors": errors,
                "actions": TASK_ACTIONS,
            },
            status_code=400,
        )

    firestore_admin.create_user_task(payload)
    return RedirectResponse(url="/admin/tasks?message=task-created", status_code=303)


@router.get("/{task_id}/edit", response_class=HTMLResponse)
async def edit_task(request: Request, task_id: str):
    task = firestore_admin.get_user_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return templates.TemplateResponse(
        "tasks/form.html",
        {"request": request, "task": task, "errors": [], "actions": TASK_ACTIONS},
    )


@router.post("/{task_id}/update")
async def update_task(
    request: Request,
    task_id: str,
    title: str = Form(""),
    points: str = Form("0"),
    frequency: str = Form("daily"),
    action_type: str = Form(""),
    action_count: str = Form("1"),
):
    errors, payload = _validate_task_payload(
        title, points, frequency, action_type, action_count
    )
    if errors:
        payload["id"] = task_id
        return templates.TemplateResponse(
            "tasks/form.html",
            {
                "request": request,
                "task": payload,
                "errors": errors,
                "actions": TASK_ACTIONS,
            },
            status_code=400,
        )

    firestore_admin.update_user_task(task_id, payload)
    return RedirectResponse(url="/admin/tasks?message=task-updated", status_code=303)


@router.post("/{task_id}/delete")
async def delete_task(task_id: str):
    firestore_admin.delete_user_task(task_id)
    return RedirectResponse(url="/admin/tasks?message=task-deleted", status_code=303)
