# app/ai/normalization/item_analysis.py

from __future__ import annotations


def _normalize_item_analysis_json(raw_json: str) -> str:
    """
    Lightweight normalizer for common field mismatches.
    Keep it minimal to avoid unintended transformations.
    """
    # If older prompts used "summary" instead of "description", map it.
    # (Swift maps backend "description" -> summary via CodingKeys.)
    return raw_json.replace('"summary":', '"description":')
