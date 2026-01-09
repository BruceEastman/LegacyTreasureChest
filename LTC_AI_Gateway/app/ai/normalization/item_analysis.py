# app/ai/normalization/item_analysis.py

from __future__ import annotations

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

    return normalized
