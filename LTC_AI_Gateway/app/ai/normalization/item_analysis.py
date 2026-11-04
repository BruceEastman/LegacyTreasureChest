# app/ai/normalization/item_analysis.py

from __future__ import annotations

import json

# Alternate top-level keys Gemini uses for the item title. The photo prompt does not
# list field names, so Gemini 3.6 Flash often answers with one of these instead of "title".
_TITLE_ALIASES = ("itemName", "name")


def _normalize_item_analysis_json(raw_json: str) -> str:
    """
    Lightweight normalizer for common field mismatches.
    Keep it minimal to avoid unintended transformations.
    """
    normalized = raw_json

    # Some older/alternate prompts might return "summary" instead of "description".
    normalized = normalized.replace('"summary":', '"description":')

    # Some older/alternate prompts might return "itemTitle" instead of "title".
    normalized = normalized.replace('"itemTitle":', '"title":')

    return _fill_title_from_alias(normalized)


def _fill_title_from_alias(json_str: str) -> str:
    """
    Use "itemName" or "name" as the title when the title is missing, null or blank.

    A non-blank "title" always wins. Nothing is filled when the aliases are blank,
    not strings, or disagree with each other; validation and the existing repair
    call then handle the response as before. Returns the input unchanged unless a
    title is filled in.
    """
    try:
        obj = json.loads(json_str)
    except ValueError:
        return json_str
    if not isinstance(obj, dict):
        return json_str

    title = obj.get("title")
    if title is not None and not (isinstance(title, str) and not title.strip()):
        return json_str  # a usable title, or a non-string that validation should reject

    candidates = {
        obj[key].strip()
        for key in _TITLE_ALIASES
        if isinstance(obj.get(key), str) and obj[key].strip()
    }
    if len(candidates) != 1:
        return json_str  # no usable alias, or conflicting aliases

    obj["title"] = candidates.pop()
    return json.dumps(obj, ensure_ascii=False)
