from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
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
    raise RuntimeError("STRIPE_SECRET_KEY environment variable is required for Stripe integration")
if not STRIPE_WEBHOOK_SECRET:
    raise RuntimeError("STRIPE_WEBHOOK_SECRET environment variable is required for Stripe webhooks")

stripe.api_key = STRIPE_SECRET_KEY

router = APIRouter()
db = get_firestore_client()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _timestamp_from_unix(value: Optional[int]) -> Optional[datetime]:
    if not value:
        return None
    return datetime.fromtimestamp(value, tz=timezone.utc)


def _retrieve_subscription(subscription_id: str) -> Optional[Dict[str, Any]]:
    if not subscription_id:
        return None
    try:
        sub = stripe.Subscription.retrieve(subscription_id)
        logger.info("Retrieved subscription %s (status=%s)", subscription_id, sub.get("status"))
        return sub
    except Exception as exc:
        logger.error("Failed to retrieve subscription %s: %s", subscription_id, exc)
        return None


def _extract_firebase_uid(obj: Dict[str, Any], subscription: Optional[Dict[str, Any]]) -> Optional[str]:
    """
    Try very hard to find Firebase UID:
    - checkout / subscription metadata.firebase_uid or .uid
    - client_reference_id
    - Stripe customer metadata.firebase_uid / .uid
    """
    # 1) From object metadata (checkout session, invoice, subscription, etc.)
    metadata = obj.get("metadata") or {}
    uid = metadata.get("firebase_uid") or metadata.get("uid")
    if uid:
        logger.info("UID from event.metadata: %s", uid)
        return uid

    # 2) From client_reference_id (if we set it during checkout session creation)
    client_ref = obj.get("client_reference_id")
    if client_ref:
        logger.info("UID from client_reference_id: %s", client_ref)
        return client_ref

    # 3) From subscription metadata (if present)
    if subscription:
        sub_metadata = subscription.get("metadata") or {}
        uid = sub_metadata.get("firebase_uid") or sub_metadata.get("uid")
        if uid:
            logger.info("UID from subscription.metadata: %s", uid)
            return uid

    # 4) From Stripe customer metadata
    customer_id = obj.get("customer") or obj.get("customer_id")
    if customer_id:
        try:
            customer = stripe.Customer.retrieve(customer_id)
            customer_meta = customer.get("metadata") or {}
            uid = customer_meta.get("firebase_uid") or customer_meta.get("uid")
            if uid:
                logger.info("UID from customer.metadata: %s", uid)
                return uid
        except Exception as exc:
            logger.error("Failed to load Stripe customer %s: %s", customer_id, exc)

    logger.warning("Could not extract Firebase UID from event")
    return None


def _lookup_plan_id_for_price(price_id: Optional[str]) -> Optional[str]:
    """
    Map Stripe price → Firestore plan document:
      collection: subscription_plans
      field: stripe_price_id
    """
    if not price_id:
        return None

    logger.info("Looking up plan for stripe_price_id=%s", price_id)
    plans_ref = (
        db.collection("subscription_plans")
        .where("stripe_price_id", "==", price_id)
        .limit(1)
    )
    docs = list(plans_ref.stream())
    if docs:
        plan_id = docs[0].id
        logger.info("Matched price %s to plan %s", price_id, plan_id)
        return plan_id

    logger.warning("No plan found in Firestore with stripe_price_id='%s'", price_id)
    return None


def _extract_price_and_product(subscription: Dict[str, Any]) -> Dict[str, Optional[str]]:
    """
    Try to extract price_id & product_id from Stripe subscription.
    """
    price_id: Optional[str] = None
    product_id: Optional[str] = None

    items = subscription.get("items", {}).get("data", []) if subscription else []
    if items:
        price = items[0].get("price") or {}
        price_id = price.get("id") or price.get("price_id")
        product_id = price.get("product")

    if not price_id and subscription:
        plan = subscription.get("plan") or {}
        price_id = plan.get("id") or plan.get("price_id")
        product_id = product_id or plan.get("product")

    return {"price_id": price_id, "product_id": product_id}


def _resolve_plan_and_price(
    subscription: Optional[Dict[str, Any]], price_id: Optional[str]
) -> Dict[str, Optional[str]]:
    """
    Combine:
      - checkout.metadata.price_id (if provided)
      - subscription.items[0].price.id
      - subscription.plan.id
    then map price → Firestore plan_id.
    """
    pricing = _extract_price_and_product(subscription or {})
    price_id = price_id or pricing.get("price_id")
    product_id = pricing.get("product_id")

    if not price_id:
        logger.warning("Cannot resolve price_id from subscription or checkout metadata")
        return {"price_id": None, "product_id": product_id, "plan_id": None}

    plan_id = _lookup_plan_id_for_price(price_id)
    return {"price_id": price_id, "product_id": product_id, "plan_id": plan_id}


def _ensure_usage_counters(existing_data: Dict[str, Any]) -> Dict[str, int]:
    """
    Guarantee we always have a usage_counters dict with at least 'transcriptions'.
    """
    usage = existing_data.get("usage_counters") or {}
    if not isinstance(usage, dict):
        usage = {}
    if "transcriptions" not in usage:
        usage["transcriptions"] = 0
    return usage


def _log_payment_for_checkout(
    uid: str,
    event_object: Dict[str, Any],
    plan_id: Optional[str],
    price_id: Optional[str],
) -> None:
    """
    Optional but useful: create a payments/ document per successful checkout.
    This feeds admin billing history instead of just aggregate revenue.
    """
    try:
        payments_ref = db.collection("payments").document()
        amount_total = event_object.get("amount_total") or 0
        currency = (event_object.get("currency") or "myr").upper()

        payments_ref.set(
            {
                "userId": uid,
                "planId": plan_id,
                "stripePriceId": price_id,
                "amount": amount_total / 100.0,
                "currency": currency,
                "status": "paid",
                "transactionId": event_object.get("id"),
                "createdAt": SERVER_TIMESTAMP,
            }
        )
        logger.info(
            "Logged payment: uid=%s plan_id=%s price_id=%s amount=%s %s",
            uid,
            plan_id,
            price_id,
            amount_total / 100.0,
            currency,
        )
    except Exception as exc:
        logger.error("Failed to log payment document: %s", exc)


def _update_user_subscription(
    uid: str,
    subscription: Optional[Dict[str, Any]],
    subscription_id: Optional[str],
    status_override: Optional[str] = None,
    checkout_price_id: Optional[str] = None,
    event_object: Optional[Dict[str, Any]] = None,
) -> None:
    """
    Update Firestore user_subscriptions/{uid} with:
      - plan_id
      - price_id
      - billing interval (month/year)
      - current period start/end
      - billing cycle anchor
      - usage counters preserved
    """
    if not uid:
        logger.error("Cannot update subscription: No UID provided")
        return

    subscription = subscription or {}

    # --- Extract billing interval first ---
    interval = None
    try:
        items = subscription.get("items", {}).get("data", [])
        if items:
            recurring = items[0].get("price", {}).get("recurring", {})
            interval = recurring.get("interval")
    except Exception as exc:
        logger.error("Error extracting interval: %s", exc)

    # --- Extract timestamps ---
    current_period_start = _timestamp_from_unix(subscription.get("current_period_start"))
    current_period_end = _timestamp_from_unix(subscription.get("current_period_end"))
    billing_cycle_anchor = _timestamp_from_unix(subscription.get("billing_cycle_anchor"))
    trial_end_at = _timestamp_from_unix(subscription.get("trial_end"))

    # --- Resolve plan & price ---
    pricing = _resolve_plan_and_price(subscription, checkout_price_id)
    price_id = pricing.get("price_id")
    product_id = pricing.get("product_id")
    plan_id = pricing.get("plan_id")

    status = status_override or subscription.get("status") or "active"

    # --- Load existing usage counters ---
    sub_ref = db.collection("user_subscriptions").document(uid)
    existing_doc = sub_ref.get()
    existing_data = existing_doc.to_dict() if existing_doc.exists else {}
    usage_counters = _ensure_usage_counters(existing_data)

    # --- Prepare Firestore update payload ---
    data: Dict[str, Any] = {
        "stripe_subscription_id": subscription_id or subscription.get("id"),
        "stripe_customer_id": subscription.get("customer") or subscription.get("customer_id"),
        "status": status,
        "trial_end_at": trial_end_at,
        "billing_interval": interval,
        "current_period_start": current_period_start,
        "current_period_end": current_period_end,
        "billing_cycle_anchor": billing_cycle_anchor,
        "is_trialing": subscription.get("status") == "trialing",
        "updatedAt": SERVER_TIMESTAMP,
        "usage_counters": usage_counters,
    }

    # Add mapping fields
    if plan_id:
        data["plan_id"] = plan_id
    if price_id:
        data["stripe_price_id"] = price_id
    if product_id:
        data["stripe_product_id"] = product_id

    # Fresh document?
    if not existing_doc.exists:
        data["createdAt"] = SERVER_TIMESTAMP

    # --- Commit to Firestore ---
    sub_ref.set(data, merge=True)

    logger.info(
        "Updated subscription for user %s (plan=%s interval=%s CPE=%s)",
        uid,
        plan_id,
        interval,
        current_period_end,
    )

    # --- Log payments if this is from checkout.session.completed ---
    if event_object is not None:
        _log_payment_for_checkout(uid, event_object, plan_id, price_id)


# ---------------------------------------------------------------------------
# Webhook endpoint
# ---------------------------------------------------------------------------

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
    event_object: Dict[str, Any] = event.get("data", {}).get("object", {}) or {}

    logger.info("Received Stripe event: %s", event_type)

    # 1) Checkout completed – main entry point for new subscriptions or plan changes
    if event_type == "checkout.session.completed":
        subscription_id = event_object.get("subscription")
        subscription = _retrieve_subscription(subscription_id) if subscription_id else None
        uid = _extract_firebase_uid(event_object, subscription)

        metadata = event_object.get("metadata") or {}
        checkout_price_id = metadata.get("price_id")

        logger.info(
            "Processing checkout.session.completed: uid=%s subscription_id=%s price_id=%s",
            uid,
            subscription_id,
            checkout_price_id,
        )

        if not uid:
            logger.warning("checkout.session.completed missing uid; skipping user_subscriptions update")
            return {"received": True}

        # Even if subscription retrieval fails, still create a minimal doc mapped by price_id.
        _update_user_subscription(
            uid=uid,
            subscription=subscription or {},
            subscription_id=subscription_id,
            status_override="active",
            checkout_price_id=checkout_price_id,
            event_object=event_object,
        )

    # 2) Recurring invoices paid – keep subscription info fresh
    elif event_type == "invoice.paid":
        subscription_id = event_object.get("subscription")

        if not subscription_id:
            subscription_id = (
                event_object.get("lines", {})
                .get("data", [{}])[0]
                .get("subscription")
            )

        subscription = _retrieve_subscription(subscription_id) if subscription_id else None
        uid = _extract_firebase_uid(event_object, subscription)

        logger.info("Processing invoice.paid: uid=%s subscription_id=%s", uid, subscription_id)

        if uid and subscription_id and subscription:
            _update_user_subscription(uid, subscription, subscription_id)
        else:
            logger.warning("invoice.paid missing uid or subscription -- attempting fallback")

            # FINAL FALLBACK: try retrieving customer's active subscription
            customer_id = event_object.get("customer")
            if customer_id:
                try:
                    subs = stripe.Subscription.list(customer=customer_id, status="active")
                    if subs.data:
                        subscription = subs.data[0]
                        subscription_id = subscription.get("id")
                        uid = _extract_firebase_uid(event_object, subscription)

                        _update_user_subscription(uid, subscription, subscription_id)
                except Exception as e:
                    logger.error("Failed fallback subscription lookup: %s", e)

    # 3) Subscription created/updated – plan upgrades/downgrades
    elif event_type in {"customer.subscription.updated", "customer.subscription.created"}:
        subscription = event_object
        subscription_id = subscription.get("id")
        uid = _extract_firebase_uid(event_object, subscription)

        logger.info(
            "Processing %s: uid=%s subscription_id=%s status=%s",
            event_type,
            uid,
            subscription_id,
            subscription.get("status"),
        )

        if uid and subscription_id:
            _update_user_subscription(uid, subscription, subscription_id)
        else:
            logger.warning("%s missing uid or subscription_id", event_type)

    # 4) Subscription canceled
    elif event_type == "customer.subscription.deleted":
        subscription = event_object
        subscription_id = subscription.get("id")
        uid = _extract_firebase_uid(event_object, subscription)

        logger.info(
            "Processing customer.subscription.deleted: uid=%s subscription_id=%s",
            uid,
            subscription_id,
        )

        if uid and subscription_id:
            _update_user_subscription(
                uid,
                subscription,
                subscription_id,
                status_override="canceled",
            )
        else:
            logger.warning("customer.subscription.deleted missing uid or subscription_id")

    else:
        # Ignore other events but still acknowledge
        logger.info("Unhandled Stripe event type: %s", event_type)

    return {"received": True}