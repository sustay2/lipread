from __future__ import annotations

from fastapi import Depends, HTTPException, Request, status


async def require_admin_session(request: Request):
    admin = request.session.get("admin") if request.session else None
    if not admin:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Login required")
    return admin


def current_admin(request: Request = Depends(require_admin_session)):
    return request.session.get("admin")
