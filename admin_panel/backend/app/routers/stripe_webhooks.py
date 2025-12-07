from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
from typing import Any, Dict, Optional

import stripe
from fastapi import APIRouter, HTTPException, Request
from google.cloud.firestore_v1 import SERVER_TIMESTAMP

from app.services.firebase_client import get_firestore_client

logger = logging.getLogger(__name__)

STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY")
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET")

if not STRIPE_SECRET_KEY:
    raise RuntimeError("STRIPE_SECRET_KEY environment variable is required for Stripe integration")
if not STRIPE_WEBHOOK_SECRET:
    raise RuntimeError("STRIPE_WEBHOOK_SECRET environment variable is required for Stripe webhooks")

stripe.api_key = STRIPE_SECRET_KEY

router = APIRouter()
db = get_firestore_client()


def _timestamp_from_unix(value: Optional[int]) -> Optional[datetime]:
    if not value:
        return None
    return datetime.fromtimestamp(value, tz=timezone.utc)


def _retrieve_subscription(subscription_id: str) -> Optional[Dict[str, Any]]:
    try:
        return stripe.Subscription.retrieve(subscription_id)
    except Exception as exc:  # pragma: no cover - network/Stripe handled at runtime
        logger.error("Failed to retrieve subscription %s: %s", subscription_id, exc)
        return None


def _extract_firebase_uid(obj: Dict[str, Any], subscription: Optional[Dict[str, Any]]) -> Optional[str]:
    metadata = obj.get("metadata") or {}
    uid = metadata.get("firebase_uid")
    if uid:
        return uid

    if subscription:
        sub_metadata = subscription.get("metadata") or {}
        uid = sub_metadata.get("firebase_uid")
        if uid:
            return uid
    return None


def _update_user_subscription(
    uid: str, subscription: Optional[Dict[str, Any]], subscription_id: Optional[str], status_override: Optional[str] = None
) -> None:
    if not uid:
        return

    subscription = subscription or {}
    
    # Extract price_id to find the corresponding internal Plan ID
    plan_id = None
    if subscription:
        # Stripe subscriptions have 'items', usually the first one contains the price
        items = subscription.get("items", {}).get("data", [])
        if items:
            price_id = items[0].get("price", {}).get("id")
            if price_id:
                # Query Firestore to find the plan with this stripe_price_id
                # This is inefficient if you have many plans, but safe for now.
                # Ideally, store a map or cache this.
                plans_ref = db.collection("subscription_plans").where("stripe_price_id", "==", price_id).limit(1)
                docs = list(plans_ref.stream())
                if docs:
                    plan_id = docs[0].id

    data: Dict[str, Any] = {
        "stripe_subscription_id": subscription_id or subscription.get("id"),
        "status": status_override or subscription.get("status"),
        "trial_end_at": _timestamp_from_unix(subscription.get("trial_end")),
        "current_period_end": _timestamp_from_unix(subscription.get("current_period_end")),
        "updatedAt": SERVER_TIMESTAMP,
    }
    
    # Save plan_id if found
    if plan_id:
        data["plan_id"] = plan_id

    db.collection("user_subscriptions").document(uid).set(data, merge=True)


@router.post("/webhook")
async def handle_stripe_webhook(request: Request) -> Dict[str, bool]:
    payload = await request.body()
    sig_header = request.headers.get("stripe-signature")

    try:
        event = stripe.Webhook.construct_event(payload, sig_header, STRIPE_WEBHOOK_SECRET)
    except ValueError as exc:
        logger.error("Invalid payload for Stripe webhook: %s", exc)
        raise HTTPException(status_code=400, detail="Invalid payload")
    except stripe.error.SignatureVerificationError as exc:
        logger.error("Stripe signature verification failed: %s", exc)
        raise HTTPException(status_code=400, detail="Invalid signature")

    event_type = event.get("type")
    event_object: Dict[str, Any] = event.get("data", {}).get("object", {})

    if event_type == "checkout.session.completed":
        subscription_id = event_object.get("subscription")
        subscription = _retrieve_subscription(subscription_id) if subscription_id else None
        uid = _extract_firebase_uid(event_object, subscription)
        if subscription_id and subscription and uid:
            _update_user_subscription(uid, subscription, subscription_id)
        else:
            logger.warning(
                "checkout.session.completed missing uid/subscription (uid=%s, subscription_id=%s)",
                uid,
                subscription_id,
            )

    elif event_type == "invoice.paid":
        subscription_id = event_object.get("subscription")
        subscription = _retrieve_subscription(subscription_id) if subscription_id else None
        uid = _extract_firebase_uid(event_object, subscription)
        if uid and subscription_id:
            _update_user_subscription(uid, subscription, subscription_id)
        else:
            logger.warning("invoice.paid missing uid/subscription (uid=%s, subscription_id=%s)", uid, subscription_id)

    elif event_type == "customer.subscription.updated":
        subscription = event_object
        subscription_id = subscription.get("id")
        uid = _extract_firebase_uid(event_object, subscription)
        if uid and subscription_id:
            _update_user_subscription(uid, subscription, subscription_id)
        else:
            logger.warning(
                "customer.subscription.updated missing uid/subscription (uid=%s, subscription_id=%s)",
                uid,
                subscription_id,
            )

    elif event_type == "customer.subscription.deleted":
        subscription = event_object
        subscription_id = subscription.get("id")
        uid = _extract_firebase_uid(event_object, subscription)
        if uid and subscription_id:
            _update_user_subscription(uid, subscription, subscription_id, status_override="canceled")
        else:
            logger.warning(
                "customer.subscription.deleted missing uid/subscription (uid=%s, subscription_id=%s)",
                uid,
                subscription_id,
            )

    else:
        logger.info("Unhandled Stripe event type: %s", event_type)

    return {"received": True}
