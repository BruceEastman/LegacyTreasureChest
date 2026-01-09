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
    """
    Text-only item analysis prompt (NO PHOTO).
    Must return JSON matching backend ItemAnalysis schema:
      - title (required)
      - description (required)
      - category (required)
      - optional: tags, confidence, valueHints, brand, materials, style, origin, condition, dimensions, eraOrYear, features
    """
    safe_title = (title or "").strip()
    safe_desc = (description or "").strip()
    safe_cat = (category or "").strip()

    # Give the model something concrete even if user fields are sparse.
    if not safe_title:
        safe_title = "Untitled Item"
    if not safe_cat:
        safe_cat = "Uncategorized"

    return f"""
You are helping a family catalog household items for a legacy and estate planning app.

IMPORTANT:
- You will NOT receive a photo.
- Use ONLY the text provided below.
- Respond ONLY with valid JSON (no markdown, no code fences, no commentary).

Return JSON that matches this schema EXACTLY:
{{
  "title": string,
  "description": string,
  "category": string,
  "tags": [string] | null,
  "confidence": number | null,
  "valueHints": {{
    "valueLow": number | null,
    "estimatedValue": number | null,
    "valueHigh": number | null,
    "currencyCode": string,
    "confidenceScore": number | null,
    "aiProvider": string | null,
    "aiNotes": string | null,
    "missingDetails": [string] | null,
    "valuationDate": string | null
  }} | null,
  "brand": string | null,
  "materials": [string] | null,
  "style": string | null,
  "origin": string | null,
  "condition": string | null,
  "dimensions": string | null,
  "eraOrYear": string | null,
  "features": [string] | null
}}

Rules:
- The top-level fields "title", "description", and "category" are REQUIRED and must be present.
- If you are unsure about value from text alone, set "valueHints" to null.
- If you provide valueHints, prefer a low/estimated/high range and include "currencyCode" (use "USD" unless user text implies otherwise).
- Use "missingDetails" to list what would improve confidence (especially: add a clear photo, labels, stamps, measurements, condition).

User text:
Title: {safe_title}
Category: {safe_cat}
Description:
{safe_desc}
""".strip()


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
