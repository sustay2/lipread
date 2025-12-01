from __future__ import annotations

from dataclasses import dataclass
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


class QuestionBankService:
    """Read-only helpers for question banks used by admin activities."""

    def __init__(self) -> None:
        self.db = get_firestore_client()

    def _bank_collection(self):
        return self.db.collection("question_banks")

    def _bank_doc(self, bank_id: str):
        return self._bank_collection().document(bank_id)

    def _question_collection(self, bank_id: str):
        return self._bank_doc(bank_id).collection("questions")

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
        )

    def list_questions(self, bank_id: str, limit: int = 500) -> List[BankQuestion]:
        questions: List[BankQuestion] = []
        for doc in self._question_collection(bank_id).limit(limit).stream():
            mapped = self._map_question(doc, bank_id)
            if mapped:
                questions.append(mapped)
        questions.sort(key=lambda q: q.stem.lower())
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
