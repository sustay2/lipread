# Lipreading Admin Monorepo (FastAPI + Streamlit)

## Dev setup
1. Python 3.11 and Docker installed
2. Copy backend/.env.example to backend/.env and fill Firebase + MEDIA_ROOT
3. Create admin/.streamlit/secrets.toml from secrets.example.toml
4. Install deps: `pip install -r requirements.txt`
5. Run locally without Docker:
   - API: `uvicorn app.main:app --reload --port 8000` (from backend/)
   - Admin: `streamlit run app.py` (from admin/)
6. Or with Docker: `powershell -ExecutionPolicy Bypass -File .\scripts\dev_up.ps1`
7. To close Docker: `powershell -ExecutionPolicy Bypass -File .\scripts\dev_down.ps1`

## Notes
- Media is stored locally under `data/` and served at `/media/*`.
- All admin writes go through FastAPI; Firestore direct writes from clients are blocked by rules.