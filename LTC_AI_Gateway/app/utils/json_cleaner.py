from __future__ import annotations

import json
import re
from typing import Any, Optional, Tuple


_CODE_FENCE_RE = re.compile(r"```(?:json)?\s*([\s\S]*?)\s*```", re.IGNORECASE)


def _strip_code_fences(text: str) -> str:
    """
    If the model returns a fenced code block, prefer the fenced content.
    Otherwise return the original text.
    """
    m = _CODE_FENCE_RE.search(text)
    if m:
        return m.group(1).strip()
    return text.strip()


def _find_first_json_span(text: str) -> Optional[Tuple[int, int]]:
    """
    Find the first top-level JSON object/array span in text by scanning and balancing
    braces/brackets while respecting strings and escapes.

    Returns (start_index, end_index_exclusive) or None.
    """
    s = text
    n = len(s)

    # Find first likely JSON start
    start = None
    for i, ch in enumerate(s):
        if ch in "{[":
            start = i
            break
    if start is None:
        return None

    opening = s[start]
    closing = "}" if opening == "{" else "]"

    depth = 0
    in_str = False
    escape = False

    for i in range(start, n):
        ch = s[i]

        if in_str:
            if escape:
                escape = False
                continue
            if ch == "\\":
                escape = True
                continue
            if ch == '"':
                in_str = False
            continue

        # not in string
        if ch == '"':
            in_str = True
            continue

        if ch == opening:
            depth += 1
            continue

        if ch == closing:
            depth -= 1
            if depth == 0:
                return (start, i + 1)

    return None


def _unwrap_known_wrappers(obj: Any) -> Any:
    """
    Gemini sometimes returns a wrapper dict like {"brief": {...}} or {"data": {...}}.
    Unwrap only when it is safe and obvious.

    - Only unwrap dicts.
    - Only unwrap if dict has a single key AND that key is in an allowlist.
    - Unwrap up to 2 levels.
    """
    allow = {
        "brief",
        "item",
        "data",
        "result",
        "response",
        "payload",
        "liquidationBrief",
        "liquidation_brief",
        "output",
    }

    current = obj
    for _ in range(2):
        if isinstance(current, dict) and len(current) == 1:
            (k, v), = current.items()
            if k in allow and isinstance(v, (dict, list)):
                current = v
                continue
        break

    return current


def clean_llm_json(raw_text: str) -> str:
    """
    Return a JSON string suitable for Pydantic model_validate_json().

    Handles:
    - fenced ```json blocks
    - leading/trailing prose
    - wrapper objects (brief/data/result/etc.)
    - returns canonical JSON via json.dumps
    """
    if not raw_text or not raw_text.strip():
        raise ValueError("LLM response is empty.")

    text = _strip_code_fences(raw_text)

    span = _find_first_json_span(text)
    if span is None:
        # As a fallback, try the whole text in case it's already pure JSON
        candidate = text.strip()
    else:
        candidate = text[span[0] : span[1]].strip()

    # Parse; if this fails, raise a clean error (caller can do one-shot repair)
    parsed = json.loads(candidate)

    parsed = _unwrap_known_wrappers(parsed)

    return json.dumps(parsed, ensure_ascii=False)
