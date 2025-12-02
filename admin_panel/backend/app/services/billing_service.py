"""Stripe billing utilities for subscription checkout and portal access."""
from __future__ import annotations

import os
from typing import Any, Dict, Optional

import stripe

STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY")
if not STRIPE_SECRET_KEY:
    raise RuntimeError("STRIPE_SECRET_KEY environment variable is required for Stripe integration")

stripe.api_key = STRIPE_SECRET_KEY
STRIPE_DEFAULT_CURRENCY = os.getenv("STRIPE_DEFAULT_CURRENCY", "myr")


def _serialize_customer(customer: Any) -> Dict[str, Any]:
    return {
        "id": customer["id"],
        "email": customer.get("email"),
        "metadata": dict(customer.get("metadata") or {}),
    }


def create_stripe_customer(firebase_uid: str, email: str) -> Dict[str, Any]:
    """Create a Stripe Customer with Firebase UID stored in metadata."""

    customer = stripe.Customer.create(email=email, metadata={"firebase_uid": firebase_uid})
    return _serialize_customer(customer)


def _find_customer_by_uid(firebase_uid: str) -> Optional[Dict[str, Any]]:
    """Attempt to locate an existing customer via metadata search."""

    try:
        search = stripe.Customer.search(
            query=f"metadata['firebase_uid']:'{firebase_uid}'",
            limit=1,
        )
        if search.get("data"):
            return _serialize_customer(search["data"][0])
    except stripe.error.InvalidRequestError:
        # Customer search may be disabled; fall back to email lookup in caller.
        return None
    return None


def get_or_create_stripe_customer(firebase_uid: str, email: str) -> Dict[str, Any]:
    """Return an existing Stripe customer or create a new one if none is found."""

    customer = _find_customer_by_uid(firebase_uid)
    if customer:
        return customer

    # Fallback: try matching by email if search is unavailable
    customers = stripe.Customer.list(email=email, limit=1)
    if customers.get("data"):
        return _serialize_customer(customers["data"][0])

    return create_stripe_customer(firebase_uid, email)


def create_checkout_session(
    firebase_uid: str, price_id: str, success_url: str, cancel_url: str, email: Optional[str] = None
) -> Dict[str, Any]:
    """Create a subscription checkout session for the given Stripe price."""

    # Email is optional for caller convenience; reuse Firebase UID metadata when creating customers.
    customer = get_or_create_stripe_customer(firebase_uid=firebase_uid, email=email or "")

    session = stripe.checkout.Session.create(
        mode="subscription",
        customer=customer["id"],
        currency=STRIPE_DEFAULT_CURRENCY,
        line_items=[{"price": price_id, "quantity": 1}],
        success_url=success_url,
        cancel_url=cancel_url,
        metadata={"firebase_uid": firebase_uid},
        subscription_data={"metadata": {"firebase_uid": firebase_uid}},
    )

    return {
        "id": session["id"],
        "url": session.get("url"),
        "customer_id": customer["id"],
        "subscription_mode": session.get("mode"),
    }


def create_billing_portal_session(stripe_customer_id: str, return_url: str) -> Dict[str, Any]:
    """Create a billing portal session for card and subscription management."""

    portal_session = stripe.billing_portal.Session.create(
        customer=stripe_customer_id,
        return_url=return_url,
    )

    return {
        "id": portal_session["id"],
        "url": portal_session.get("url"),
        "customer_id": stripe_customer_id,
    }
