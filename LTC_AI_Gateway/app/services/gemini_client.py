from __future__ import annotations

import logging
import os
import re
from typing import Any, Dict, Optional

import httpx
from dotenv import load_dotenv

from app.utils.json_cleaner import clean_llm_json

load_dotenv()

logger = logging.getLogger(__name__)


def _sanitize_env(name: str, value: Optional[str]) -> str:
    """
    Secrets/env vars sometimes include trailing newlines (common with Secret Manager or copy/paste),
    or (more rarely) stray control characters like \\r embedded in the value.

    Normalize safely:
      - strip leading/trailing whitespace
      - remove common control chars anywhere: \\r, \\n, \\t
      - reject any remaining non-printable ASCII/control chars
    """
    v = (value or "")
    if not v:
        return ""

    v = v.strip()
    v = v.replace("\r", "").replace("\n", "").replace("\t", "")

    if not v:
        return ""

    # Reject remaining control chars: 0x00-0x1F and 0x7F
    if re.search(r"[\x00-\x1F\x7F]", v):
        raise RuntimeError(f"{name} contains non-printable control characters after normalization.")

    return v


GEMINI_API_KEY = _sanitize_env("GEMINI_API_KEY", os.getenv("GEMINI_API_KEY"))
GEMINI_MODEL = _sanitize_env("GEMINI_MODEL", os.getenv("GEMINI_MODEL", "gemini-2.5-flash"))

if not GEMINI_API_KEY:
    raise RuntimeError("GEMINI_API_KEY is not set in environment (.env / Secret Manager)")


def _gemini_url() -> str:
    return (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{GEMINI_MODEL}:generateContent?key={GEMINI_API_KEY}"
    )


async def _post_gemini(payload: Dict[str, Any]) -> str:
    import asyncio

    url = _gemini_url()

    async def _do_request() -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(url, json=payload)

        if resp.status_code >= 400:
            snippet = resp.text[:1200]
            logger.error("Gemini upstream error status=%s body_snippet=%r", resp.status_code, snippet)
            raise RuntimeError(f"Gemini error {resp.status_code}: {snippet}")

        return resp.json()

    last_exc: Optional[Exception] = None
    for attempt in range(2):
        try:
            data: Dict[str, Any] = await _do_request()

            raw_text = ""
            try:
                candidate = data["candidates"][0]
                parts = candidate["content"]["parts"]
                raw_text = next(p["text"] for p in parts if "text" in p)
            except Exception as exc:  # noqa: BLE001
                logger.error("Gemini response missing expected text field. data_keys=%s", list(data.keys()))
                raise RuntimeError("Gemini response missing expected text field.") from exc

            try:
                return clean_llm_json(raw_text)
            except Exception as exc:  # noqa: BLE001
                preview = (raw_text or "")[:800].replace("\n", "\\n")
                logger.error("Gemini returned invalid JSON. raw_text_preview=%r", preview)
                raise RuntimeError(
                    f"Gemini returned non-JSON or empty JSON candidate. raw_text_preview='{preview}'"
                ) from exc

        except RuntimeError as exc:
            last_exc = exc
            if attempt == 0:
                await asyncio.sleep(0.4)
                continue
            raise

    if last_exc:
        raise last_exc
    raise RuntimeError("Gemini call failed for unknown reasons.")


async def _post_gemini_text(payload: Dict[str, Any]) -> str:
    """
    Call Gemini and return plain text (no JSON cleaning).
    Use this for endpoints that intentionally return human text (e.g., summaries).
    """
    import asyncio

    url = _gemini_url()

    async def _do_request() -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(url, json=payload)

        if resp.status_code >= 400:
            snippet = resp.text[:1200]
            logger.error("Gemini upstream error status=%s body_snippet=%r", resp.status_code, snippet)
            raise RuntimeError(f"Gemini error {resp.status_code}: {snippet}")

        return resp.json()

    last_exc: Optional[Exception] = None
    for attempt in range(2):
        try:
            data: Dict[str, Any] = await _do_request()

            try:
                candidate = data["candidates"][0]
                parts = candidate["content"]["parts"]
                raw_text = next(p["text"] for p in parts if "text" in p)
            except Exception as exc:  # noqa: BLE001
                logger.error("Gemini response missing expected text field. data_keys=%s", list(data.keys()))
                raise RuntimeError("Gemini response missing expected text field.") from exc

            return (raw_text or "").strip()

        except RuntimeError as exc:
            last_exc = exc
            if attempt == 0:
                await asyncio.sleep(0.4)
                continue
            raise

    if last_exc:
        raise last_exc
    raise RuntimeError("Gemini call failed for unknown reasons.")


async def call_gemini_for_audio_summary(*, prompt: str, audio_base64: str, mime_type: str) -> str:
    """Call Gemini with an audio clip + prompt and return plain text summary."""
    payload: Dict[str, Any] = {
        "contents": [
            {
                "parts": [
                    {"text": prompt},
                    {
                        "inline_data": {
                            "mime_type": mime_type,
                            "data": audio_base64,
                        }
                    },
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.2,
            "topP": 0.8,
            "topK": 40,
            "maxOutputTokens": 256,
        },
    }

    return await _post_gemini_text(payload)


async def call_gemini_for_item_analysis(*, prompt: str, image_base64: str) -> str:
    """Call Gemini with an image + prompt and return cleaned JSON text."""
    payload: Dict[str, Any] = {
        "contents": [
            {
                "parts": [
                    {"text": prompt},
                    {
                        "inline_data": {
                            "mime_type": "image/jpeg",
                            "data": image_base64,
                        }
                    },
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.2,
            "topP": 0.8,
            "topK": 40,
            "maxOutputTokens": 4096,
        },
    }

    return await _post_gemini(payload)


async def call_gemini_for_item_text_analysis(*, prompt: str) -> str:
    """Call Gemini with text-only prompt and return cleaned JSON text."""
    payload: Dict[str, Any] = {
        "contents": [
            {
                "parts": [
                    {"text": prompt},
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.2,
            "topP": 0.8,
            "topK": 40,
            "maxOutputTokens": 4096,
        },
    }

    return await _post_gemini(payload)


# ---------------------------------------------------------------------------
# Liquidation calls (keep these here so routes can import consistently)
# ---------------------------------------------------------------------------

async def call_gemini_for_liquidation_brief(*, prompt: str, photo_base64: Optional[str] = None) -> str:
    """Liquidation brief. Optional photo."""
    parts = [{"text": prompt}]
    if photo_base64:
        parts.append(
            {
                "inline_data": {
                    "mime_type": "image/jpeg",
                    "data": photo_base64,
                }
            }
        )

    payload: Dict[str, Any] = {
        "contents": [{"parts": parts}],
        "generationConfig": {
            "temperature": 0.2,
            "topP": 0.8,
            "topK": 40,
            "maxOutputTokens": 4096,
        },
    }

    return await _post_gemini(payload)


async def call_gemini_for_liquidation_plan(*, prompt: str) -> str:
    """Liquidation plan. Text-only prompt."""
    return await call_gemini_for_item_text_analysis(prompt=prompt)