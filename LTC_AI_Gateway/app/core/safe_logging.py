from __future__ import annotations

import json
import logging
from typing import Any, Dict, Optional


def get_logger(name: str = "ltc_ai_gateway") -> logging.Logger:
    return logging.getLogger(name)


def log_event(
    logger: logging.Logger,
    *,
    level: int,
    event: str,
    request_id: Optional[str] = None,
    device_id: Optional[str] = None,
    fields: Optional[Dict[str, Any]] = None,
) -> None:
    """
    Emit a single structured log line.
    IMPORTANT: Do not include request bodies, base64, or secrets in fields.
    """
    payload: Dict[str, Any] = {"event": event}
    if request_id:
        payload["requestId"] = request_id
    if device_id:
        payload["deviceId"] = device_id
    if fields:
        payload.update(fields)

    # JSON line logging plays well with Cloud Run logs.
    msg = json.dumps(payload, ensure_ascii=False, default=str)
    logger.log(level, msg)