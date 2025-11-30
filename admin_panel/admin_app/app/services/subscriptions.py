from typing import Any, Dict, List


class SubscriptionService:
    def __init__(self):
        self.plans = [
            {"id": "basic", "name": "Basic", "price": 9.99, "cycle": "monthly", "features": ["Core lessons"]},
            {
                "id": "pro",
                "name": "Pro",
                "price": 19.99,
                "cycle": "monthly",
                "features": ["Full library", "Advanced analytics"],
            },
        ]

    def list_plans(self) -> List[Dict[str, Any]]:
        return self.plans

    def get_payments(self) -> List[Dict[str, Any]]:
        return [
            {
                "user": "learner@example.com",
                "plan": "Pro",
                "amount": "$19.99",
                "date": "2024-11-01",
                "status": "success",
                "transaction_id": "txn_123",
            },
            {
                "user": "trial@example.com",
                "plan": "Basic",
                "amount": "$0.00",
                "date": "2024-11-03",
                "status": "failed",
                "transaction_id": "txn_124",
            },
        ]

    def list_billing_history(self, user_id: str) -> List[Dict[str, Any]]:
        return [
            {"plan": "Pro", "amount": "$19.99", "date": "2024-11-01", "status": "success"},
            {"plan": "Pro", "amount": "$19.99", "date": "2024-10-01", "status": "success"},
        ]
