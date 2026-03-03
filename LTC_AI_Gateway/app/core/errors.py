from __future__ import annotations

from typing import Any, Dict, Optional

from pydantic import BaseModel


class ErrorBody(BaseModel):
    code: str
    message: str
    requestId: str
    status: int
    details: Optional[Dict[str, Any]] = None


class ErrorEnvelope(BaseModel):
    error: ErrorBody


def make_error_envelope(
    *,
    code: str,
    message: str,
    request_id: str,
    status: int,
    details: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Returns a plain dict suitable for JSONResponse(content=...).
    """
    env = ErrorEnvelope(
        error=ErrorBody(
            code=code,
            message=message,
            requestId=request_id,
            status=status,
            details=details,
        )
    )
    return env.model_dump(exclude_none=True)


def code_for_status(status: int) -> str:
    if status == 400:
        return "BAD_REQUEST"
    if status == 401:
        return "UNAUTHORIZED"
    if status == 403:
        return "FORBIDDEN"
    if status == 404:
        return "NOT_FOUND"
    if status == 409:
        return "CONFLICT"
    if status == 422:
        return "VALIDATION_ERROR"
    if status == 429:
        return "RATE_LIMITED"
    if status == 503:
        return "SERVICE_UNAVAILABLE"
    if 500 <= status <= 599:
        return "UPSTREAM_ERROR"
    return "ERROR"