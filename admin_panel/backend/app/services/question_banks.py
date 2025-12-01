from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from app.services.firebase_client import get_firestore_client


@dataclass
class QuestionBank:
    id: str
    title: str
    topic: Optional[str]
    difficulty: int
    tags: List[str]
    ownerId: Optional[str]
    isArchive: bool
    description: Optional[str] = None
    createdBy: Optional[str] = None
    createdAt: Any = None
    updatedAt: Any = None


@dataclass
class BankQuestion:
    id: str
    bankId: str
    type: str
    stem: str
    options: List[Any]
    answers: List[Any]
    answerPattern: Optional[str]
    explanation: Optional[str]
    tags: List[str]
    difficulty: int
    mediaId: Optional[str]
    createdAt: Any = None
    updatedAt: Any = None

    def to_dict(self) -> Dict[str, Any]:
        """Return a JSON-serializable representation for templates / APIs."""

        def _serialize_ts(value: Any) -> Optional[str]:
            if not value:
                return None
            iso = getattr(value, "isoformat", None)
            if callable(iso):
                return iso()
            return str(value)

        return {
            "id": self.id,
            "bankId": self.bankId,
            "type": self.type,
            "stem": self.stem,
            "options": list(self.options or []),
            "answers": list(self.answers or []),
            "answerPattern": self.answerPattern,
            "explanation": self.explanation,
            "tags": list(self.tags or []),
            "difficulty": self.difficulty,
            "mediaId": self.mediaId,
            "createdAt": _serialize_ts(self.createdAt),
            "updatedAt": _serialize_ts(self.updatedAt),
        }


class QuestionBankService:
    """CRUD helpers for question banks used by admin activities."""

    def __init__(self) -> None:
        self.db = get_firestore_client()

    def _bank_collection(self):
        return self.db.collection("question_banks")

    def _bank_doc(self, bank_id: str):
        return self._bank_collection().document(bank_id)

    def _question_collection(self, bank_id: str):
        return self._bank_doc(bank_id).collection("questions")

    def create_question(
        self,
        bank_id: str,
        *,
        stem: str,
        options: Optional[List[Any]] = None,
        answers: Optional[List[Any]] = None,
        answer_pattern: Optional[str] = None,
        explanation: Optional[str] = None,
        tags: Optional[List[str]] = None,
        difficulty: int = 1,
        media_id: Optional[str] = None,
        question_type: str = "mcq",
    ) -> str:
        """Create a question inside a bank and return its id."""

        now = datetime.now(timezone.utc)
        payload = {
            "type": question_type or "mcq",
            "stem": stem,
            "options": list(options or []),
            "answers": list(answers or []),
            "answerPattern": answer_pattern,
            "explanation": explanation,
            "tags": list(tags or []),
            "difficulty": int(difficulty) if difficulty is not None else 1,
            "mediaId": media_id,
            "createdAt": now,
            "updatedAt": now,
        }
        doc_ref = self._question_collection(bank_id).document()
        doc_ref.set(payload)
        return doc_ref.id

    def list_banks(self, limit: int = 200) -> List[QuestionBank]:
        banks: List[QuestionBank] = []
        for doc in self._bank_collection().limit(limit).stream():
            data = doc.to_dict() or {}
            banks.append(
                QuestionBank(
                    id=doc.id,
                    title=data.get("title", "Untitled bank"),
                    topic=data.get("topic"),
                    difficulty=int(data.get("difficulty", 1)),
                    tags=list(data.get("tags") or []),
                    ownerId=data.get("ownerId"),
                    isArchive=bool(data.get("isArchive", False)),
                    description=data.get("description"),
                    createdBy=data.get("createdBy"),
                    createdAt=data.get("createdAt"),
                    updatedAt=data.get("updatedAt"),
                )
            )
        banks.sort(key=lambda b: b.title.lower())
        return banks

    def get_bank(self, bank_id: str) -> Optional[QuestionBank]:
        snap = self._bank_doc(bank_id).get()
        if not snap.exists:
            return None
        data = snap.to_dict() or {}
        return QuestionBank(
            id=snap.id,
            title=data.get("title", "Untitled bank"),
            topic=data.get("topic"),
            difficulty=int(data.get("difficulty", 1)),
            tags=list(data.get("tags") or []),
            ownerId=data.get("ownerId"),
            isArchive=bool(data.get("isArchive", False)),
            description=data.get("description"),
            createdBy=data.get("createdBy"),
            createdAt=data.get("createdAt"),
            updatedAt=data.get("updatedAt"),
        )

    def create_bank(
        self,
        *,
        title: str,
        difficulty: int,
        tags: Optional[List[str]] = None,
        description: Optional[str] = None,
        created_by: Optional[str] = None,
    ) -> str:
        doc_ref = self._bank_collection().document()
        now = datetime.now(timezone.utc)
        payload = {
            "title": title or "Untitled bank",
            "difficulty": int(difficulty) if difficulty is not None else 1,
            "tags": list(tags or []),
            "description": description or None,
            "createdBy": created_by,
            "createdAt": now,
            "updatedAt": now,
        }
        doc_ref.set(payload)
        return doc_ref.id

    def list_questions(self, bank_id: str, limit: int = 500, as_dict: bool = False) -> List[Any]:
        questions: List[Any] = []
        for doc in self._question_collection(bank_id).limit(limit).stream():
            mapped = self._map_question(doc, bank_id)
            if mapped:
                questions.append(mapped.to_dict() if as_dict else mapped)
        questions.sort(key=lambda q: (q["stem"] if isinstance(q, dict) else q.stem).lower())
        return questions

    def get_question(self, bank_id: str, question_id: str) -> Optional[BankQuestion]:
        doc = self._question_collection(bank_id).document(question_id).get()
        return self._map_question(doc, bank_id)

    def _map_question(self, doc, bank_id: str) -> Optional[BankQuestion]:
        if not doc or not doc.exists:
            return None
        data = doc.to_dict() or {}
        return BankQuestion(
            id=doc.id,
            bankId=bank_id,
            type=data.get("type", "mcq"),
            stem=data.get("stem", ""),
            options=list(data.get("options") or []),
            answers=list(data.get("answers") or []),
            answerPattern=data.get("answerPattern"),
            explanation=data.get("explanation"),
            tags=list(data.get("tags") or []),
            difficulty=int(data.get("difficulty", 1)),
            mediaId=data.get("mediaId"),
            createdAt=data.get("createdAt"),
            updatedAt=data.get("updatedAt"),
        )


question_bank_service = QuestionBankService()
