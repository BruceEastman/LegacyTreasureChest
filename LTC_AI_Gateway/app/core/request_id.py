from __future__ import annotations

from uuid import uuid4

from fastapi import Request


REQUEST_ID_HEADER = "X-Request-ID"
DEVICE_ID_HEADER = "X-LTC-Device-ID"


def get_or_create_request_id(request: Request) -> str:
    existing = request.headers.get(REQUEST_ID_HEADER)
    if existing and len(existing) <= 128:
        return existing
    return str(uuid4())


def get_device_id(request: Request) -> str:
    # Do not validate heavily yet; just keep it bounded and log-safe.
    # Rate limiting will rely on this later.
    device_id = request.headers.get(DEVICE_ID_HEADER, "").strip()
    if not device_id:
        return "unknown"
    return device_id[:128]