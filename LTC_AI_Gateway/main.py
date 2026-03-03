from __future__ import annotations

import logging

from dotenv import load_dotenv
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.errors import code_for_status, make_error_envelope
from app.middleware.request_context import RequestContextMiddleware
from app.routes.analyze_item_photo import router as analyze_item_photo_router

# Load environment variables from .env as early as possible (process startup).
# This ensures ALL modules (Gemini, Google Places, etc.) see the same environment.
load_dotenv()

# Basic logging configuration (Cloud Run will capture stdout/stderr).
logging.basicConfig(level=logging.INFO)

app = FastAPI(
    title="Legacy Treasure Chest AI Gateway",
    description="AI backend for item photo analysis and related tasks.",
    version="0.1.0",
)

# Middleware: requestId + safe structured logging
app.add_middleware(RequestContextMiddleware)

# CORS – fine for iOS, we can tighten later if needed.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -------------------------
# Global error handling
# -------------------------

def _request_id_from_request(request: Request) -> str:
    rid = getattr(request.state, "request_id", None)
    return rid or "unknown"


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    request_id = _request_id_from_request(request)
    status = int(getattr(exc, "status_code", 500))

    # IMPORTANT:
    # - For 5xx, do NOT expose exc.detail (may include upstream/internal messages).
    # - For 4xx, it's generally safe to return the detail as a user-facing message.
    if 500 <= status <= 599:
        message = "Upstream service error."
        details = None
    else:
        message = str(getattr(exc, "detail", "Request error."))
        details = None

    return JSONResponse(
        status_code=status,
        content=make_error_envelope(
            code=code_for_status(status),
            message=message,
            request_id=request_id,
            status=status,
            details=details,
        ),
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    request_id = _request_id_from_request(request)
    status = 422

    # Keep details minimal and safe; no raw payload echo.
    # Pydantic error structure is usually safe, but can be verbose — we keep it bounded.
    errs = exc.errors()
    safe_errs = errs[:10]

    return JSONResponse(
        status_code=status,
        content=make_error_envelope(
            code=code_for_status(status),
            message="Validation error.",
            request_id=request_id,
            status=status,
            details={"errors": safe_errs},
        ),
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    request_id = _request_id_from_request(request)
    status = 500

    # Never leak exception detail to the client.
    return JSONResponse(
        status_code=status,
        content=make_error_envelope(
            code=code_for_status(status),
            message="Internal server error.",
            request_id=request_id,
            status=status,
        ),
    )

# -------------------------
# Routes
# -------------------------

app.include_router(analyze_item_photo_router)


@app.get("/health")
async def health() -> dict:
    # No upstream calls. Cloud Run / load balancer health check safe.
    return {"status": "ok"}