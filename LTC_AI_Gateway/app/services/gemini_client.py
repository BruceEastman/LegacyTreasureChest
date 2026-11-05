from __future__ import annotations

import contextvars
import logging
import os
import re
import time
from typing import Any, Dict, Optional

import httpx
from dotenv import load_dotenv

from app.core.safe_logging import log_event
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
GEMINI_MODEL = _sanitize_env("GEMINI_MODEL", os.getenv("GEMINI_MODEL", "gemini-3.6-flash"))

if not GEMINI_API_KEY:
    raise RuntimeError("GEMINI_API_KEY is not set in environment (.env / Secret Manager)")


# ---------------------------------------------------------------------------
# Per-attempt instrumentation (opt-in per route)
# ---------------------------------------------------------------------------
# A route that wants per-attempt timing and token logs sets this context for the duration of
# its Gemini calls, e.g. {"requestId": ..., "operation": "liquidation_brief", "scope": "item",
# "phase": "initial"}. Routes that do not set it log exactly as before. The log line carries
# only metadata (status, finish reason, token counts, sizes, timings): never prompts, model
# text, item details or the API key.
GEMINI_LOG_CONTEXT: contextvars.ContextVar[Optional[Dict[str, Any]]] = contextvars.ContextVar(
    "gemini_log_context", default=None
)


def _log_gemini_attempt(
    ctx: Optional[Dict[str, Any]],
    *,
    attempt: int,
    started: float,
    info: Dict[str, Any],
    outcome: str,
    will_retry: bool,
    payload: Dict[str, Any],
) -> None:
    if not ctx:
        return
    try:
        _emit_gemini_attempt(ctx, attempt=attempt, started=started, info=info, outcome=outcome,
                             will_retry=will_retry, payload=payload)
    except Exception:  # noqa: BLE001  (instrumentation must never change request behavior)
        logger.warning("gemini.attempt log could not be written")


def _json_shape(text: str) -> Dict[str, Any]:
    """Content-free structure of a reply that failed to parse, to tell a cut-off reply (unclosed
    brackets or string at the end) from malformed but complete JSON. Returns numbers only."""
    import json as _json

    depth, in_str, escape, started_json = 0, False, False, False
    for ch in text:
        if in_str:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch in "{[":
            depth += 1
            started_json = True
        elif ch in "}]":
            depth -= 1
    error_pos = None
    body = text.strip()
    if body.startswith("```"):
        body = body.strip("`").removeprefix("json").strip()
    try:
        _json.loads(body)
    except ValueError as exc:
        pos = getattr(exc, "pos", None)
        error_pos = round(pos / max(len(body), 1), 3) if isinstance(pos, int) else None
    return {"jsonOpenBrackets": depth if started_json else None, "jsonEndsInString": in_str,
            "jsonErrorPos": error_pos}


def _emit_gemini_attempt(ctx, *, attempt, started, info, outcome, will_retry, payload) -> None:
    data = info.get("data") if isinstance(info.get("data"), dict) else {}
    usage = data.get("usageMetadata") or {}
    candidates = data.get("candidates") or []
    finish_reason = candidates[0].get("finishReason") if candidates and isinstance(candidates[0], dict) else None
    parts = ((candidates[0].get("content") or {}).get("parts") or []) if candidates and isinstance(candidates[0], dict) else []
    text_parts = sum(1 for p in parts if isinstance(p, dict) and "text" in p and not p.get("thought"))
    shape = info.get("jsonShape") or {}
    log_event(
        logger,
        level=logging.INFO,
        event="gemini.attempt",
        request_id=ctx.get("requestId"),
        fields={
            "operation": ctx.get("operation"),
            "scope": ctx.get("scope"),
            "phase": ctx.get("phase"),
            "attempt": attempt,
            "model": GEMINI_MODEL,
            "maxOutputTokens": (payload.get("generationConfig") or {}).get("maxOutputTokens"),
            "latencyMs": int((time.perf_counter() - started) * 1000),
            "httpStatus": info.get("httpStatus"),
            "finishReason": finish_reason,
            "promptTokens": usage.get("promptTokenCount"),
            "outputTokens": usage.get("candidatesTokenCount"),
            "thinkingTokens": usage.get("thoughtsTokenCount"),
            "totalTokens": usage.get("totalTokenCount"),
            "responseChars": info.get("responseChars"),
            "textParts": text_parts,
            **shape,
            "jsonValid": outcome == "ok",
            "outcome": outcome,
            "willRetry": will_retry,
        },
    )


def _gemini_url() -> str:
    return (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{GEMINI_MODEL}:generateContent?key={GEMINI_API_KEY}"
    )


async def _post_gemini(payload: Dict[str, Any], *, retry_on_truncation: bool = True) -> str:
    """POST a JSON-output request. One identical retry on a failed attempt (unchanged default).

    retry_on_truncation=False: if Gemini reports finishReason MAX_TOKENS and the text does not
    parse, fail at once instead of resending the identical request, which would be cut off again.
    """
    import asyncio

    url = _gemini_url()
    log_ctx = GEMINI_LOG_CONTEXT.get()

    async def _do_request(info: Dict[str, Any]) -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(url, json=payload)
        info["httpStatus"] = resp.status_code

        if resp.status_code >= 400:
            snippet = resp.text[:1200]
            logger.error(
                "Gemini upstream error operation=%s status=%s response_length=%s",
                "generateContent(json)",
                resp.status_code,
                len(resp.text),
            )
            raise RuntimeError(f"Gemini error {resp.status_code}: {snippet}")

        return resp.json()

    last_exc: Optional[Exception] = None
    for attempt in range(2):
        info: Dict[str, Any] = {}
        started = time.perf_counter()
        outcome = "error"
        try:
            data: Dict[str, Any] = await _do_request(info)
            info["data"] = data

            raw_text = ""
            try:
                candidate = data["candidates"][0]
                parts = candidate["content"]["parts"]
                raw_text = next(p["text"] for p in parts if "text" in p)
            except Exception as exc:  # noqa: BLE001
                outcome = "missing_text"
                logger.error("Gemini response missing expected text field. data_keys=%s", list(data.keys()))
                raise RuntimeError("Gemini response missing expected text field.") from exc
            info["responseChars"] = len(raw_text or "")

            try:
                cleaned = clean_llm_json(raw_text)
                _log_gemini_attempt(log_ctx, attempt=attempt + 1, started=started, info=info,
                                    outcome="ok", will_retry=False, payload=payload)
                return cleaned
            except Exception as exc:  # noqa: BLE001
                outcome = "invalid_json"
                cand0 = (data.get("candidates") or [{}])[0]
                if not retry_on_truncation and isinstance(cand0, dict) and cand0.get("finishReason") == "MAX_TOKENS":
                    info["noRetryTruncated"] = True
                if log_ctx:
                    try:
                        info["jsonShape"] = _json_shape(raw_text or "")
                    except Exception:  # noqa: BLE001
                        pass
                preview = (raw_text or "")[:800].replace("\n", "\\n")
                logger.error(
                    "Gemini returned invalid JSON operation=%s response_length=%s reason=%s",
                    "generateContent(json)",
                    len(raw_text or ""),
                    type(exc).__name__,
                )
                raise RuntimeError(
                    f"Gemini returned non-JSON or empty JSON candidate. raw_text_preview='{preview}'"
                ) from exc

        except RuntimeError as exc:
            last_exc = exc
            if outcome == "error" and (info.get("httpStatus") or 0) >= 400:
                outcome = "http_error"
            retry = attempt == 0 and not info.get("noRetryTruncated")
            _log_gemini_attempt(log_ctx, attempt=attempt + 1, started=started, info=info,
                                outcome=outcome, will_retry=retry, payload=payload)
            if retry:
                await asyncio.sleep(0.4)
                continue
            raise
        except Exception:
            # Transport failures (timeouts, connection errors) are not retried here (unchanged).
            _log_gemini_attempt(log_ctx, attempt=attempt + 1, started=started, info=info,
                                outcome="transport_error", will_retry=False, payload=payload)
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
            logger.error(
                "Gemini upstream error operation=%s status=%s response_length=%s",
                "generateContent(text)",
                resp.status_code,
                len(resp.text),
            )
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

            # A reply cut off at the output limit is incomplete: never return it as a finished summary.
            if candidate.get("finishReason") == "MAX_TOKENS":
                logger.error("Gemini text response truncated operation=%s", "generateContent(text)")
                raise RuntimeError("Gemini summary was truncated at the output limit.")

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
            # Thinking tokens count toward this cap; 256 left room for only a few words.
            "maxOutputTokens": 1024,
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
            "maxOutputTokens": 4096,
        },
    }

    return await _post_gemini(payload)


# ---------------------------------------------------------------------------
# Liquidation calls (keep these here so routes can import consistently)
# ---------------------------------------------------------------------------

LIQUIDATION_BRIEF_MAX_OUTPUT_TOKENS = 8192


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
            # Thinking tokens count toward this cap. Briefs are the largest JSON reply and used up
            # to ~80% of 4096 in testing; 8192 leaves room without changing the prompt or model.
            "maxOutputTokens": LIQUIDATION_BRIEF_MAX_OUTPUT_TOKENS,
        },
    }

    return await _post_gemini(payload, retry_on_truncation=False)


async def call_gemini_for_liquidation_plan(*, prompt: str) -> str:
    """Liquidation plan. Text-only prompt."""
    return await call_gemini_for_item_text_analysis(prompt=prompt)