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


# ---------------------------------------------------------------------------
# LTC 1.3 prompts (used only when a request carries the 1.3 `context` and/or
# `supplementary` fields). The builders above are unchanged and still serve
# LTC 1.2 and earlier.
# ---------------------------------------------------------------------------

# Evidence wording validated in the PE-001 evidence pilot (harness "evidence-v2").
EVIDENCE_BLOCK_VERSION = "evidence-v2"
_EVIDENCE_BLOCK_WITH_PRIMARY = (
    "ADDITIONAL EVIDENCE:\n"
    "The first image after these instructions is the primary photo of the item.\n"
    "The labeled images after it are additional evidence about the same item.\n"
)
_EVIDENCE_BLOCK_NO_PRIMARY = (
    "ADDITIONAL EVIDENCE:\n"
    "There is no primary photo of the item.\n"
    "The labeled images after these instructions are evidence about the item.\n"
)
_EVIDENCE_DOCUMENT_NOTE = (
    "A supporting document may show historical prices, such as an appraisal, retail replacement or "
    "insurance value. Those are not current resale values: do not base the estimate on them.\n"
    "Attribute facts taken from a document to the document (for example \"according to the "
    "appraisal\") rather than stating them as verified.\n"
)
_EVIDENCE_TRUNCATION_NOTE = (
    "Only the first {shown} of {total} pages of supporting document {doc} were provided.\n"
)

# Labels placed before each supplementary image. They never describe content.
SUPPLEMENTARY_PHOTO_LABEL = "Supplementary photo {n}:"
DOCUMENT_PAGE_LABEL = "Supporting document {doc}, page {page} of {pages}:"

# Keys Gemini must use (ItemAnalysis). Listed explicitly: the 1.2 photo prompt
# never named them, which made `brand` unreliable.
_OUTPUT_FIELDS_BLOCK = (
    "OUTPUT FIELDS (use exactly these keys):\n"
    "- title (string), description (string), category (string)\n"
    "- tags ([string] or null), confidence (number 0-1 or null)\n"
    "- valueHints: {valueLow, estimatedValue, valueHigh, currencyCode, confidenceScore, aiNotes, missingDetails}\n"
    "- brand, modelNumber, style, origin, condition, dimensions, eraOrYear (string or null)\n"
    "- materials, features ([string] or null)\n"
    "- valuationUnit (string): what ONE unit is, e.g. \"one stool\" or \"complete 10-place-setting service\"\n"
    "- conflicts ([string] or null): short notes where the evidence contradicts the owner's notes or the "
    "earlier AI details; null if none\n"
)

_EVIDENCE_USE_RULES = (
    "EVIDENCE RULES:\n"
    "- Base identification on what the photos, documents and owner notes actually show or state.\n"
    "- Do not assert materials, construction, maker, age or authenticity that the evidence does not "
    "support. When something is likely but not shown, say so (\"appears to be\", \"likely\").\n"
    "- Do not invent components or set contents that are not shown or stated.\n"
    "- Read printed or stamped text exactly. Keep manufacturer model, reference and pattern numbers "
    "(they identify the item).\n"
)

_PRIVACY_RULES = (
    "PRIVACY RULES (title, description and all attributes):\n"
    "- Do not include personal names, home addresses, phone numbers or email addresses.\n"
    "- Do not include appraisal, certificate, lab-report, policy, account or serial numbers that "
    "identify a person or a document. You may say that such a document exists (for example "
    "\"a lab grading report is available\").\n"
    "- Manufacturer model, reference and pattern numbers are not personal and may be kept.\n"
)


def _quantity_block(quantity: int | None) -> str:
    q = quantity if isinstance(quantity, int) and quantity >= 1 else 1
    return (
        "QUANTITY AND VALUATION UNIT (STRICT):\n"
        f"- This catalog entry represents QUANTITY = {q} identical unit(s). This number is "
        "authoritative over any count mentioned in text.\n"
        "- Every value in valueHints is for ONE unit, never for the whole quantity.\n"
        "- State that unit in \"valuationUnit\".\n"
        "- If QUANTITY is 1 and the owner describes this entry as a set, pair or service (for example "
        "\"10 place settings\"), the unit is that complete set: value the complete set.\n"
        "- If QUANTITY is more than 1, value one of the identical units (for example one of four stools).\n"
    )


_ORIGIN_HEADINGS = {
    "owner": "OWNER-WRITTEN DESCRIPTION (the owner's own words):",
    "priorAI": "EARLIER AI-GENERATED DESCRIPTION (accepted by the owner but NOT verified):",
    "mixed": "SAVED DESCRIPTION (may mix the owner's text with earlier AI suggestions; NOT verified):",
}


def _context_block(hints: ItemAIHints | None, context) -> str:
    """Item information grouped by where it came from. `context` is an
    ItemAnalysisContext (or None)."""
    lines: List[str] = ["ITEM INFORMATION (grouped by source):"]
    if hints is not None and hints.userWrittenTitle:
        lines.append(f"- Saved item name: {hints.userWrittenTitle}")
    if hints is not None and hints.knownCategory:
        lines.append(f"- Saved category: {hints.knownCategory}")

    notes = (getattr(context, "ownerNotes", None) or "").strip()
    if notes:
        lines.append("")
        lines.append("OWNER-PROVIDED NOTES (written by the owner; treat as the owner's statements, "
                     "authoritative unless the evidence clearly contradicts them):")
        lines.append(notes)

    parts = getattr(context, "savedDescription", None)
    if parts is None and hints is not None and (hints.userWrittenDescription or "").strip():
        # No labeled description was sent: the legacy combined text may hold
        # earlier AI output, so it is labeled as unverified.
        from app.models import SavedDescriptionPart
        parts = [SavedDescriptionPart(origin="mixed", text=hints.userWrittenDescription)]

    for part in (parts or []):
        text = (part.text or "").strip()
        if not text:
            continue
        lines.append("")
        lines.append(_ORIGIN_HEADINGS.get(part.origin, _ORIGIN_HEADINGS["mixed"]))
        lines.append(text)

    prior = {k: v for k, v in (getattr(context, "priorAttributes", None) or {}).items()
             if isinstance(v, str) and v.strip()}
    if prior:
        lines.append("")
        lines.append("EARLIER AI-IDENTIFIED DETAILS (NOT verified; repeat one only if the current "
                     "evidence or owner notes support it, otherwise correct or omit it):")
        for key in sorted(prior):
            lines.append(f"- {key}: {prior[key].strip()}")

    if len(lines) == 1:
        lines.append("No saved item information was provided.")

    lines.append("")
    lines.append(
        "Keep facts the owner wrote in the description when the evidence does not contradict them. "
        "Do not present earlier AI-generated statements as the owner's facts."
    )
    return "\n".join(lines) + "\n"


def evidence_block(*, has_primary: bool, has_document: bool, truncations=()) -> str:
    """Evidence instructions. `truncations` holds (doc, shown, total) tuples."""
    block = _EVIDENCE_BLOCK_WITH_PRIMARY if has_primary else _EVIDENCE_BLOCK_NO_PRIMARY
    if has_document:
        block += _EVIDENCE_DOCUMENT_NOTE
    for doc, shown, total in truncations:
        block += _EVIDENCE_TRUNCATION_NOTE.format(shown=shown, total=total, doc=doc)
    return block


def build_item_analysis_prompt_v2(
    hints: ItemAIHints | None,
    context,
    *,
    has_primary: bool,
    has_evidence: bool,
    has_document: bool = False,
    truncations=(),
) -> str:
    """1.3 photo/evidence prompt: the 1.2 rules plus output fields, the unit
    rule, source-labeled item information, evidence and privacy rules."""
    sections = [
        "You are an expert estate inventory and valuation assistant.\n"
        "You analyze a single household item (from photos, documents and/or description) and respond "
        "with STRICT JSON ONLY.\nNo Markdown. No backticks. No commentary.\n",
        _OUTPUT_FIELDS_BLOCK,
        _CATEGORY_RULES_BLOCK,
        _VALUATION_BASIS_BLOCK,
        "CRITICAL VALUE RULES:\n"
        "- Always include valueHints with valueLow, estimatedValue, valueHigh (number or null), "
        "currencyCode, confidenceScore (0.0 to 1.0), aiNotes (string) and missingDetails (array; can be empty).\n"
        "- If you can identify the item well enough for a reasonable estimate but are uncertain, give a WIDE "
        "range for this specific item, set confidenceScore low (e.g., 0.15–0.35), and list what is missing.\n"
        "- If the information is not sufficient to estimate this specific item, set valueLow, estimatedValue "
        "and valueHigh to null, explain why in aiNotes, and list what is missing.\n"
        "- Never substitute a generic or typical range for the category. Do NOT omit valueHints.\n",
        _quantity_block(getattr(context, "quantity", None)),
        _EVIDENCE_USE_RULES,
        _PRIVACY_RULES,
        _context_block(hints, context),
    ]
    if has_evidence:
        sections.append(evidence_block(has_primary=has_primary, has_document=has_document,
                                       truncations=truncations))
    elif not has_primary:
        sections.append("No photo is available. Use only the text provided.\n")
    return "\n".join(sections)


def build_item_analysis_text_prompt_v2(hints: ItemAIHints | None, context) -> str:
    """1.3 text-only prompt (no photo, no evidence)."""
    return build_item_analysis_prompt_v2(hints, context, has_primary=False, has_evidence=False)
