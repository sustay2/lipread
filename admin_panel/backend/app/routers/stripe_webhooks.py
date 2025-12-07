from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

import stripe
from fastapi import APIRouter, HTTPException, Request
from google.cloud.firestore_v1 import SERVER_TIMESTAMP

from app.services.firebase_client import get_firestore_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("stripe_webhook")

STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY")
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET")

if not STRIPE_SECRET_KEY:
    raise RuntimeError("STRIPE_SECRET_KEY must be set")
if not STRIPE_WEBHOOK_SECRET:
    raise RuntimeError("STRIPE_WEBHOOK_SECRET must be set")

stripe.api_key = STRIPE_SECRET_KEY

router = APIRouter()
db = get_firestore_client()


# ============================================================
# Helpers
# ============================================================

def _timestamp_from_unix(value: Optional[int]) -> Optional[datetime]:
    if not value:
        return None
    return datetime.fromtimestamp(int(value), tz=timezone.utc)


def _retrieve_subscription(subscription_id: str) -> Optional[Dict[str, Any]]:
    """
    Retrieve subscription with expanded price, invoice, and item data.
    Required for correct billing cycle extraction.
    """
    if not subscription_id:
        return None
    try:
        sub = stripe.Subscription.retrieve(
            subscription_id,
            expand=[
                "items.data.price",
                "latest_invoice",
                "plan",
            ]
        )
        logger.info("Retrieved subscription %s", subscription_id)
        return sub
    except Exception as exc:
        logger.error("Failed retrieving subscription %s: %s", subscription_id, exc)
        return None


def _extract_firebase_uid(obj: Dict[str, Any], subscription: Optional[Dict[str, Any]]) -> Optional[str]:
    """Try multiple sources to extract firebase_uid."""
    # 1) event metadata
    metadata = obj.get("metadata") or {}
    uid = metadata.get("firebase_uid") or metadata.get("uid")
    if uid:
        return uid

    # 2) client_reference_id (checkout)
    if obj.get("client_reference_id"):
        return obj["client_reference_id"]

    # 3) subscription metadata
    if subscription:
        meta = subscription.get("metadata") or {}
        uid = meta.get("firebase_uid") or meta.get("uid")
        if uid:
            return uid

    # 4) customer metadata
    customer_id = (
        obj.get("customer")
        or obj.get("customer_id")
        or (subscription or {}).get("customer")
    )

    if customer_id:
        try:
            customer = stripe.Customer.retrieve(customer_id)
            cust_meta = customer.get("metadata") or {}
            uid = cust_meta.get("firebase_uid") or cust_meta.get("uid")
            if uid:
                return uid
        except Exception as exc:
            logger.error("Failed loading Stripe customer %s: %s", customer_id, exc)

    logger.warning("Could not extract UID for event")
    return None


def _lookup_plan(price_id: Optional[str]) -> Dict[str, Any]:
    """
    Returns Firestore plan document including trial_period_days (if exists).
    """
    if not price_id:
        return {}

    query = (
        db.collection("subscription_plans")
        .where("stripe_price_id", "==", price_id)
        .limit(1)
    )
    docs = list(query.stream())
    if docs:
        plan = docs[0].to_dict()
        plan["id"] = docs[0].id
        return plan

    logger.warning("No plan found for price_id=%s", price_id)
    return {}


def _extract_price(subscription: Dict[str, Any]) -> Optional[str]:
    """Extract price from subscription.items → fallback to subscription.plan."""
    items = subscription.get("items", {}).get("data", [])
    if items:
        price = items[0].get("price") or {}
        return price.get("id")
    plan = subscription.get("plan") or {}
    return plan.get("id")


def _ensure_usage(existing: Dict[str, Any]) -> Dict[str, int]:
    usage = existing.get("usage_counters") or {}
    if "transcriptions" not in usage:
        usage["transcriptions"] = 0
    return usage


def _fallback_periods(uid: str, price_id: str, subscription: Dict[str, Any]) -> Dict[str, datetime]:
    """
    NEW LOGIC:
    If Stripe does NOT return proper period dates, fallback:
    - First-time purchase → Firestore trial_period_days (if any)
    - Otherwise → +30 days from now
    """

    now = datetime.now(tz=timezone.utc)

    plan = _lookup_plan(price_id)
    trial_days = int(plan.get("trial_period_days", 0))

    logger.warning(
        "Applying fallback billing periods for uid=%s (trial_days=%s)",
        uid, trial_days,
    )

    # This subscription already has trial_end? Stop.
    if subscription.get("trial_end"):
        return {}

    # Determine if user already has a subscription document
    sub_doc = db.collection("user_subscriptions").document(uid).get()
    first_time_purchase = not sub_doc.exists

    if first_time_purchase and trial_days > 0:
        return {
            "current_period_start": now,
            "current_period_end": now + timedelta(days=trial_days),
            "trial_end": now + timedelta(days=trial_days),
        }

    # Normal fallback: 30-day month
    return {
        "current_period_start": now,
        "current_period_end": now + timedelta(days=30),
        "trial_end": None,
    }


def _log_payment(uid: str, obj: Dict[str, Any], plan_id: Optional[str], price_id: Optional[str]):
    try:
        db.collection("payments").document().set({
            "userId": uid,
            "planId": plan_id,
            "stripePriceId": price_id,
            "amount": (obj.get("amount_total") or 0) / 100.0,
            "currency": (obj.get("currency") or "myr").upper(),
            "transactionId": obj.get("id"),
            "status": "paid",
            "createdAt": SERVER_TIMESTAMP,
        })
    except Exception as exc:
        logger.error("Failed logging payment: %s", exc)


# ============================================================
# Main Firestore write logic
# ============================================================

def _update_user_subscription(
    uid: str,
    subscription: Dict[str, Any],
    subscription_id: str,
    *,
    checkout_price_id: Optional[str] = None,
    status_override: Optional[str] = None,
    event_object: Optional[Dict[str, Any]] = None,
):
    price_id = checkout_price_id or _extract_price(subscription)
    plan = _lookup_plan(price_id)
    plan_id = plan.get("id")

    # Extract official dates
    c_start = _timestamp_from_unix(subscription.get("current_period_start"))
    c_end = _timestamp_from_unix(subscription.get("current_period_end"))
    trial_end = _timestamp_from_unix(subscription.get("trial_end"))
    anchor = _timestamp_from_unix(subscription.get("billing_cycle_anchor"))

    # Apply fallback if Stripe missing data
    if not c_start or not c_end:
        fallback = _fallback_periods(uid, price_id, subscription)
        c_start = c_start or fallback.get("current_period_start")
        c_end = c_end or fallback.get("current_period_end")
        trial_end = trial_end or fallback.get("trial_end")

    # Billing interval
    interval = None
    try:
        items = subscription.get("items", {}).get("data", [])
        if items:
            interval = items[0]["price"]["recurring"]["interval"]
    except Exception:
        pass

    sub_ref = db.collection("user_subscriptions").document(uid)
    existing = sub_ref.get().to_dict() or {}
    usage = _ensure_usage(existing)

    data = {
        "stripe_subscription_id": subscription_id,
        "stripe_customer_id": subscription.get("customer"),
        "status": status_override or subscription.get("status") or "active",
        "billing_interval": interval,
        "current_period_start": c_start,
        "current_period_end": c_end,
        "billing_cycle_anchor": anchor,
        "trial_end_at": trial_end,
        "plan_id": plan_id,
        "stripe_price_id": price_id,
        "stripe_product_id": subscription.get("plan", {}).get("product"),
        "is_trialing": subscription.get("status") == "trialing",
        "usage_counters": usage,
        "updatedAt": SERVER_TIMESTAMP,
    }

    if not existing:
        data["createdAt"] = SERVER_TIMESTAMP

    sub_ref.set(data, merge=True)
    logger.info("Updated user subscription for uid=%s", uid)

    if event_object is not None:
        _log_payment(uid, event_object, plan_id, price_id)


# ============================================================
# Webhook Endpoint
# ============================================================

@router.post("/webhook")
async def stripe_webhook(request: Request) -> Dict[str, bool]:
    payload = await request.body()
    sig = request.headers.get("stripe-signature")

    try:
        event = stripe.Webhook.construct_event(payload, sig, STRIPE_WEBHOOK_SECRET)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    event_type = event["type"]
    obj = event["data"]["object"]

    logger.info("Stripe → %s", event_type)

    # ---------------------------------------------------------
    # checkout.session.completed
    # ---------------------------------------------------------
    if event_type == "checkout.session.completed":
        subscription_id = obj.get("subscription")
        subscription = _retrieve_subscription(subscription_id)
        uid = _extract_firebase_uid(obj, subscription)

        if not uid:
            logger.warning("Checkout completed but no UID found.")
            return {"received": True}

        if subscription is None:
            logger.warning("Subscription not fully ready — invoice.paid will update billing periods.")
            return {"received": True}

        _update_user_subscription(
            uid=uid,
            subscription=subscription,
            subscription_id=subscription_id,
            checkout_price_id=obj.get("metadata", {}).get("price_id"),
            status_override="active",
            event_object=obj,
        )
        return {"received": True}

    # ---------------------------------------------------------
    # invoice.paid / invoice.finalized / invoice.payment_succeeded
    # ---------------------------------------------------------
    if event_type in {"invoice.paid", "invoice.finalized", "invoice.payment_succeeded"}:
        subscription_id = obj.get("subscription")

        # fallback through invoice lines
        if not subscription_id:
            for line in obj.get("lines", {}).get("data", []):
                if line.get("subscription"):
                    subscription_id = line["subscription"]
                    break

        subscription = _retrieve_subscription(subscription_id)
        uid = _extract_firebase_uid(obj, subscription)

        if uid and subscription:
            _update_user_subscription(uid, subscription, subscription_id)
        else:
            logger.warning("Invoice event missing UID or subscription.")
        return {"received": True}

    # ---------------------------------------------------------
    # subscription updated/created
    # ---------------------------------------------------------
    if event_type in {"customer.subscription.created", "customer.subscription.updated"}:
        subscription = obj
        subscription_id = subscription.get("id")
        full = _retrieve_subscription(subscription_id)
        uid = _extract_firebase_uid(obj, full)

        if uid and full:
            _update_user_subscription(uid, full, subscription_id)
        return {"received": True}

    # ---------------------------------------------------------
    # subscription deleted
    # ---------------------------------------------------------
    if event_type == "customer.subscription.deleted":
        subscription = obj
        subscription_id = subscription.get("id")
        uid = _extract_firebase_uid(obj, subscription)

        if uid:
            _update_user_subscription(
                uid,
                subscription,
                subscription_id,
                status_override="canceled",
            )
        return {"received": True}

    logger.info("Ignoring event %s", event_type)
    return {"received": True}