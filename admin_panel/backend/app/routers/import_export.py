from typing import Any, Dict, List

from fastapi import APIRouter, File, HTTPException, UploadFile
import json

from firebase_admin import firestore as admin_fs

router = APIRouter()
db = admin_fs.client()
COL = "import_export"

@router.post("/admin/import_export")
async def import_seed_json(file: UploadFile = File(...)) -> Dict[str, Any]:
    """
    Import the course/module/lesson/activity seed JSON into Firestore.

    Expected JSON structure (courses_seed.json):

    {
      "courses": [
        {
          "id": "course_id",
          "data": { ...course fields... },
          "modules": [
            {
              "id": "module_id",
              "data": { ...module fields... },
              "lessons": [
                {
                  "id": "lesson_id",
                  "data": { ...lesson fields... },
                  "activities": [
                    {
                      "id": "activity_id",
                      "data": { ...activity fields... }
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    """
    # ------- Parse JSON -------
    try:
        raw_bytes = await file.read()
        text = raw_bytes.decode("utf-8")
        payload = json.loads(text)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {e}")

    courses: List[Dict[str, Any]] = payload.get("courses", [])
    if not isinstance(courses, list) or not courses:
        raise HTTPException(
            status_code=400,
            detail="JSON must contain a non-empty 'courses' array",
        )

    # ------- Write to Firestore in a batch -------
    batch = db.batch()
    courses_written = 0
    modules_written = 0
    lessons_written = 0
    activities_written = 0

    for course in courses:
        course_id = course.get("id")
        course_data = course.get("data", {})
        if not course_id:
            continue

        course_ref = db.collection("courses").document(course_id)
        batch.set(course_ref, course_data)
        courses_written += 1

        # --- Modules ---
        for module in course.get("modules", []) or []:
            module_id = module.get("id")
            module_data = module.get("data", {})
            if not module_id:
                continue

            module_ref = course_ref.collection("modules").document(module_id)
            batch.set(module_ref, module_data)
            modules_written += 1

            # --- Lessons ---
            for lesson in module.get("lessons", []) or []:
                lesson_id = lesson.get("id")
                lesson_data = lesson.get("data", {})
                if not lesson_id:
                    continue

                lesson_ref = module_ref.collection("lessons").document(lesson_id)
                batch.set(lesson_ref, lesson_data)
                lessons_written += 1

                # --- Activities ---
                for activity in lesson.get("activities", []) or []:
                    activity_id = activity.get("id")
                    activity_data = activity.get("data", {})
                    if not activity_id:
                        continue

                    act_ref = lesson_ref.collection("activities").document(activity_id)
                    batch.set(act_ref, activity_data)
                    activities_written += 1

    batch.commit()

    return {
        "status": "ok",
        "courses": courses_written,
        "modules": modules_written,
        "lessons": lessons_written,
        "activities": activities_written,
    }