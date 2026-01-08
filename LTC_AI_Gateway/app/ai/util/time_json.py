# app/ai/util/time_json.py

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any


def _now_iso_z() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _parse_llm_json_obj(raw_json: str) -> Any:
    """
    Parse cleaned LLM JSON into Python. Raises ValueError on failure.
    Assumes clean_llm_json already stripped fences, etc.
    """
    return json.loads(raw_json)


def _unwrap_singleton_wrapper(obj: Any) -> Any:
    """
    If obj is {"SomeWrapper": {...}} return the inner dict.
    Handles the known wrapper case: {"LiquidationBriefDTO": {...}} etc.
    """
    if not isinstance(obj, dict):
        return obj

    if len(obj) != 1:
        return obj

    (k, v), = obj.items()
    if isinstance(v, dict):
        # Common wrappers we have seen from LLMs
        known_wrappers = {
            "LiquidationBriefDTO",
            "LiquidationPlanChecklistDTO",
            "LiquidationPlanDTO",
            "brief",
            "plan",
            "data",
            "result",
            "response",
            "output",
        }
        if k in known_wrappers or k.endswith("DTO"):
            return v

    return obj
