# Lipread Admin Panel (FastAPI + Bootstrap)

This admin experience replaces the prior Streamlit UI with a FastAPI application that renders Bootstrap 5 templates through Jinja2. Uvicorn serves the app, Firebase remains the identity and storage layer, and the existing admin API continues to provide data.

## Architecture
- **FastAPI app (`app/`)** – routers/controllers for each admin area, wired to Jinja2 templates and JSON endpoints.
- **Service layer (`app/services/`)** – backend/Firebase/Stripe accessors (`BackendClient`, `FirebaseAuthService`, `SubscriptionService`, `ReportService`).
- **Presentation layer (`app/templates/`)** – Bootstrap 5 pages for dashboard, users, progress, engagement, courses/modules/lessons/activities, analytics, reports, and subscriptions.
- **Static assets (`app/static/`)** – shared CSS overrides.
- **Container (`Dockerfile`)** – runs `uvicorn app.main:app`.

## Folder structure
```
admin_panel/admin_app/
├── Dockerfile
├── README.md
└── app/
    ├── config.py                # environment + Firebase/Stripe settings
    ├── main.py                  # FastAPI app factory + router wiring
    ├── routers/                 # dashboard, users, content, analytics, billing
    ├── services/                # backend API client + Firebase/Stripe/report helpers
    ├── static/                  # Bootstrap overrides
    └── templates/               # Bootstrap 5 + Jinja2 admin pages
```

## Running locally
```bash
uvicorn app.main:app --reload --port 8501
```

Point `LIPREAD_ADMIN_API_BASE_URL` to your admin API to drive live data. The UI falls back to demo data when the API is unreachable.
