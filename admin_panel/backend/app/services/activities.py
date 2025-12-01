from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from google.cloud.firestore_v1 import Query

from app.services.firebase_client import get_firestore_client
from app.services.question_banks import BankQuestion, question_bank_service


@dataclass
class ActivityRecord:
    id: str
    title: str
    type: str
    order: int
    scoring: Dict[str, Any]
    config: Dict[str, Any]
    questionCount: int
    createdAt: Any = None
    updatedAt: Any = None


@dataclass
class ActivityQuestion:
    id: str
    questionId: str
    bankId: str
    mode: str
    order: int
    data: Optional[Dict[str, Any]]
    resolvedQuestion: Optional[Dict[str, Any]]


class ActivityService:
    """CRUD operations for activities and their attached questions."""

    def __init__(self) -> None:
        self.db = get_firestore_client()

    def _activities_collection(self, course_id: str, module_id: str, lesson_id: str):
        return (
            self.db.collection("courses")
            .document(course_id)
            .collection("modules")
            .document(module_id)
            .collection("lessons")
            .document(lesson_id)
            .collection("activities")
        )

    def _activity_doc(self, course_id: str, module_id: str, lesson_id: str, activity_id: str):
        return self._activities_collection(course_id, module_id, lesson_id).document(activity_id)

    def _questions_collection(self, course_id: str, module_id: str, lesson_id: str, activity_id: str):
        return self._activity_doc(course_id, module_id, lesson_id, activity_id).collection("questions")

    def list_activities(self, course_id: str, module_id: str, lesson_id: str) -> List[ActivityRecord]:
        activities: List[ActivityRecord] = []
        for doc in self._activities_collection(course_id, module_id, lesson_id).order_by("order").stream():
            data = doc.to_dict() or {}
            question_count = self._count_questions(course_id, module_id, lesson_id, doc.id)
            activities.append(
                ActivityRecord(
                    id=doc.id,
                    title=data.get("title") or data.get("type", "activity"),
                    type=data.get("type", "activity"),
                    order=int(data.get("order") or 0),
                    scoring=dict(data.get("scoring") or {}),
                    config=dict(data.get("config") or {}),
                    questionCount=question_count,
                    createdAt=data.get("createdAt"),
                    updatedAt=data.get("updatedAt"),
                )
            )
        return activities

    def _count_questions(self, course_id: str, module_id: str, lesson_id: str, activity_id: str) -> int:
        collection = self._questions_collection(course_id, module_id, lesson_id, activity_id)
        try:
            agg = collection.count().get()
            return agg[0][0].value  # type: ignore[index]
        except Exception:
            return sum(1 for _ in collection.stream())

    def get_activity(self, course_id: str, module_id: str, lesson_id: str, activity_id: str) -> Optional[Dict[str, Any]]:
        doc = self._activity_doc(course_id, module_id, lesson_id, activity_id).get()
        if not doc.exists:
            return None
        data = doc.to_dict() or {}
        questions = self._load_questions(course_id, module_id, lesson_id, activity_id)
        return {
            "id": doc.id,
            "title": data.get("title") or data.get("type"),
            "type": data.get("type"),
            "order": int(data.get("order") or 0),
            "config": dict(data.get("config") or {}),
            "scoring": dict(data.get("scoring") or {}),
            "questions": questions,
            "createdAt": data.get("createdAt"),
            "updatedAt": data.get("updatedAt"),
        }

    def _load_questions(
        self, course_id: str, module_id: str, lesson_id: str, activity_id: str
    ) -> List[ActivityQuestion]:
        attached: List[ActivityQuestion] = []
        for doc in self._questions_collection(course_id, module_id, lesson_id, activity_id).order_by("order").stream():
            data = doc.to_dict() or {}
            mode = data.get("mode", "reference")
            embedded = data.get("data") if mode == "embedded" else None
            resolved = None
            bank_id = data.get("bankId")
            question_id = data.get("questionId")
            if embedded:
                resolved = embedded
            elif bank_id and question_id:
                qb_question = question_bank_service.get_question(bank_id, question_id)
                if qb_question:
                    resolved = self._question_to_dict(qb_question)
            attached.append(
                ActivityQuestion(
                    id=doc.id,
                    questionId=question_id,
                    bankId=bank_id,
                    mode=mode,
                    order=int(data.get("order") or 0),
                    data=embedded,
                    resolvedQuestion=resolved,
                )
            )
        attached.sort(key=lambda q: q.order)
        return attached

    def create_activity(
        self,
        course_id: str,
        module_id: str,
        lesson_id: str,
        *,
        title: str,
        type: str,
        order: int,
        scoring: Dict[str, Any],
        config: Optional[Dict[str, Any]] = None,
        question_bank_id: Optional[str] = None,
        question_ids: Optional[List[str]] = None,
        embed_questions: bool = False,
        ab_variant: Optional[str] = None,
        created_by: Optional[str] = None,
    ) -> str:
        now = datetime.now(timezone.utc)
        payload = {
            "title": title or type,
            "type": type,
            "order": int(order),
            "scoring": scoring or {},
            "config": config or {},
            "abVariant": ab_variant,
            "createdAt": now,
            "updatedAt": now,
        }
        if question_bank_id:
            payload["config"]["questionBankId"] = question_bank_id
        if embed_questions:
            payload["config"]["embedQuestions"] = True
        if created_by:
            payload["createdBy"] = created_by

        doc_ref = self._activities_collection(course_id, module_id, lesson_id).document()
        doc_ref.set(payload)

        if question_bank_id and question_ids:
            self._attach_questions(
                course_id,
                module_id,
                lesson_id,
                doc_ref.id,
                question_bank_id,
                question_ids,
                embed_questions,
            )
        return doc_ref.id

    def update_activity(
        self,
        course_id: str,
        module_id: str,
        lesson_id: str,
        activity_id: str,
        *,
        title: str,
        type: str,
        order: int,
        scoring: Dict[str, Any],
        config: Optional[Dict[str, Any]] = None,
        question_bank_id: Optional[str] = None,
        question_ids: Optional[List[str]] = None,
        embed_questions: bool = False,
        ab_variant: Optional[str] = None,
    ) -> bool:
        doc_ref = self._activity_doc(course_id, module_id, lesson_id, activity_id)
        if not doc_ref.get().exists:
            return False
        payload = {
            "title": title or type,
            "type": type,
            "order": int(order),
            "scoring": scoring or {},
            "config": config or {},
            "abVariant": ab_variant,
            "updatedAt": datetime.now(timezone.utc),
        }
        if question_bank_id:
            payload["config"]["questionBankId"] = question_bank_id
        if embed_questions:
            payload["config"]["embedQuestions"] = True
        doc_ref.update(payload)

        questions = question_ids or []
        if question_bank_id is not None:
            self._replace_questions(
                course_id,
                module_id,
                lesson_id,
                activity_id,
                question_bank_id,
                questions,
                embed_questions,
            )
        return True

    def delete_activity(
        self, course_id: str, module_id: str, lesson_id: str, activity_id: str
    ) -> bool:
        doc_ref = self._activity_doc(course_id, module_id, lesson_id, activity_id)
        if not doc_ref.get().exists:
            return False
        for q in self._questions_collection(course_id, module_id, lesson_id, activity_id).stream():
            q.reference.delete()
        doc_ref.delete()
        return True

    def next_order(self, course_id: str, module_id: str, lesson_id: str) -> int:
        collection = self._activities_collection(course_id, module_id, lesson_id)
        try:
            snap = (
                collection.order_by("order", direction=Query.DESCENDING)
                .limit(1)
                .stream()
            )
            last = next(iter(snap), None)
            if last:
                data = last.to_dict() or {}
                return int(data.get("order") or 0) + 1
        except Exception:
            pass
        return 0

    def _replace_questions(
        self,
        course_id: str,
        module_id: str,
        lesson_id: str,
        activity_id: str,
        bank_id: str,
        question_ids: List[str],
        embed: bool,
    ) -> None:
        col = self._questions_collection(course_id, module_id, lesson_id, activity_id)
        for q in col.stream():
            q.reference.delete()
        if question_ids:
            self._attach_questions(course_id, module_id, lesson_id, activity_id, bank_id, question_ids, embed)

    def _attach_questions(
        self,
        course_id: str,
        module_id: str,
        lesson_id: str,
        activity_id: str,
        bank_id: str,
        question_ids: List[str],
        embed: bool,
    ) -> None:
        col = self._questions_collection(course_id, module_id, lesson_id, activity_id)
        batch = self.db.batch()
        for idx, qid in enumerate(question_ids):
            question = question_bank_service.get_question(bank_id, qid)
            if not question:
                continue
            payload: Dict[str, Any] = {
                "questionId": qid,
                "bankId": bank_id,
                "mode": "embedded" if embed else "reference",
                "order": idx,
            }
            if embed:
                payload["data"] = self._question_to_dict(question)
            batch.set(col.document(), payload)
        batch.commit()

    def _question_to_dict(self, question: BankQuestion) -> Dict[str, Any]:
        return {
            "id": question.id,
            "bankId": question.bankId,
            "type": question.type,
            "stem": question.stem,
            "options": question.options,
            "answers": question.answers,
            "answerPattern": question.answerPattern,
            "explanation": question.explanation,
            "tags": question.tags,
            "difficulty": question.difficulty,
            "mediaId": question.mediaId,
        }


activity_service = ActivityService()
