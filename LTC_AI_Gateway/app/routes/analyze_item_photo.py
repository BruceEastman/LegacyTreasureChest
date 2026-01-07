from __future__ import annotations

import base64
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from uuid import uuid4

from fastapi import APIRouter, HTTPException
from pydantic import ValidationError

from app.models import AnalyzeItemPhotoRequest, ItemAIHints, ItemAnalysis, ValueHints

from app.models_liquidation import (
    LiquidationBriefDTO,
    LiquidationBriefRequest,
    LiquidationPlanChecklistDTO,
    LiquidationPlanRequest,
)

from app.models_disposition import (
    DispositionOutreachComposeRequest,
    DispositionOutreachComposeResponse,
    DispositionPartnersSearchRequest,
    DispositionPartnersSearchResponse,
)

from app.services.gemini_client import GEMINI_MODEL, call_gemini_for_item_analysis

# Optional Gemini functions (DO NOT crash server if missing)
try:
    from app.services.gemini_client import call_gemini_for_item_text_analysis  # type: ignore
except Exception:  # noqa: BLE001
    call_gemini_for_item_text_analysis = None  # type: ignore

try:
    from app.services.gemini_client import call_gemini_for_liquidation_brief  # type: ignore
except Exception:  # noqa: BLE001
    call_gemini_for_liquidation_brief = None  # type: ignore

try:
    from app.services.gemini_client import call_gemini_for_liquidation_plan  # type: ignore
except Exception:  # noqa: BLE001
    call_gemini_for_liquidation_plan = None  # type: ignore


router = APIRouter(prefix="/ai", tags=["ai"])


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


# ---------------------------------------------------------------------------
# Normalization + repair helpers
# ---------------------------------------------------------------------------

def _normalize_item_analysis_json(raw_json: str) -> str:
    """
    Lightweight normalizer for common field mismatches.
    Keep it minimal to avoid unintended transformations.
    """
    # If older prompts used "summary" instead of "description", map it.
    # (Swift maps backend "description" -> summary via CodingKeys.)
    return raw_json.replace('"summary":', '"description":')


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


# ---------------------------------------------------------------------------
# Category-aware fallback valuation policy
# ---------------------------------------------------------------------------

_CATEGORY_FALLBACKS: dict[str, Tuple[float, float, float]] = {
    "Jewelry": (1000.0, 3000.0, 8000.0),
    "Rug": (200.0, 900.0, 4000.0),
    "Art": (100.0, 500.0, 2500.0),
    "Furniture": (50.0, 200.0, 800.0),
    "China & Crystal": (25.0, 125.0, 600.0),
    "Luxury Personal Items": (150.0, 600.0, 2500.0),
    "Collectibles": (25.0, 150.0, 900.0),
    "Decor": (25.0, 125.0, 600.0),
    "Electronics": (30.0, 150.0, 600.0),
    "Appliance": (50.0, 200.0, 900.0),
    "Tools": (20.0, 80.0, 300.0),
    "Clothing": (20.0, 75.0, 250.0),
    "Luggage": (25.0, 100.0, 350.0),
}

_CATEGORY_MISSING_DETAILS: dict[str, List[str]] = {
    "Jewelry": [
        "Metal purity (e.g., 14k/18k/platinum) and total weight",
        "Stone details (carat, cut, color, clarity) and any certificates",
        "Brand/maker marks or retailer",
        "Condition and whether resizing/repairs were done",
    ],
    "Rug": [
        "Exact dimensions",
        "Materials (wool/silk/cotton foundation) and origin",
        "Approximate age and condition (wear, stains, repairs)",
        "KPSI / knot density if known (or clear back photo if available)",
    ],
    "Art": [
        "Artist name and medium (oil/print/photo/etc.)",
        "Dimensions and whether it is original vs. editioned",
        "Signature/edition info and provenance",
        "Condition and framing details",
    ],
    "Furniture": [
        "Maker/brand and approximate era",
        "Dimensions and materials",
        "Condition issues (scratches, repairs, refinishing)",
        "Designer attribution if any",
    ],
}


def _now_iso_z() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _fallback_for_category(category: str | None) -> Tuple[float, float, float]:
    if not category:
        return (25.0, 125.0, 600.0)
    return _CATEGORY_FALLBACKS.get(category, (25.0, 125.0, 600.0))


def _missing_details_for_category(category: str | None) -> List[str]:
    if not category:
        return ["Brand/maker", "Materials", "Dimensions/size", "Condition", "Any receipts/certificates"]
    return _CATEGORY_MISSING_DETAILS.get(
        category,
        ["Brand/maker", "Materials", "Dimensions/size", "Condition", "Any receipts/certificates"],
    )


def _apply_value_policy(analysis: ItemAnalysis) -> ItemAnalysis:
    """
    Enforce:
    - valueHints exists
    - includes numeric range (low/estimated/high)
    - if Gemini left them empty, apply category fallback with low confidence and explicit notes
    """
    now_iso = _now_iso_z()

    if analysis.valueHints is None:
        low, mid, high = _fallback_for_category(getattr(analysis, "category", None))
        analysis.valueHints = ValueHints(
            valueLow=low,
            estimatedValue=mid,
            valueHigh=high,
            currencyCode="USD",
            confidenceScore=0.20,
            valuationDate=now_iso,
            aiProvider=GEMINI_MODEL,
            aiNotes=(
                "Low-confidence placeholder range. The provided information was insufficient to estimate value precisely. "
                "Add the missing details to tighten the range."
            ),
            missingDetails=_missing_details_for_category(getattr(analysis, "category", None)),
        )
        return analysis

    vh = analysis.valueHints

    # Stamp provider/date
    if vh.valuationDate is None:
        vh.valuationDate = now_iso
    if vh.aiProvider is None:
        vh.aiProvider = GEMINI_MODEL
    if not vh.currencyCode:
        vh.currencyCode = "USD"

    all_missing = (vh.valueLow is None and vh.estimatedValue is None and vh.valueHigh is None)
    if all_missing:
        low, mid, high = _fallback_for_category(getattr(analysis, "category", None))
        vh.valueLow = low
        vh.estimatedValue = mid
        vh.valueHigh = high
        vh.confidenceScore = min(vh.confidenceScore or 1.0, 0.25)
        vh.aiNotes = (
            "Low-confidence placeholder range because the AI could not infer a valuation from the provided inputs alone. "
            "This is not a verified appraisal. Add the missing details to improve accuracy."
        )
        vh.missingDetails = vh.missingDetails or _missing_details_for_category(getattr(analysis, "category", None))
        return analysis

    # Partial numbers: fill missing values conservatively
    if vh.estimatedValue is None:
        if vh.valueLow is not None and vh.valueHigh is not None:
            vh.estimatedValue = (vh.valueLow + vh.valueHigh) / 2.0
        elif vh.valueLow is not None:
            vh.estimatedValue = vh.valueLow
        elif vh.valueHigh is not None:
            vh.estimatedValue = vh.valueHigh

    if vh.valueLow is None and vh.estimatedValue is not None:
        vh.valueLow = round(vh.estimatedValue * 0.7, 2)

    if vh.valueHigh is None and vh.estimatedValue is not None:
        vh.valueHigh = round(vh.estimatedValue * 1.3, 2)

    if vh.valueLow is not None and vh.valueHigh is not None and vh.valueLow > vh.valueHigh:
        vh.valueLow, vh.valueHigh = vh.valueHigh, vh.valueLow

    if vh.aiNotes is None:
        vh.aiNotes = "Valuation estimated from visible cues and provided details. Add more specifics to improve accuracy."
    if vh.missingDetails is None:
        vh.missingDetails = []

    return analysis


# ---------------------------------------------------------------------------
# Liquidation normalization + repair helpers
# ---------------------------------------------------------------------------

def _parse_llm_json_obj(raw_json: str) -> Any:
    """
    Parse cleaned LLM JSON into Python. Raises ValueError on failure.
    Assumes clean_llm_json already stripped fences, etc.
    """
    return json.loads(raw_json)


def _unwrap_singleton_wrapper(obj: Any) -> Any:
    """
    If obj is {"SomeWrapper": {...}} return the inner dict.
    Handles the known wrapper case: {"LiquidationBriefDTO": {...}} etc.
    """
    if not isinstance(obj, dict):
        return obj

    if len(obj) != 1:
        return obj

    (k, v), = obj.items()
    if isinstance(v, dict):
        # Common wrappers we have seen from LLMs
        known_wrappers = {
            "LiquidationBriefDTO",
            "LiquidationPlanChecklistDTO",
            "LiquidationPlanDTO",
            "brief",
            "plan",
            "data",
            "result",
            "response",
            "output",
        }
        if k in known_wrappers or k.endswith("DTO"):
            return v

    return obj


def _normalize_path_value(path: Any) -> Any:
    if not isinstance(path, str):
        return path
    s = path.strip()

    # Normalize common drift
    alias = {
        "patha_maximizeprice": "pathA_maximizePrice",
        "path_a_maximize_price": "pathA_maximizePrice",
        "maximizeprice": "pathA_maximizePrice",
        "maximize_value": "pathA_maximizePrice",
        "pathb_delegateconsign": "pathB_delegateConsign",
        "path_b_delegate_consign": "pathB_delegateConsign",
        "delegateconsign": "pathB_delegateConsign",
        "minimize_effort": "pathB_delegateConsign",
        "pathc_quickexit": "pathC_quickExit",
        "path_c_quick_exit": "pathC_quickExit",
        "quickexit": "pathC_quickExit",
        "fastestexit": "pathC_quickExit",
        "donation": "donate",
    }
    key = s.replace(" ", "").replace("-", "_").lower()
    return alias.get(key, s)


def _normalize_effort_value(effort: Any) -> Any:
    if not isinstance(effort, str):
        return effort
    s = effort.strip().lower().replace(" ", "").replace("-", "")
    alias = {
        "veryhigh": "veryHigh",
        "very_high": "veryHigh",
        "vh": "veryHigh",
        "med": "medium",
    }
    return alias.get(s, effort)


def _normalize_liquidation_brief_obj(*, raw_json: str, request: LiquidationBriefRequest) -> Dict[str, Any]:
    """
    Make the backend tolerant of:
    - wrapper keys: {"LiquidationBriefDTO": {...}}
    - missing required top-level fields we can safely infer/stamp (scope, generatedAt)
    - missing pathOptions ids (generate UUIDs pre-validation)
    - enum drift for recommendedPath/pathOptions[].path and effort
    """
    obj_any = _parse_llm_json_obj(raw_json)
    obj_any = _unwrap_singleton_wrapper(obj_any)

    if not isinstance(obj_any, dict):
        raise ValueError("Liquidation brief JSON was not an object.")

    obj: Dict[str, Any] = dict(obj_any)

    # Required fields we can safely infer/stamp before validation
    obj.setdefault("schemaVersion", request.schemaVersion)
    obj.setdefault("scope", request.scope)

    if "generatedAt" not in obj or obj.get("generatedAt") in (None, ""):
        obj["generatedAt"] = datetime.now(timezone.utc).isoformat()

    # Normalize paths
    if "recommendedPath" in obj:
        obj["recommendedPath"] = _normalize_path_value(obj.get("recommendedPath"))
    if "pathOptions" in obj and isinstance(obj["pathOptions"], list):
        for opt in obj["pathOptions"]:
            if isinstance(opt, dict):
                # Pre-generate ID if missing (since id is required by DTO)
                if not opt.get("id"):
                    opt["id"] = str(uuid4())
                if "path" in opt:
                    opt["path"] = _normalize_path_value(opt.get("path"))
                if "effort" in opt:
                    opt["effort"] = _normalize_effort_value(opt.get("effort"))

    # Ensure lists exist if omitted (to avoid nulls)
    if obj.get("pathOptions") is None:
        obj["pathOptions"] = []
    if obj.get("actionSteps") is None:
        obj["actionSteps"] = []
    if obj.get("missingDetails") is None:
        obj["missingDetails"] = []
    if obj.get("assumptions") is None:
        obj["assumptions"] = []

    return obj


def _normalize_liquidation_plan_obj(*, raw_json: str, request: LiquidationPlanRequest) -> Dict[str, Any]:
    """
    Tolerate wrapper keys and minor drift for plan.
    If createdAt missing, stamp it pre-validation.
    """
    obj_any = _parse_llm_json_obj(raw_json)
    obj_any = _unwrap_singleton_wrapper(obj_any)

    if not isinstance(obj_any, dict):
        raise ValueError("Liquidation plan JSON was not an object.")

    obj: Dict[str, Any] = dict(obj_any)

    obj.setdefault("schemaVersion", request.schemaVersion)
    if "createdAt" not in obj or obj.get("createdAt") in (None, ""):
        obj["createdAt"] = datetime.now(timezone.utc).isoformat()

    # Ensure items is a list
    if obj.get("items") is None:
        obj["items"] = []
    return obj


# ---------------------------------------------------------------------------
# Liquidation prompt helpers
# ---------------------------------------------------------------------------

def _build_liquidation_brief_prompt(payload: LiquidationBriefRequest) -> str:
    title = payload.title or "Untitled Item"
    description = payload.description or ""
    category = payload.category or "Uncategorized"
    qty = payload.quantity or 1
    currency = payload.currencyCode or "USD"

    goal = payload.inputs.goal if payload.inputs and payload.inputs.goal else "balanced"
    location = payload.inputs.locationHint if payload.inputs else None

    return f"""You are an expert estate liquidation assistant.
Return STRICT JSON ONLY matching LiquidationBriefDTO. No markdown.

IMPORTANT:
- Return a FLAT JSON object (no wrapper key like "LiquidationBriefDTO").
- Do NOT nest the response under any extra keys.

Context:
- Scope: {payload.scope}
- Title: {title}
- Description: {description}
- Category: {category}
- Quantity: {qty}
- Goal: {goal}
- Location: {location or "none"}
- Currency: {currency}

Rules:
- Always include: schemaVersion, scope, generatedAt, recommendedPath, reasoning, pathOptions, actionSteps.
- recommendedPath MUST be one of:
  pathA_maximizePrice | pathB_delegateConsign | pathC_quickExit | donate | needsInfo
- Include the primary A/B/C paths in pathOptions (plus donate/needsInfo when appropriate).
- pathOptions[].effort MUST be one of: low | medium | high | veryHigh
- pathOptions[].id MUST be a UUID string
"""


def _build_liquidation_brief_repair_prompt(*, original_prompt: str, raw_json: str, validation_error: str) -> str:
    return f"""{original_prompt}

The JSON you returned DID NOT validate against the LiquidationBriefDTO schema.

Common mistakes to avoid:
- Do NOT wrap the JSON in a top-level key like "LiquidationBriefDTO".
- Return one FLAT object only.

Validation error:
{validation_error}

Your previous JSON:
{raw_json}

Return STRICT JSON ONLY that fixes the schema errors. No markdown. No backticks.
"""


def _build_liquidation_plan_prompt(req: LiquidationPlanRequest) -> str:
    safe_title = req.title or "Untitled"
    safe_category = req.category or "Uncategorized"

    # brief fields
    brief = req.brief
    recommended = brief.recommendedPath
    reasoning = brief.reasoning
    action_steps = brief.actionSteps or []
    missing = brief.missingDetails or []

    # Path grounding
    chosen = req.chosenPath

    steps_block = "\n".join(f"- {s}" for s in action_steps[:20]) if action_steps else "(none)"
    missing_block = "\n".join(f"- {m}" for m in missing[:20]) if missing else "(none)"

    return f"""You are an expert estate liquidation assistant.

Your job: generate an OPERATIONAL checklist plan for the user to execute.

Return STRICT JSON ONLY that matches LiquidationPlanChecklistDTO:
{{
  "schemaVersion": 1,
  "createdAt": "ISO-8601 datetime",
  "items": [
    {{
      "order": 1,
      "text": "step text",
      "isCompleted": false,
      "completedAt": null,
      "userNotes": null
    }}
  ]
}}

IMPORTANT:
- Return a FLAT JSON object (no wrapper key like "LiquidationPlanChecklistDTO").
- Do NOT nest the response under any extra keys.

Context:
- Scope: {req.scope}
- Title: {safe_title}
- Category: {safe_category}
- ChosenPath: {chosen}

Brief context:
- recommendedPath: {recommended}
- reasoning: {reasoning}

Brief actionSteps (context only):
{steps_block}

Missing details (ask user to collect early if relevant):
{missing_block}

Rules:
- Generate 10–16 steps.
- Steps must be specific, short, and sequential.
- Steps must reflect the chosenPath:
  - pathA_maximizePrice: comps, photos, listing quality, shipping/pickup decision, pricing strategy, relist cadence.
  - pathB_delegateConsign: shortlist consignors/dealers, intake packet, commission terms, agreement tracking, follow-ups.
  - pathC_quickExit: quick photos, honest description, fast pricing, safe local pickup rules.
  - donate: pick destination, receipt, record donation details.
  - needsInfo: gather missing details first, then regenerate brief.
- Do NOT include markdown. Do NOT include commentary.
Return JSON only.
"""


def _build_liquidation_plan_repair_prompt(*, original_prompt: str, raw_json: str, validation_error: str) -> str:
    return f"""{original_prompt}

The JSON you returned DID NOT validate against the LiquidationPlanChecklistDTO schema.

Common mistakes to avoid:
- Do NOT wrap the JSON in a top-level key like "LiquidationPlanChecklistDTO".
- Return one FLAT object only.

Validation error:
{validation_error}

Your previous JSON:
{raw_json}

Return STRICT JSON ONLY that fixes the schema errors. No markdown. No backticks.
"""


# ---------------------------------------------------------------------------
# Disposition Engine (v1) — backend-first execution support
# ---------------------------------------------------------------------------

_DISPOSITION_MATRIX_PATH = Path(__file__).resolve().parents[1] / "config" / "disposition_matrix.v1.json"

# Simple in-memory cache (v1)
# key -> (created_at_utc_epoch_seconds, response_dict)
_DISPOSITION_CACHE: dict[str, tuple[float, dict]] = {}
_DISPOSITION_CACHE_TTL_SECONDS = 24 * 60 * 60  # 24 hours


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _load_disposition_matrix() -> dict:
    try:
        raw = _DISPOSITION_MATRIX_PATH.read_text(encoding="utf-8")
        return json.loads(raw)
    except FileNotFoundError as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Disposition matrix not found at {_DISPOSITION_MATRIX_PATH}",
        ) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=500,
            detail=f"Failed to load disposition matrix: {exc}",
        ) from exc


def _norm(s: str) -> str:
    return (s or "").strip().lower()


def _scenario_matches(when: dict, req: DispositionPartnersSearchRequest) -> bool:
    """
    Matching rules:
    - if when key absent => no constraint
    - list fields => req value must be in list (case-sensitive for enums, tolerant for category)
    - scalar fields => must equal
    - wildcard "*" => always match
    """
    sc = req.scenario

    def match_value(when_val: Any, req_val: Any, *, normalize_text: bool = False) -> bool:
        if when_val == "*" or when_val is None:
            return True
        if req_val is None:
            return False
        if isinstance(when_val, list):
            if normalize_text and isinstance(req_val, str):
                return any(_norm(x) == _norm(req_val) for x in when_val)
            return req_val in when_val
        if normalize_text and isinstance(when_val, str) and isinstance(req_val, str):
            return _norm(when_val) == _norm(req_val)
        return when_val == req_val

    # categories
    if "categories" in when:
        if not match_value(when.get("categories"), sc.category, normalize_text=True):
            return False

    # valueBand
    if "valueBand" in when:
        if not match_value(when.get("valueBand"), sc.valueBand):
            return False

    # bulky / fragile
    if "bulky" in when:
        if not match_value(when.get("bulky"), sc.bulky):
            return False
    if "fragile" in when:
        if not match_value(when.get("fragile"), sc.fragile):
            return False

    # goals
    if "goals" in when:
        if not match_value(when.get("goals"), sc.goal):
            return False

    # chosenPaths
    if "chosenPaths" in when:
        if not match_value(when.get("chosenPaths"), req.chosenPath):
            return False

    return True


def _pick_scenario(matrix: dict, req: DispositionPartnersSearchRequest) -> dict:
    scenarios = matrix.get("scenarios", [])
    scenarios_sorted = sorted(scenarios, key=lambda x: int(x.get("priority", 0)), reverse=True)

    for s in scenarios_sorted:
        when = s.get("when", {}) or {}
        if _scenario_matches(when, req):
            return s

    default_id = matrix.get("defaultScenarioId")
    if default_id:
        for s in scenarios_sorted:
            if s.get("id") == default_id:
                return s

    # last-resort fallback: first scenario or empty
    return scenarios_sorted[0] if scenarios_sorted else {"id": "default_any", "partnerTypes": []}


def _cache_get(key: str) -> Optional[dict]:
    import time
    now = time.time()
    v = _DISPOSITION_CACHE.get(key)
    if not v:
        return None
    created, payload = v
    if now - created > _DISPOSITION_CACHE_TTL_SECONDS:
        _DISPOSITION_CACHE.pop(key, None)
        return None
    return payload


def _cache_set(key: str, payload: dict) -> None:
    import time
    _DISPOSITION_CACHE[key] = (time.time(), payload)


def _mk_cache_key(req: DispositionPartnersSearchRequest, *, partner_type: str, radius: int, query: str) -> str:
    loc = req.location
    parts = [
        "v1",
        partner_type,
        _norm(query),
        f"{_norm(loc.city)}|{_norm(loc.region)}|{_norm(loc.countryCode)}",
        str(radius),
        _norm(req.scenario.category or ""),
        _norm(req.scenario.goal or ""),
        _norm(req.chosenPath or ""),
    ]
    return "||".join(parts)


def _negated(text: str, keyword: str) -> bool:
    """
    Simple v1 negation guard:
    - if "not <keyword>" or "no <keyword>" appears, treat as negated.
    This is intentionally lightweight and conservative.
    """
    t = _norm(text)
    k = _norm(keyword)
    return (f"not {k}" in t) or (f"no {k}" in t)


def _eval_gate_keyword_any(gate_def: dict, sources: dict) -> tuple[bool, Optional[str], float, list[dict]]:
    """
    Returns: (passed, source_used, strength, signals)
    strength is 0..1 based on sourceWeights when matched.
    """
    keywords: list[str] = gate_def.get("keywords", []) or []
    srcs: list[str] = gate_def.get("sources", []) or []
    src_weights: dict = gate_def.get("sourceWeights", {}) or {}

    best_strength = 0.0
    best_source: Optional[str] = None
    signals: list[dict] = []

    for src in srcs:
        txt = sources.get(src) or ""
        txt_l = _norm(txt)
        if not txt_l:
            continue

        for kw in keywords:
            kw_l = _norm(kw)
            if not kw_l:
                continue

            if kw_l in txt_l and not _negated(txt_l, kw_l):
                w = float(src_weights.get(src, 0.5))
                if w > best_strength:
                    best_strength = w
                    best_source = src
                signals.append({"type": "text_match", "label": kw, "source": src})

    return (best_strength > 0.0, best_source, best_strength, signals)


def _evaluate_trust(
    matrix: dict,
    *,
    partner_payload_sources: dict,
    trust_gate_ids: list[str],
) -> tuple[list[dict], float, list[dict]]:
    """
    Evaluate trust gates in order. Returns:
    - gates: [{id, mode, status, source, strength}]
    - trustScore: 0..1 (evidence-based match confidence; discovery-first)
    - signals: merged signals

    Philosophy (v1, updated objective):
    - Required gates remain eligibility checks (still used by _apply_required_gates()).
    - trustScore represents "match confidence / evidence-based fit" based on
      fields we can reasonably expect from Places + snippets.
    - Missing policy evidence (pickup/commission/insurance/receipts) should NOT
      heavily penalize trustScore; instead those become "questions to ask".
    """

    gate_defs: dict = matrix.get("trustGateDefinitions", {}) or {}
    gates_out: list[dict] = []
    signals_out: list[dict] = []

    required_total = 0
    required_pass = 0
    boost_total = 0

    required_strength_sum = 0.0
    required_strength_hits = 0
    boost_strength_sum = 0.0
    boost_strength_hits = 0

    for gate_id in trust_gate_ids:
        mode = "boost"
        gid = gate_id
        if isinstance(gate_id, str) and gate_id.startswith("required:"):
            mode = "required"
            gid = gate_id.split("required:", 1)[1].strip()

        gdef = gate_defs.get(gid)
        if not gdef:
            gates_out.append({"id": gid, "mode": mode, "status": "unknown", "source": None, "strength": 0.0})
            if mode == "required":
                required_total += 1
            else:
                boost_total += 1
            continue

        gtype = gdef.get("type")
        passed = False
        src_used: Optional[str] = None
        strength = 0.0
        signals: list[dict] = []

        if gtype == "keyword_any":
            passed, src_used, strength, signals = _eval_gate_keyword_any(gdef, partner_payload_sources)
        else:
            passed = False
            src_used = None
            strength = 0.0
            signals = []

        if mode == "required":
            required_total += 1
            if passed:
                required_pass += 1
                required_strength_sum += float(strength)
                required_strength_hits += 1
        else:
            boost_total += 1
            if passed:
                boost_strength_sum += float(strength)
                boost_strength_hits += 1

        gates_out.append(
            {
                "id": gid,
                "mode": mode,
                "status": "pass" if passed else "fail",
                "source": src_used,
                "strength": round(float(strength), 3),
            }
        )
        signals_out.extend(signals)

    # ---- trustScore (match confidence / evidence-based fit) ----
    # Base: if required gates exist and all pass, we assume a solid "type fit" floor.
    # If required gates are missing in matrix for a partnerType, keep a moderate base.
    if required_total > 0:
        required_ratio = required_pass / float(required_total)
        if required_pass == required_total:
            base = 0.72
        else:
            base = 0.10 * required_ratio
    else:
        base = 0.60

    # Evidence lift: modest boost when we actually see supporting signals.
    # We normalize by gate count so missing boost evidence doesn't crater score.
    req_avg_strength = (required_strength_sum / required_strength_hits) if required_strength_hits > 0 else 0.0
    boost_avg_strength = (boost_strength_sum / boost_strength_hits) if boost_strength_hits > 0 else 0.0

    # "Lift" is capped and intentionally modest.
    lift = (0.18 * req_avg_strength) + (0.18 * boost_avg_strength)

    trust_score = max(0.0, min(1.0, base + lift))
    return (gates_out, round(float(trust_score), 3), signals_out)


def _stub_places_search(*, query: str, city: str, region: str, radius_miles: int, partner_type: str) -> list[dict]:
    """
    Deterministic stub results to unblock iOS + matrix tuning.
    No external API calls in v1 stub.
    """
    # Seeded by query characteristics
    ql = _norm(query)
    base_names = {
        "consignment": ["Heritage Consignment", "Treasure Trail Consignments", "Home & Hearth Consignment"],
        "estate_sale": ["Trusted Estate Services", "Valley Estate Liquidators", "Legacy Estate Sales Co."],
        "auction": ["Boise Auction House", "Gem State Auctions", "Treasure Valley Auctioneers"],
        "donation": ["Community Donation Center", "Family Aid Thrift", "Local Housing Charity"],
        "junk_haul": ["Quick Haul & Remove", "Cleanout Crew", "Same-Day Junk Haul"],
    }
    names = base_names.get(partner_type, ["Local Service Provider"])

    # Make “signals” appear in snippets for testing trust gates
    insured_phrase = "Bonded and insured." if ("bond" in ql or "insured" in ql) else "Insured and licensed."
    pickup_phrase = "Pickup available for bulky items." if ("pickup" in ql or "bulky" in ql) else "Drop-off accepted."
    payout_phrase = "Clear payout terms and commission disclosed." if partner_type == "consignment" else "Transparent process."

    results: list[dict] = []
    for idx, nm in enumerate(names[:8]):
        dist = min(radius_miles, 5 + idx * 4)  # simple increasing distance
        rating = max(3.6, 4.7 - idx * 0.15)

        place_id = f"stub:{partner_type}:{abs(hash((query, nm, city, region))) % 10_000_000}"

        website_snippet = f"{nm} — {partner_type.replace('_', ' ')}. {insured_phrase} {pickup_phrase} {payout_phrase}"
        place_details = f"{nm} serves {city}, {region}. Call for details. Commission terms available." if partner_type == "consignment" else f"{nm} serves {city}."
        reviews_snippet = "Great communication and professional service." if idx % 2 == 0 else "Fast response and fair process."

        results.append(
            {
                "partnerId": place_id,
                "name": nm,
                "partnerType": partner_type,
                "contact": {
                    "phone": "+1-208-555-01{:02d}".format(idx),
                    "website": f"https://example.com/{partner_type}/{idx}",
                    "email": None,
                    "address": f"{100 + idx} Main St",
                    "city": city,
                    "region": region,
                },
                "distanceMiles": float(dist),
                "rating": float(round(rating, 1)),
                "sources": {
                    "website_snippet": website_snippet,
                    "place_details": place_details,
                    "reviews_snippet": reviews_snippet,
                },
            }
        )
    return results


def _relevance_score(partner: dict, query: str) -> float:
    """
    Simple v1 relevance:
    - keyword hits in website snippet
    - mild bonus if query contains partner type word
    """
    txt = _norm(partner.get("sources", {}).get("website_snippet", ""))
    q = _norm(query)
    hits = 0
    for token in [t for t in q.split() if len(t) >= 4][:12]:
        if token in txt:
            hits += 1

    base = min(1.0, hits / 6.0)
    return round(0.55 + 0.45 * base, 3)  # keep fairly high for stubs


def _distance_score(distance_miles: float, radius_miles: int) -> float:
    if radius_miles <= 0:
        return 0.5
    return round(max(0.0, 1.0 - min(distance_miles / float(radius_miles), 1.0)), 3)


def _review_score(rating: Optional[float]) -> float:
    if rating is None:
        return 0.5
    return round(max(0.0, min(1.0, rating / 5.0)), 3)


def _summarize_reasons(
    *,
    partner_type: str,
    req: DispositionPartnersSearchRequest,
    trust_score: float,
    rel: float,
    gates_eval: Optional[list[dict]] = None,
) -> list[str]:
    reasons: list[str] = []

    cat = req.scenario.category or "item"
    reasons.append(f"Matches: {partner_type.replace('_', ' ')} for {cat}")

    # Evidence-accurate phrasing: only claim "confirmed" if we actually have required gate passes with a source.
    confirmed_type = False
    if gates_eval:
        for g in gates_eval:
            if g.get("mode") == "required" and g.get("status") == "pass" and g.get("source") is not None:
                confirmed_type = True
                break

    if confirmed_type:
        reasons.append("Business type appears to match (based on public snippets)")
    else:
        reasons.append("Business type is a likely match (verify on their listing/site)")

    if rel >= 0.75:
        reasons.append("Strong keyword match to your situation")

    # For bulky items: always treat pickup/handling as verification, not assumed evidence
    if req.scenario.bulky:
        reasons.append("Verification needed: ask about pickup/handling for bulky items")

    # Interpret trust_score as match confidence (not qualification)
    if trust_score >= 0.85:
        reasons.append("High match confidence from available evidence")
    elif trust_score >= 0.7:
        reasons.append("Good match; limited public evidence available")
    else:
        reasons.append("Potential match; expect to verify details directly")

    return reasons[:4]


def _build_questions(partner_type: str, req: DispositionPartnersSearchRequest) -> list[str]:
    common = [
        "Do you provide receipts or itemized records suitable for estate accounting?",
        "What is your typical timeline and next step to get started?",
    ]
    if partner_type == "consignment":
        return [
            "Do you offer pickup for bulky items?",
            "What is your commission and payout schedule?",
            "Do you accept items in my category and condition?",
            *common,
        ][:6]
    if partner_type == "estate_sale":
        return [
            "Are you bonded and insured? Can you provide proof?",
            "Do you handle pricing, staging, and advertising?",
            "How do you account for items sold and fees deducted?",
            *common,
        ][:6]
    if partner_type == "auction":
        return [
            "What categories perform best at your auctions?",
            "What are seller fees and settlement timing?",
            "Do you offer pickup/transport for larger items?",
            *common,
        ][:6]
    if partner_type == "donation":
        return [
            "Do you provide a donation receipt suitable for taxes?",
            "What items do you accept or not accept?",
            "Do you offer pickup?",
            *common,
        ][:6]
    if partner_type == "junk_haul":
        return [
            "Can you provide a written estimate and disposal policy?",
            "Are you insured for in-home pickup?",
            "Can you schedule within my timeline?",
            *common,
        ][:6]
    return common


def _rank_candidates(
    *,
    rank_weights: dict,
    trust_score: float,
    relevance: float,
    distance_score: float,
    review_score: float,
) -> float:
    w_t = float(rank_weights.get("trustScore", 0.45))
    w_r = float(rank_weights.get("relevanceScore", 0.35))
    w_d = float(rank_weights.get("distanceScore", 0.15))
    w_v = float(rank_weights.get("reviewScore", 0.05))
    score = (w_t * trust_score) + (w_r * relevance) + (w_d * distance_score) + (w_v * review_score)
    return round(max(0.0, min(1.0, score)), 3)


def _apply_required_gates(gates: list[dict]) -> bool:
    """
    If any required gate fails, exclude partner from results (hard filter).
    """
    for g in gates:
        if g.get("mode") == "required" and g.get("status") == "fail":
            return False
    return True


@router.post("/disposition/partners/search", response_model=DispositionPartnersSearchResponse)
async def disposition_partners_search(
    payload: DispositionPartnersSearchRequest,
) -> DispositionPartnersSearchResponse:
    """
    Disposition Engine v1:
    - Select scenario via matrix (priority + wildcard + fallback)
    - Run partner-type searches (provider abstraction: stub or Google Places New)
    - Evaluate trust gates (required vs boost)
    - Rank + return "why recommended" and "questions to ask"
    - Radius expansion when results are too few
    - In-memory cache to limit provider calls
    """
    from app.services.partner_discovery.factory import get_partner_discovery_provider
    from app.services.partner_discovery.providers import PartnerDiscoveryQuery

    def _safe_getattr(obj, name: str, default=None):
        try:
            return getattr(obj, name)
        except Exception:
            return default

    def _as_float(v):
        try:
            if v is None:
                return None
            return float(v)
        except Exception:
            return None

    def _normalize_brand_hints() -> None:
        """
        Wire payload.hints.keywords -> payload.scenario.brandHints (v1-safe).
        Dedup + cap to keep queries short and deterministic.
        """
        # Start from scenario.brandHints (already part of DTO)
        current = list(payload.scenario.brandHints or [])
        seen = {_norm(x) for x in current if isinstance(x, str) and x.strip()}

        # Add hints.keywords
        if payload.hints and payload.hints.keywords:
            for kw in payload.hints.keywords:
                if not isinstance(kw, str):
                    continue
                kw_s = kw.strip()
                if not kw_s:
                    continue
                fp = _norm(kw_s)
                if fp in seen:
                    continue
                current.append(kw_s)
                seen.add(fp)

        # Keep short; provider/search quality improves when not overstuffed
        payload.scenario.brandHints = current[:6]

    matrix = _load_disposition_matrix()
    scenario = _pick_scenario(matrix, payload)

    default_radius = int(matrix.get("defaultRadiusMiles", 25))
    base_radius = int(payload.location.radiusMiles or default_radius)
    max_radius = int(matrix.get("maxRadiusMiles", 100))
    min_results = int(matrix.get("minResults", 6))

    partner_types: list[dict] = scenario.get("partnerTypes", []) or []
    all_results: list[dict] = []

    # Provider: explicit selection by env var; stub remains available.
    provider = get_partner_discovery_provider(stub_fn=_stub_places_search)

    # Normalize hints early so they consistently affect all queries/types.
    _normalize_brand_hints()

    # Optional center coordinates for accurate distance computation.
    # Backwards compatible: iOS/curl can omit.
    center_lat = _as_float(_safe_getattr(payload.location, "latitude", None))
    center_lng = _as_float(_safe_getattr(payload.location, "longitude", None))

    # Each partner type defines its own query templates and trust/ranking
    for pt in partner_types:
        partner_type = pt.get("type")
        if not partner_type:
            continue

        queries = pt.get("queries", []) or []
        trust_gates = pt.get("trustGates", []) or []
        rank_weights = pt.get("rankWeights", {}) or {}

        # Radius expansion loop (25 -> 50 -> 100, capped)
        radii: list[int] = [base_radius]
        if base_radius < 50:
            radii.append(50)
        if 100 not in radii:
            radii.append(100)
        radii = [r for r in radii if r <= max_radius]

        found_for_type: list[dict] = []

        for radius in radii:
            # Run each query template (weighted queries later; v1 uses all)
            for q in queries:
                q_template = q.get("q") if isinstance(q, dict) else None
                if not q_template:
                    continue

                query_str = (
                    q_template.replace("{city}", payload.location.city)
                    .replace("{region}", payload.location.region)
                    .replace("{category}", payload.scenario.category or "")
                )

                # Allow hints to enrich search (v1)
                if payload.scenario.brandHints:
                    query_str = f"{query_str} {' '.join(payload.scenario.brandHints[:2])}"

                cache_key = _mk_cache_key(
                    payload,
                    partner_type=partner_type,
                    radius=radius,
                    query=query_str,
                )
                cached = _cache_get(cache_key)
                if cached is not None:
                    candidates = cached.get("candidates", [])
                else:
                    # Provider abstraction (stub or Google Places New)
                    candidates = provider.search(
                        PartnerDiscoveryQuery(
                            query=query_str,
                            city=payload.location.city,
                            region=payload.location.region,
                            radius_miles=radius,
                            partner_type=partner_type,
                            center_lat=center_lat,
                            center_lng=center_lng,
                            # Optional: keep these default unless you later add localization inputs
                            language_code="en",
                            region_code="US",
                        )
                    )
                    _cache_set(cache_key, {"candidates": candidates})

                for c in candidates:
                    # Trust evaluation
                    sources = c.get("sources", {}) or {}
                    gates_eval, trust_score, signals = _evaluate_trust(
                        matrix,
                        partner_payload_sources=sources,
                        trust_gate_ids=trust_gates,
                    )

                    if not _apply_required_gates(gates_eval):
                        continue

                    rel = _relevance_score(c, query_str)

                    # Be tolerant of missing distance in provider payload.
                    dist_miles_raw = c.get("distanceMiles", None)
                    try:
                        dist_miles = float(dist_miles_raw) if dist_miles_raw is not None else float(radius)
                    except Exception:
                        dist_miles = float(radius)

                    dist_score = _distance_score(dist_miles, radius)
                    rev_score = _review_score(c.get("rating"))

                    score = _rank_candidates(
                        rank_weights=rank_weights,
                        trust_score=trust_score,
                        relevance=rel,
                        distance_score=dist_score,
                        review_score=rev_score,
                    )

                    reasons = _summarize_reasons(
                        partner_type=partner_type,
                        req=payload,
                        trust_score=trust_score,
                        rel=rel,
                        gates_eval=gates_eval,
                    )

                    found_for_type.append(
                        {
                            "partnerId": c.get("partnerId"),
                            "name": c.get("name"),
                            "partnerType": partner_type,
                            "contact": c.get("contact", {}),
                            "distanceMiles": c.get("distanceMiles"),
                            "rating": c.get("rating"),

                            # Consumer facing trust signals
                            "userRatingsTotal": c.get("userRatingsTotal") or c.get("userRatingCount"),


                            "trust": {
                                "trustScore": trust_score,
                                "claimLevel": "claimed",
                                "gates": gates_eval,
                                "signals": signals[:12],
                            },
                            "ranking": {
                                "score": score,
                                "reasons": reasons,
                            },
                            "whyRecommended": " ; ".join(reasons[:2]),
                            "questionsToAsk": _build_questions(partner_type, payload),
                        }
                    )

                    # Stop collecting more candidates for this query if we have enough
                    if len(found_for_type) >= min_results:
                        break

                # Stop running more queries at this radius if we have enough
                if len(found_for_type) >= min_results:
                    break

            # Stop expanding radius if we have enough
            if len(found_for_type) >= min_results:
                break

        # Deduplicate within partnerType by a stable fingerprint (stub partnerId is not stable)
        def _fingerprint(r: dict) -> str:
            c = r.get("contact") or {}
            name = _norm(r.get("name", ""))
            phone = _norm(c.get("phone") or "")
            web = _norm(c.get("website") or "")
            addr = _norm(c.get("address") or "")
            city = _norm(c.get("city") or "")
            region = _norm(c.get("region") or "")
            return f"{name}|{phone}|{web}|{addr}|{city}|{region}"

        seen_fp: set[str] = set()
        deduped: list[dict] = []
        for r in sorted(
            found_for_type,
            key=lambda x: float(x.get("ranking", {}).get("score", 0.0)),
            reverse=True,
        ):
            fp = _fingerprint(r)
            if fp in seen_fp:
                continue
            seen_fp.add(fp)
            deduped.append(r)

        all_results.extend(deduped[: int(matrix.get("maxResultsPerType", 8))])

    # Global ranking
    all_results_sorted = sorted(
        all_results,
        key=lambda x: float(x.get("ranking", {}).get("score", 0.0)),
        reverse=True,
    )

    return DispositionPartnersSearchResponse(
        schemaVersion=1,
        generatedAt=_utcnow(),
        scenarioId=scenario.get("id", "unknown"),
        partnerTypes=[pt.get("type") for pt in partner_types if pt.get("type")],
        results=all_results_sorted[: int(matrix.get("maxResultsTotal", 15))],
        disclaimer="Partner information is best-effort and may be outdated. Verify policies (bonding/insurance/receipts/fees) directly.",
        recommendedRefreshDays=int(matrix.get("recommendedRefreshDays", 30)),
    )

@router.post("/disposition/outreach/compose", response_model=DispositionOutreachComposeResponse)
async def disposition_outreach_compose(payload: DispositionOutreachComposeRequest) -> DispositionOutreachComposeResponse:
    """
    Template-first outreach packet (v1).
    No auto-contacting; iOS uses this to prefill subject/body + attachment list.
    """
    item = payload.itemSummary
    partner = payload.partner

    city = payload.location.city
    region = payload.location.region

    value_txt = ""
    if item.valueEstimate and (item.valueEstimate.low or item.valueEstimate.likely or item.valueEstimate.high):
        cur = item.valueEstimate.currencyCode or "USD"
        lo = item.valueEstimate.low
        mid = item.valueEstimate.likely
        hi = item.valueEstimate.high
        value_txt = f"Estimated value ({cur}): "
        if lo is not None and hi is not None:
            value_txt += f"{lo:.0f}–{hi:.0f}"
        elif mid is not None:
            value_txt += f"{mid:.0f}"
        elif lo is not None:
            value_txt += f"{lo:.0f}+"
        else:
            value_txt += "unknown"
    else:
        value_txt = "Estimated value: unknown (happy to provide more details)."

    subject = f"Inquiry: {item.title} ({city})"

    # Contact method selection (many partners won't have email)
    preferred = "email" if (partner.contact and partner.contact.email) else "website_form"
    if not partner.contact or (not partner.contact.email and not partner.contact.website):
        preferred = "phone"

    questions = [
        "Are you currently accepting items in this category?",
        "What is your process and timeline to evaluate/accept items?",
        "Do you provide receipts or itemized records (useful for estate accounting)?",
    ]

    body = (
        f"Hello {partner.name},\n\n"
        "I am using the Legacy Treasure Chest app to catalog estate items and plan next steps.\n"
        f"I have an item that may be a fit for your {partner.partnerType.replace('_', ' ')} services.\n\n"
        f"Item: {item.title}\n"
        f"Category: {item.category or 'Unknown'}\n"
        f"Quantity: {item.quantity or 1}\n"
        f"Location: {city}, {region}\n"
        f"{value_txt}\n\n"
        f"Details:\n{item.description or '(no additional description provided)'}\n\n"
        "Questions:\n"
        + "\n".join([f"- {q}" for q in questions])
        + "\n\n"
        "If helpful, I can share a one-page item summary PDF and photos.\n"
        "Thank you,\n"
        "Bruce\n"
    )

    attachments = []
    if payload.packetScope and payload.packetScope.includeInventoryPdf:
        attachments.append({"kind": "inventory_pdf", "label": "LTC_Item_Summary.pdf", "required": True})
    if payload.packetScope and payload.packetScope.includePhotos:
        # v1: we don’t know exact photos on backend; iOS can attach what it has
        attachments.append({"kind": "photos", "label": "Item_Photos.jpg (one or more)", "required": False})
    if payload.packetScope and payload.packetScope.includePlanSummary:
        attachments.append({"kind": "plan_summary", "label": "Liquidation_Plan_Steps.txt", "required": False})

    return DispositionOutreachComposeResponse(
        schemaVersion=1,
        generatedAt=_utcnow(),
        preferredContactMethod=preferred,
        subject=subject,
        emailBody=body,
        attachments=attachments,
        followUps=[
            "If no response in 3 business days, send a brief follow-up.",
            "Confirm pickup logistics, fees/commission, and documentation/receipts.",
        ],
        instructions=(
            "If the partner has no email, use their website contact form and paste the message body. "
            "If neither email nor website is available, call and use the same questions."
        ),
    )


# ---------------------------------------------------------------------------
# Endpoints (existing)
# ---------------------------------------------------------------------------

@router.post("/analyze-item-photo", response_model=ItemAnalysis)
async def analyze_item_photo(payload: AnalyzeItemPhotoRequest) -> ItemAnalysis:
    try:
        base64.b64decode(payload.imageJpegBase64, validate=True)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail="imageJpegBase64 is not valid base64") from exc

    prompt = build_item_analysis_prompt(payload.hints)

    try:
        raw_json = await call_gemini_for_item_analysis(
            prompt=prompt,
            image_base64=payload.imageJpegBase64,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    normalized = _normalize_item_analysis_json(raw_json)

    try:
        analysis = ItemAnalysis.model_validate_json(normalized)
    except ValidationError as ve:
        # One repair attempt with explicit error context
        try:
            repair_prompt = _build_item_analysis_repair_prompt(
                original_prompt=prompt,
                raw_json=normalized,
                validation_error=str(ve),
            )
            repaired = await call_gemini_for_item_analysis(
                prompt=repair_prompt,
                image_base64=payload.imageJpegBase64,
            )
            repaired_norm = _normalize_item_analysis_json(repaired)
            analysis = ItemAnalysis.model_validate_json(repaired_norm)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(
                status_code=502,
                detail=f"Failed to decode ItemAnalysis JSON from Gemini: {ve}",
            ) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=502,
            detail=f"Failed to decode ItemAnalysis JSON from Gemini: {exc}",
        ) from exc

    analysis = _apply_value_policy(analysis)
    return analysis


@router.post("/analyze-item-text", response_model=ItemAnalysis)
async def analyze_item_text(payload: dict) -> ItemAnalysis:
    """
    Text-only item analysis (no photo).
    Payload shape:
      {
        "title": "...",
        "description": "...",
        "category": "Jewelry",
        "hints": { optional ItemAIHints-compatible object }
      }
    """
    if call_gemini_for_item_text_analysis is None:
        raise HTTPException(status_code=501, detail="Text-only item analysis is not enabled on this server build.")

    title = payload.get("title")
    description = payload.get("description")
    category = payload.get("category")

    hints_obj = payload.get("hints")
    hints: Optional[ItemAIHints] = None
    if isinstance(hints_obj, dict):
        try:
            hints = ItemAIHints.model_validate(hints_obj)  # type: ignore[attr-defined]
        except Exception:
            hints = None

    prompt = build_item_analysis_prompt(hints) if hints else build_item_analysis_text_prompt(title, description, category)

    try:
        raw_json = await call_gemini_for_item_text_analysis(prompt=prompt)  # type: ignore[misc]
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    normalized = _normalize_item_analysis_json(raw_json)

    try:
        analysis = ItemAnalysis.model_validate_json(normalized)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=502,
            detail=f"Failed to decode ItemAnalysis JSON from Gemini: {exc}",
        ) from exc

    analysis = _apply_value_policy(analysis)
    return analysis


@router.post("/generate-liquidation-brief", response_model=LiquidationBriefDTO)
async def generate_liquidation_brief(payload: LiquidationBriefRequest) -> LiquidationBriefDTO:
    if call_gemini_for_liquidation_brief is None:
        raise HTTPException(status_code=501, detail="Liquidation brief generation is not enabled on this server build.")

    if payload.photoJpegBase64:
        try:
            base64.b64decode(payload.photoJpegBase64, validate=True)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=400, detail="photoJpegBase64 is not valid base64") from exc

    prompt = _build_liquidation_brief_prompt(payload)

    try:
        raw_json = await call_gemini_for_liquidation_brief(  # type: ignore[misc]
            prompt=prompt,
            photo_base64=payload.photoJpegBase64,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    # First pass normalize + validate
    try:
        obj = _normalize_liquidation_brief_obj(raw_json=raw_json, request=payload)
        brief = LiquidationBriefDTO.model_validate(obj)
    except ValidationError as ve:
        # One repair attempt with explicit error context
        try:
            repair_prompt = _build_liquidation_brief_repair_prompt(
                original_prompt=prompt,
                raw_json=raw_json,
                validation_error=str(ve),
            )
            repaired = await call_gemini_for_liquidation_brief(  # type: ignore[misc]
                prompt=repair_prompt,
                photo_base64=payload.photoJpegBase64,
            )
            repaired_obj = _normalize_liquidation_brief_obj(raw_json=repaired, request=payload)
            brief = LiquidationBriefDTO.model_validate(repaired_obj)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(
                status_code=502,
                detail=f"Failed to decode LiquidationBriefDTO JSON from Gemini: {ve}",
            ) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=502,
            detail=f"Failed to decode LiquidationBriefDTO JSON from Gemini: {exc}",
        ) from exc

    # Stamp required fields & IDs (belt-and-suspenders)
    now = datetime.now(timezone.utc)
    brief.aiProvider = brief.aiProvider or "gemini"
    brief.aiModel = brief.aiModel or GEMINI_MODEL
    if getattr(brief, "generatedAt", None) is None:
        brief.generatedAt = now
    if brief.schemaVersion != payload.schemaVersion:
        brief.schemaVersion = payload.schemaVersion
    if getattr(brief, "scope", None) in (None, ""):
        brief.scope = payload.scope

    for opt in brief.pathOptions:
        if not getattr(opt, "id", None):
            opt.id = str(uuid4())

    # Preserve request inputs (goal/location/constraints) for downstream steps (Disposition Engine, plan generation)
    if payload.inputs is not None and brief.inputs is None:
        brief.inputs = payload.inputs

    return brief


@router.post("/generate-liquidation-plan", response_model=LiquidationPlanChecklistDTO)
async def generate_liquidation_plan(payload: LiquidationPlanRequest) -> LiquidationPlanChecklistDTO:
    """
    AI-native plan generation.
    Input: LiquidationPlanRequest (chosenPath + brief + optional title/category)
    Output: LiquidationPlanChecklistDTO (ordered operational checklist)
    """
    if call_gemini_for_liquidation_plan is None:
        raise HTTPException(status_code=501, detail="Liquidation plan generation is not enabled on this server build.")

    prompt = _build_liquidation_plan_prompt(payload)

    try:
        raw_json = await call_gemini_for_liquidation_plan(prompt=prompt)  # type: ignore[misc]
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    # First pass normalize + validate
    try:
        obj = _normalize_liquidation_plan_obj(raw_json=raw_json, request=payload)
        plan = LiquidationPlanChecklistDTO.model_validate(obj)
    except ValidationError as ve:
        # One repair attempt with explicit error context
        try:
            repair_prompt = _build_liquidation_plan_repair_prompt(
                original_prompt=prompt,
                raw_json=raw_json,
                validation_error=str(ve),
            )
            repaired = await call_gemini_for_liquidation_plan(prompt=repair_prompt)  # type: ignore[misc]
            repaired_obj = _normalize_liquidation_plan_obj(raw_json=repaired, request=payload)
            plan = LiquidationPlanChecklistDTO.model_validate(repaired_obj)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(
                status_code=502,
                detail=f"Failed to decode LiquidationPlanChecklistDTO JSON from Gemini: {ve}",
            ) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=502,
            detail=f"Failed to decode LiquidationPlanChecklistDTO JSON from Gemini: {exc}",
        ) from exc

    # Server-side stamps / normalization
    if getattr(plan, "createdAt", None) is None:
        plan.createdAt = datetime.now(timezone.utc)

    # Ensure sequential order
    if plan.items:
        for idx, item in enumerate(plan.items):
            if getattr(item, "order", None) is None:
                item.order = idx + 1

    return plan
