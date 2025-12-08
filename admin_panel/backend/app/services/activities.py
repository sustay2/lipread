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
    itemCount: int
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


@dataclass
class DictationItem:
    id: str
    correctText: str
    mediaId: Optional[str]
    hints: Optional[str]
    order: int


@dataclass
class PracticeItem:
    id: str
    description: str
    targetWord: Optional[str]
    mediaId: Optional[str]
    order: int


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

    def _dictation_collection(
        self, course_id: str, module_id: str, lesson_id: str, activity_id: str
    ):
        return self._activity_doc(course_id, module_id, lesson_id, activity_id).collection(
            "dictationItems"
        )

    def _practice_collection(
        self, course_id: str, module_id: str, lesson_id: str, activity_id: str
    ):
        return self._activity_doc(course_id, module_id, lesson_id, activity_id).collection(
            "practiceItems"
        )

    def list_activities(self, course_id: str, module_id: str, lesson_id: str) -> List[ActivityRecord]:
        activities: List[ActivityRecord] = []
        for doc in self._activities_collection(course_id, module_id, lesson_id).order_by("order").stream():
            data = doc.to_dict() or {}
            activity_type = data.get("type") or "activity"
            question_count = self._count_items(course_id, module_id, lesson_id, doc.id, activity_type)
            activities.append(
                ActivityRecord(
                    id=doc.id,
                    title=data.get("title") or activity_type,
                    type=activity_type,
                    order=int(data.get("order") or 0),
                    scoring=dict(data.get("scoring") or {}),
                    config=dict(data.get("config") or {}),
                    itemCount=question_count,
                    createdAt=data.get("createdAt"),
                    updatedAt=data.get("updatedAt"),
                )
            )
        return activities

    def _count_items(
        self, course_id: str, module_id: str, lesson_id: str, activity_id: str, activity_type: str
    ) -> int:
        if activity_type == "dictation":
            collection = self._dictation_collection(course_id, module_id, lesson_id, activity_id)
        elif activity_type == "practice_lip":
            collection = self._practice_collection(course_id, module_id, lesson_id, activity_id)
        else:
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
        activity_type = data.get("type")
        questions: List[ActivityQuestion] = []
        dictation_items: List[DictationItem] = []
        practice_items: List[PracticeItem] = []
        if activity_type == "dictation":
            dictation_items = self._load_dictation_items(course_id, module_id, lesson_id, activity_id)
        elif activity_type == "practice_lip":
            practice_items = self._load_practice_items(course_id, module_id, lesson_id, activity_id)
        else:
            questions = self._load_questions(course_id, module_id, lesson_id, activity_id)
        return {
            "id": doc.id,
            "title": data.get("title") or data.get("type"),
            "type": data.get("type"),
            "order": int(data.get("order") or 0),
            "config": dict(data.get("config") or {}),
            "scoring": dict(data.get("scoring") or {}),
            "questionBankId": data.get("questionBankId"),
            "questions": [q.__dict__ for q in questions],
            "dictationItems": [item.__dict__ for item in dictation_items],
            "practiceItems": [item.__dict__ for item in practice_items],
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
            embedded = data.get("data") if data.get("data") else None
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

    def _load_dictation_items(
        self, course_id: str, module_id: str, lesson_id: str, activity_id: str
    ) -> List[DictationItem]:
        items: List[DictationItem] = []
        for doc in self._dictation_collection(course_id, module_id, lesson_id, activity_id).order_by("order").stream():
            data = doc.to_dict() or {}
            items.append(
                DictationItem(
                    id=doc.id,
                    correctText=data.get("correctText", ""),
                    mediaId=data.get("mediaId"),
                    hints=data.get("hints"),
                    order=int(data.get("order") or 0),
                )
            )
        items.sort(key=lambda i: i.order)
        return items

    def _load_practice_items(
        self, course_id: str, module_id: str, lesson_id: str, activity_id: str
    ) -> List[PracticeItem]:
        items: List[PracticeItem] = []
        for doc in self._practice_collection(course_id, module_id, lesson_id, activity_id).order_by("order").stream():
            data = doc.to_dict() or {}
            items.append(
                PracticeItem(
                    id=doc.id,
                    description=data.get("description", ""),
                    targetWord=data.get("targetWord"),
                    mediaId=data.get("mediaId"),
                    order=int(data.get("order") or 0),
                )
            )
        items.sort(key=lambda i: i.order)
        return items

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
        dictation_items: Optional[List[Dict[str, Any]]] = None,
        practice_items: Optional[List[Dict[str, Any]]] = None,
    ) -> str:
        now = datetime.now(timezone.utc)
        payload = {
            "title": title or type,
            "type": type,
            "order": int(order),
            "scoring": scoring or {},
            "config": config or {},
            "abVariant": ab_variant,
            "questionBankId": question_bank_id,
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

        if type == "dictation" and dictation_items is not None:
            self._replace_dictation_items(course_id, module_id, lesson_id, doc_ref.id, dictation_items)
        elif type == "practice_lip" and practice_items is not None:
            self._replace_practice_items(course_id, module_id, lesson_id, doc_ref.id, practice_items)
        elif question_bank_id and question_ids:
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
        dictation_items: Optional[List[Dict[str, Any]]] = None,
        practice_items: Optional[List[Dict[str, Any]]] = None,
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
            "questionBankId": question_bank_id,
            "updatedAt": datetime.now(timezone.utc),
        }
        if question_bank_id:
            payload["config"]["questionBankId"] = question_bank_id
        if embed_questions:
            payload["config"]["embedQuestions"] = True
        doc_ref.update(payload)

        questions = question_ids or []
        if type == "dictation" and dictation_items is not None:
            self._replace_dictation_items(course_id, module_id, lesson_id, activity_id, dictation_items)
        elif type == "practice_lip" and practice_items is not None:
            self._replace_practice_items(course_id, module_id, lesson_id, activity_id, practice_items)
        elif question_bank_id is not None:
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
        for d in self._dictation_collection(course_id, module_id, lesson_id, activity_id).stream():
            d.reference.delete()
        for p in self._practice_collection(course_id, module_id, lesson_id, activity_id).stream():
            p.reference.delete()
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
        question_items: List[Dict[str, Any]],
        embed: bool,
    ) -> None:
        col = self._questions_collection(course_id, module_id, lesson_id, activity_id)

        existing_docs = {doc.id: doc.to_dict() for doc in col.stream()}
        batch = self.db.batch()

        for idx, item in enumerate(question_items):
            qid = item.get("id")
            existing = existing_docs.get(qid)

            # If existing and no new upload, preserve old mediaId
            media_id = item.get("mediaId")
            if existing and not item.get("needsUpload"):
                media_id = existing.get("mediaId")

            # Real question data (always embed)
            payload = {
                "questionId": item.get("questionId"),
                "bankId": bank_id,
                "order": idx,
                "mode": "copied" if embed else "reference",
                "type": item.get("type", "mcq"),
                "data": {
                    "id": item.get("questionId"),
                    "bankId": bank_id,
                    "type": item.get("type", "mcq"),
                    "stem": item.get("stem", ""),
                    "options": item.get("options", []),
                    "answers": item.get("answers", []),
                    "explanation": item.get("explanation"),
                    "mediaId": media_id,
                }
            }

            if qid:
                # Update existing reference
                batch.update(col.document(qid), payload)
            else:
                # Create new one
                batch.set(col.document(), payload)

        batch.commit()

    def _replace_dictation_items(
        self,
        course_id: str,
        module_id: str,
        lesson_id: str,
        activity_id: str,
        items: List[Dict[str, Any]],
    ) -> None:
        col = self._dictation_collection(course_id, module_id, lesson_id, activity_id)

        existing_docs = {doc.id: doc.to_dict() for doc in col.stream()}
        batch = self.db.batch()
        now = datetime.now(timezone.utc)

        for idx, item in enumerate(items):
            item_id = item.get("id")
            existing = existing_docs.get(item_id)

            media_id = item.get("mediaId")
            if existing and not item.get("needsUpload"):
                media_id = existing.get("mediaId")

            payload = {
                "correctText": item.get("correctText", ""),
                "mediaId": media_id,
                "hints": item.get("hints"),
                "order": idx,
                "updatedAt": now,
            }

            if item_id:
                batch.update(col.document(item_id), payload)
            else:
                payload["createdAt"] = now
                batch.set(col.document(), payload)

        batch.commit()

    def _replace_practice_items(
        self,
        course_id: str,
        module_id: str,
        lesson_id: str,
        activity_id: str,
        items: List[Dict[str, Any]],
    ) -> None:
        col = self._practice_collection(course_id, module_id, lesson_id, activity_id)

        existing_docs = {doc.id: doc.to_dict() for doc in col.stream()}
        batch = self.db.batch()
        now = datetime.now(timezone.utc)

        for idx, item in enumerate(items):
            item_id = item.get("id")
            existing = existing_docs.get(item_id)

            media_id = item.get("mediaId")
            if existing and not item.get("needsUpload"):
                media_id = existing.get("mediaId")

            payload = {
                "description": item.get("description", ""),
                "targetWord": item.get("targetWord"),
                "mediaId": media_id,
                "order": idx,
                "updatedAt": now,
            }

            if item_id:
                batch.update(col.document(item_id), payload)
            else:
                payload["createdAt"] = now
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
