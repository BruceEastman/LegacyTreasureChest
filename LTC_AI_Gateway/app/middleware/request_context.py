from __future__ import annotations

import time
from typing import Callable

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

from app.core.config import (
    ANALYZE_PER_MINUTE_LIMIT,
    AI_PER_DAY_LIMIT,
    AI_PER_MINUTE_LIMIT,
    DISABLE_ALL_AI,
)
from app.core.errors import make_error_envelope
from app.core.rate_limiter import rate_limiter
from app.core.request_id import (
    DEVICE_ID_HEADER,
    REQUEST_ID_HEADER,
    get_device_id,
    get_or_create_request_id,
)
from app.core.safe_logging import get_logger, log_event

logger = get_logger(__name__)


class RequestContextMiddleware(BaseHTTPMiddleware):
    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)

    async def dispatch(self, request: Request, call_next: Callable):
        request_id = get_or_create_request_id(request)
        device_id = get_device_id(request)

        request.state.request_id = request_id
        request.state.device_id = device_id

        start = time.perf_counter()
        path = request.url.path

        # -----------------------
        # Kill Switch: All AI
        # -----------------------
        if DISABLE_ALL_AI and path.startswith("/ai"):
            return JSONResponse(
                status_code=503,
                content=make_error_envelope(
                    code="SERVICE_UNAVAILABLE",
                    message="AI services temporarily disabled.",
                    request_id=request_id,
                    status=503,
                ),
            )

        # -----------------------
        # Rate limiting
        # -----------------------
        if path.endswith("/analyze-item-photo"):
            allowed, retry = rate_limiter.check(
                device_id=device_id,
                scope="analyze-item-photo",
                limit=ANALYZE_PER_MINUTE_LIMIT,
                window_seconds=60,
            )
            if not allowed:
                return JSONResponse(
                    status_code=429,
                    content=make_error_envelope(
                        code="RATE_LIMITED",
                        message="Too many analyze requests.",
                        request_id=request_id,
                        status=429,
                        details={"retryAfterSeconds": retry},
                    ),
                )

        if path.startswith("/ai"):
            allowed, retry = rate_limiter.check(
                device_id=device_id,
                scope="ai-global-minute",
                limit=AI_PER_MINUTE_LIMIT,
                window_seconds=60,
            )
            if not allowed:
                return JSONResponse(
                    status_code=429,
                    content=make_error_envelope(
                        code="RATE_LIMITED",
                        message="Too many AI requests.",
                        request_id=request_id,
                        status=429,
                        details={"retryAfterSeconds": retry},
                    ),
                )

            allowed_daily, retry_daily = rate_limiter.check_daily(
                device_id=device_id,
                scope="ai-global-daily",
                limit=AI_PER_DAY_LIMIT,
            )
            if not allowed_daily:
                return JSONResponse(
                    status_code=429,
                    content=make_error_envelope(
                        code="RATE_LIMITED",
                        message="Daily AI limit reached.",
                        request_id=request_id,
                        status=429,
                        details={"retryAfterSeconds": retry_daily},
                    ),
                )

        # -----------------------
        # Logging start
        # -----------------------
        log_event(
            logger,
            level=20,
            event="request.start",
            request_id=request_id,
            device_id=device_id,
            fields={"method": request.method, "path": path},
        )

        response = await call_next(request)

        elapsed_ms = int((time.perf_counter() - start) * 1000)

        response.headers[REQUEST_ID_HEADER] = request_id
        response.headers[DEVICE_ID_HEADER] = device_id

        log_event(
            logger,
            level=20,
            event="request.end",
            request_id=request_id,
            device_id=device_id,
            fields={
                "method": request.method,
                "path": path,
                "status": response.status_code,
                "elapsedMs": elapsed_ms,
            },
        )

        return response