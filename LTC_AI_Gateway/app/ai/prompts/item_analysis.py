# app/ai/prompts/item_analysis.py

from __future__ import annotations

from typing import List

from app.models import CANONICAL_ITEM_CATEGORIES, ItemAIHints


# ---------------------------------------------------------------------------
# Prompt helpers
# ---------------------------------------------------------------------------


# Shared, closed-list category instruction reused by both the photo and
# text-only prompts so Gemini is given the exact same category contract.
_CATEGORY_RULES_BLOCK = (
    "CATEGORY RULES (STRICT):\n"
    "- The \"category\" field MUST be exactly one of these values (character-for-character):\n"
    "  " + ", ".join(CANONICAL_ITEM_CATEGORIES) + "\n"
    "- Never invent, paraphrase, or combine category names.\n"
    "- If no listed category reasonably fits, return exactly \"Other\".\n"
)

# Shared valuation-basis instruction reused by both the photo and text-only
# prompts so every value in valueHints means the same thing.
_VALUATION_BASIS_BLOCK = (
    "VALUATION BASIS (applies to every value in valueHints):\n"
    "- Estimate the item's CURRENT SECONDARY-MARKET RESALE value: what a typical private seller\n"
    "  could reasonably expect to receive for this used item today through ordinary resale channels.\n"
    "- Be conservative. When uncertain, favor the lower end of what is realistic.\n"
    "- Express uncertainty as a range (valueLow to valueHigh) rather than overstating precision.\n"
    "- Do NOT substitute original retail price, current new retail price, replacement cost,\n"
    "  insurance value, or formal appraisal value, even if one is visible or provided.\n"
    "- Base the estimate on general knowledge of comparable items. Do not claim that specific\n"
    "  completed sales were checked or verified.\n"
)


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

    # IMPORTANT: Always return ValueHints. Use a numeric range when the item can be
    # reasonably estimated; otherwise leave the numbers null ("Not estimated").
    return f"""You are an expert estate inventory and valuation assistant.
You analyze a single household item (from photo and/or description) and respond with STRICT JSON ONLY.
No Markdown. No backticks. No commentary.

Return a JSON object that matches the ItemAnalysis schema.

{_CATEGORY_RULES_BLOCK}
{_VALUATION_BASIS_BLOCK}
CRITICAL VALUE RULES:
- Always include valueHints with:
  - valueLow (number or null)
  - estimatedValue (number or null)
  - valueHigh (number or null)
  - currencyCode (e.g., "USD")
  - confidenceScore (0.0 to 1.0)
  - aiNotes (string)
  - missingDetails (array of strings; can be empty)
- If you can identify the item well enough for a reasonable estimate but are uncertain,
  give a WIDE range for this specific item, set confidenceScore low (e.g., 0.15–0.35),
  and list what details are missing.
- If the information is not sufficient to estimate this specific item, set valueLow,
  estimatedValue, and valueHigh to null, explain why in aiNotes, and list what is missing.
- Never substitute a generic or typical range for the category. Do NOT omit valueHints.

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

{_CATEGORY_RULES_BLOCK}
{_VALUATION_BASIS_BLOCK}
Rules:
- The top-level fields "title", "description", and "category" are REQUIRED and must be present.
- Always include "valueHints" with "currencyCode" (use "USD" unless user text implies otherwise).
- If the text supports a reasonable estimate for this specific item, give a low/estimated/high range.
- If it does not, set valueLow, estimatedValue, and valueHigh to null, explain why in "aiNotes",
  and list what is missing. Never substitute a generic or typical range for the category.
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
Follow the CRITICAL VALUE RULES (always include valueHints; use null values when not estimable).
No markdown. No backticks.
"""
