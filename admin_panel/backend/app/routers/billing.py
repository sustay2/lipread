from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from google.api_core.exceptions import FailedPrecondition
from google.cloud.firestore_v1 import Query

from app.deps.auth import get_current_user
from app.services import billing_service
from app.services.firebase_client import get_firestore_client

router = APIRouter(prefix="/api/billing")
db = get_firestore_client()


def _serialize_timestamp(value: Any) -> Any:
    if hasattr(value, "isoformat"):
        try:
            return value.isoformat()
        except Exception:
            return value
    return value


def _serialize_plan(doc_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": doc_id,
        "name": data.get("name"),
        "price_myr": data.get("price_myr"),
        "stripe_product_id": data.get("stripe_product_id"),
        "stripe_price_id": data.get("stripe_price_id"),
        "transcription_limit": data.get("transcription_limit"),
        "is_transcription_unlimited": data.get("is_transcription_unlimited", False),
        "can_access_premium_courses": data.get("can_access_premium_courses", False),
        "trial_period_days": data.get("trial_period_days", 0),
        "is_active": data.get("is_active", False),
        "createdAt": _serialize_timestamp(data.get("createdAt")),
        "updatedAt": _serialize_timestamp(data.get("updatedAt")),
    }


def _serialize_subscription(doc_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": doc_id,
        "plan_id": data.get("plan_id"),
        "stripe_customer_id": data.get("stripe_customer_id"),
        "stripe_subscription_id": data.get("stripe_subscription_id"),
        "status": data.get("status"),
        "is_trialing": data.get("is_trialing", False),
        "trial_end_at": _serialize_timestamp(data.get("trial_end_at")),
        "current_period_end": _serialize_timestamp(data.get("current_period_end")),
        "usage_counters": data.get("usage_counters", {}),
        "createdAt": _serialize_timestamp(data.get("createdAt")),
        "updatedAt": _serialize_timestamp(data.get("updatedAt")),
    }


@router.get("/plans")
async def list_plans() -> Dict[str, List[Dict[str, Any]]]:
    plans: List[Dict[str, Any]] = []
    snaps = db.collection("subscription_plans").stream()
    for snap in snaps:
        data = snap.to_dict() or {}
        if data.get("is_active", False):
            plans.append(_serialize_plan(snap.id, data))
    plans.sort(key=lambda p: p.get("price_myr") or 0)
    return {"items": plans}


@router.get("/me")
async def get_my_subscription(user=Depends(get_current_user)) -> Dict[str, Any]:
    uid = user.get("uid")
    sub_ref = db.collection("user_subscriptions").document(uid)
    sub_snap = sub_ref.get()
    if not sub_snap.exists:
        return {"subscription": None, "plan": None}

    sub_data = sub_snap.to_dict() or {}
    plan_id = sub_data.get("plan_id")
    plan_data: Optional[Dict[str, Any]] = None
    if plan_id:
        plan_snap = db.collection("subscription_plans").document(plan_id).get()
        if plan_snap.exists:
            plan_data = _serialize_plan(plan_snap.id, plan_snap.to_dict() or {})

    return {
        "subscription": _serialize_subscription(sub_snap.id, sub_data),
        "plan": plan_data,
    }


@router.post("/checkout-session")
async def create_checkout_session(
    payload: Dict[str, Any], user=Depends(get_current_user)
) -> Dict[str, Any]:
    price_id = payload.get("price_id")
    success_url = payload.get("success_url")
    cancel_url = payload.get("cancel_url")
    if not (price_id and success_url and cancel_url):
        raise HTTPException(status_code=400, detail="price_id, success_url, and cancel_url are required")

    uid = user.get("uid")
    email = user.get("email") or ""
    return billing_service.create_checkout_session(
        firebase_uid=uid,
        price_id=price_id,
        success_url=success_url,
        cancel_url=cancel_url,
        email=email,
    )


@router.post("/customer-portal")
async def create_customer_portal_session(
    payload: Dict[str, Any], user=Depends(get_current_user)
) -> Dict[str, Any]:
    return_url = payload.get("return_url")
    stripe_customer_id = payload.get("stripe_customer_id")
    if not return_url:
        raise HTTPException(status_code=400, detail="return_url is required")

    if not stripe_customer_id:
        uid = user.get("uid")
        sub_snap = db.collection("user_subscriptions").document(uid).get()
        if sub_snap.exists:
            sub_data = sub_snap.to_dict() or {}
            stripe_customer_id = sub_data.get("stripe_customer_id")
    if not stripe_customer_id:
        raise HTTPException(status_code=400, detail="stripe_customer_id is required")

    return billing_service.create_billing_portal_session(
        stripe_customer_id=stripe_customer_id, return_url=return_url
    )


@router.get("/history")
async def get_billing_history(user=Depends(get_current_user)) -> Dict[str, List[Dict[str, Any]]]:
    uid = user.get("uid")
    try:
        snaps = (
            db.collection("payments")
            .where("userId", "==", uid)
            .order_by("createdAt", direction=Query.DESCENDING)
            .limit(100)
            .stream()
        )
    except FailedPrecondition as e:
        raise HTTPException(
            status_code=500,
            detail=(
                "Firestore index is required for payments query (userId + createdAt). "
                f"Create the suggested index from the Firebase error link. Details: {e.message}"
            ),
        )

    items: List[Dict[str, Any]] = []
    for snap in snaps:
        data = snap.to_dict() or {}
        items.append(
            {
                "id": snap.id,
                "planId": data.get("planId"),
                "amount": data.get("amount"),
                "currency": data.get("currency", "MYR"),
                "status": data.get("status", "pending"),
                "transactionId": data.get("transactionId"),
                "createdAt": _serialize_timestamp(data.get("createdAt")),
            }
        )

    return {"items": items}
