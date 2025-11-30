from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

from app.services.firebase_client import get_firestore_client


@dataclass
class LessonRecord:
    id: str
    title: str
    order: int
    estimatedMin: int
    objectives: List[str]
    createdAt: Optional[datetime] = None
    updatedAt: Optional[datetime] = None


class LessonService:
    """Encapsulates Firestore CRUD operations for lessons under courses/modules."""

    def __init__(self) -> None:
        self.db = get_firestore_client()

    def _lesson_collection(self, course_id: str, module_id: str):
        return (
            self.db.collection("courses")
            .document(course_id)
            .collection("modules")
            .document(module_id)
            .collection("lessons")
        )

    def _module_doc(self, course_id: str, module_id: str):
        return (
            self.db.collection("courses")
            .document(course_id)
            .collection("modules")
            .document(module_id)
        )

    def get_module(self, course_id: str, module_id: str) -> Optional[Dict[str, Any]]:
        doc = self._module_doc(course_id, module_id).get()
        if not doc.exists:
            return None
        data = doc.to_dict() or {}
        return {
            "id": doc.id,
            "title": data.get("title"),
            "summary": data.get("summary"),
            "order": data.get("order"),
            "createdAt": data.get("createdAt"),
            "updatedAt": data.get("updatedAt"),
        }

    def list_lessons(
        self, course_id: str, module_id: str, page: int = 1, page_size: int = 20
    ) -> Tuple[List[LessonRecord], int]:
        collection = self._lesson_collection(course_id, module_id)
        query = collection.order_by("order")
        if page > 1:
            query = query.offset((page - 1) * page_size)
        query = query.limit(page_size)

        lessons: List[LessonRecord] = []
        for doc in query.stream():
            data = doc.to_dict() or {}
            lessons.append(
                LessonRecord(
                    id=doc.id,
                    title=data.get("title", ""),
                    order=int(data.get("order") or 0),
                    estimatedMin=int(data.get("estimatedMin") or 0),
                    objectives=list(data.get("objectives") or []),
                    createdAt=data.get("createdAt"),
                    updatedAt=data.get("updatedAt"),
                )
            )

        total = self._count_lessons(collection)
        lessons.sort(key=lambda l: l.order)
        return lessons, total

    def _count_lessons(self, collection) -> int:
        try:
            agg = collection.count().get()
            # AggregationResult stores fields by index then field name
            return agg[0][0].value  # type: ignore[index]
        except Exception:
            # Fallback for emulator or old SDKs
            return sum(1 for _ in collection.stream())

    def get_lesson(self, course_id: str, module_id: str, lesson_id: str) -> Optional[LessonRecord]:
        doc = self._lesson_collection(course_id, module_id).document(lesson_id).get()
        if not doc.exists:
            return None
        data = doc.to_dict() or {}
        return LessonRecord(
            id=doc.id,
            title=data.get("title", ""),
            order=int(data.get("order") or 0),
            estimatedMin=int(data.get("estimatedMin") or 0),
            objectives=list(data.get("objectives") or []),
            createdAt=data.get("createdAt"),
            updatedAt=data.get("updatedAt"),
        )

    def create_lesson(self, course_id: str, module_id: str, payload: Dict[str, Any]) -> str:
        now = datetime.now(timezone.utc)
        payload.setdefault("createdAt", now)
        payload.setdefault("updatedAt", now)
        payload.setdefault("order", 0)
        payload.setdefault("estimatedMin", 0)
        payload.setdefault("objectives", [])
        doc_ref = self._lesson_collection(course_id, module_id).document()
        doc_ref.set(payload)
        return doc_ref.id

    def update_lesson(
        self, course_id: str, module_id: str, lesson_id: str, payload: Dict[str, Any]
    ) -> bool:
        doc_ref = self._lesson_collection(course_id, module_id).document(lesson_id)
        if not doc_ref.get().exists:
            return False
        payload = {**payload, "updatedAt": datetime.now(timezone.utc)}
        doc_ref.update(payload)
        return True

    def delete_lesson(self, course_id: str, module_id: str, lesson_id: str) -> bool:
        doc_ref = self._lesson_collection(course_id, module_id).document(lesson_id)
        if not doc_ref.get().exists:
            return False
        # cascade delete activities
        for activity in doc_ref.collection("activities").stream():
            doc_ref.collection("activities").document(activity.id).delete()
        doc_ref.delete()
        return True

    def reindex_orders(self, course_id: str, module_id: str) -> None:
        """Ensure order field is sequential after deletes."""
        lessons, _ = self.list_lessons(course_id, module_id, page=1, page_size=500)
        batch = self.db.batch()
        for idx, lesson in enumerate(lessons):
            ref = self._lesson_collection(course_id, module_id).document(lesson.id)
            batch.update(ref, {"order": idx})
        batch.commit()


lesson_service = LessonService()
