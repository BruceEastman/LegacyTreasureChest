# app/ai/prompts/item_analysis.py

from __future__ import annotations

from typing import List

from app.models import ItemAIHints


# ---------------------------------------------------------------------------
# Prompt helpers
# ---------------------------------------------------------------------------

def _format_hints(hints: ItemAIHints | None) -> str:
    if hints is None:
        return "No additional user hints were provided."

    lines: List[str] = []
    if hints.userWrittenTitle:
        lines.append(f"- User written title: {hints.userWrittenTitle}")
    if hints.userWrittenDescription:
        lines.append(f"- User description: {hints.userWrittenDescription}")
    if hints.knownCategory:
        lines.append(f"- User selected/known category: {hints.knownCategory}")

    return "\n".join(lines) if lines else "No additional user hints were provided."


def build_item_analysis_prompt(hints: ItemAIHints | None) -> str:
    hints_block = _format_hints(hints)

    # IMPORTANT: Require ValueHints with numeric range.
    # If uncertain, allow wide range + low confidence + missingDetails, but DO NOT omit.
    return f"""You are an expert estate inventory and valuation assistant.
You analyze a single household item (from photo and/or description) and respond with STRICT JSON ONLY.
No Markdown. No backticks. No commentary.

Return a JSON object that matches the ItemAnalysis schema.

CRITICAL VALUE RULES:
- Always include valueHints with:
  - valueLow (number)
  - estimatedValue (number)
  - valueHigh (number)
  - currencyCode (e.g., "USD")
  - confidenceScore (0.0 to 1.0)
  - aiNotes (string)
  - missingDetails (array of strings; can be empty)
- If you are uncertain, provide a WIDE but plausible range for the category,
  set confidenceScore low (e.g., 0.15–0.35), and list what details are missing.
- Do NOT return null for all value fields. Do NOT omit valueHints.

Here are hints from the user (may be empty):

{hints_block}
"""


def build_item_analysis_text_prompt(title: str | None, description: str | None, category: str | None) -> str:
    safe_title = title or "Untitled Item"
    safe_desc = description or ""
    safe_cat = category or "Uncategorized"

    hints = ItemAIHints(
        userWrittenTitle=safe_title,
        userWrittenDescription=safe_desc,
        knownCategory=safe_cat,
    )
    return build_item_analysis_prompt(hints)


def _build_item_analysis_repair_prompt(*, original_prompt: str, raw_json: str, validation_error: str) -> str:
    return f"""{original_prompt}

The JSON you returned DID NOT validate against the schema.

Validation error:
{validation_error}

Your previous JSON:
{raw_json}

Return STRICT JSON ONLY that fixes the schema errors.
Follow the CRITICAL VALUE RULES (valueHints must contain numeric range).
No markdown. No backticks.
"""
