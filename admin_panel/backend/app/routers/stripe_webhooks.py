from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
from typing import Any, Dict, Optional

import stripe
from fastapi import APIRouter, HTTPException, Request
from google.cloud.firestore_v1 import SERVER_TIMESTAMP

from app.services.firebase_client import get_firestore_client

# Configure logging to show up in your terminal
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("stripe_webhook")

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
    except Exception as exc:
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

    customer_id = obj.get("customer") or obj.get("customer_id")
    if customer_id:
        try:
            customer = stripe.Customer.retrieve(customer_id)
            customer_meta = customer.get("metadata") or {}
            return customer_meta.get("firebase_uid")
        except Exception as exc:
            logger.error("Failed to load Stripe customer %s: %s", customer_id, exc)
    return None


def _lookup_plan_id_for_price(price_id: Optional[str]) -> Optional[str]:
    if not price_id:
        return None

    plans_ref = db.collection("subscription_plans").where("stripe_price_id", "==", price_id).limit(1)
    docs = list(plans_ref.stream())
    if docs:
        return docs[0].id

    logger.warning("No plan found in Firestore with stripe_price_id='%s'", price_id)
    return None


def _update_user_subscription(
    uid: str, subscription: Optional[Dict[str, Any]], subscription_id: Optional[str], status_override: Optional[str] = None
) -> None:
    if not uid:
        logger.error("Cannot update subscription: No UID provided")
        return

    subscription = subscription or {}
    
    # Extract price_id to find the corresponding internal Plan ID
    plan_id = None
    price_id = None

    if subscription:
        items = subscription.get("items", {}).get("data", [])
        if items:
            price_id = items[0].get("price", {}).get("id")
        else:
            logger.warning("Subscription has no items.")

    plan_id = _lookup_plan_id_for_price(price_id)
    if plan_id:
        logger.info("Resolved plan %s for price %s", plan_id, price_id)

    data: Dict[str, Any] = {
        "stripe_subscription_id": subscription_id or subscription.get("id"),
        "status": status_override or subscription.get("status"),
        "stripe_customer_id": subscription.get("customer") or subscription.get("customer_id"),
        "trial_end_at": _timestamp_from_unix(subscription.get("trial_end")),
        "current_period_end": _timestamp_from_unix(subscription.get("current_period_end")),
        "is_trialing": subscription.get("status") == "trialing",
        "updatedAt": SERVER_TIMESTAMP,
    }
    
    if plan_id:
        data["plan_id"] = plan_id
    else:
        # If we can't find the plan, we might want to log this specifically
        logger.error(f"Updating user {uid} subscription WITHOUT plan_id. Status: {data['status']}")

    sub_ref = db.collection("user_subscriptions").document(uid)
    if not sub_ref.get().exists:
        data["createdAt"] = SERVER_TIMESTAMP

    sub_ref.set(data, merge=True)
    logger.info(f"Successfully updated subscription for user {uid}")


@router.post("/webhook")
async def handle_stripe_webhook(request: Request) -> Dict[str, bool]:
    payload = await request.body()
    sig_header = request.headers.get("stripe-signature")

    try:
        event = stripe.Webhook.construct_event(payload, sig_header, STRIPE_WEBHOOK_SECRET)
    except ValueError as exc:
        logger.error("Invalid payload: %s", exc)
        raise HTTPException(status_code=400, detail="Invalid payload")
    except stripe.error.SignatureVerificationError as exc:
        logger.error("Invalid signature: %s", exc)
        raise HTTPException(status_code=400, detail="Invalid signature")

    event_type = event.get("type")
    event_object: Dict[str, Any] = event.get("data", {}).get("object", {})
    
    logger.info(f"Received Stripe event: {event_type}")

    if event_type == "checkout.session.completed":
        subscription_id = event_object.get("subscription")
        subscription = _retrieve_subscription(subscription_id) if subscription_id else None
        uid = _extract_firebase_uid(event_object, subscription)
        
        logger.info(f"Processing checkout.session.completed for uid: {uid}, sub: {subscription_id}")
        
        if subscription_id and subscription and uid:
            _update_user_subscription(uid, subscription, subscription_id)
        else:
            logger.warning("Missing data for checkout completion")

    elif event_type == "invoice.paid":
        subscription_id = event_object.get("subscription")
        subscription = _retrieve_subscription(subscription_id) if subscription_id else None
        uid = _extract_firebase_uid(event_object, subscription)
        if uid and subscription_id:
            _update_user_subscription(uid, subscription, subscription_id)

    elif event_type in {"customer.subscription.updated", "customer.subscription.created"}:
        subscription = event_object
        subscription_id = subscription.get("id")
        uid = _extract_firebase_uid(event_object, subscription)
        if uid and subscription_id:
            _update_user_subscription(uid, subscription, subscription_id)

    elif event_type == "customer.subscription.deleted":
        subscription = event_object
        subscription_id = subscription.get("id")
        uid = _extract_firebase_uid(event_object, subscription)
        if uid and subscription_id:
            _update_user_subscription(uid, subscription, subscription_id, status_override="canceled")

    return {"received": True}
