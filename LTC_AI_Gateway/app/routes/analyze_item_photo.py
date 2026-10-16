from __future__ import annotations

import base64
import json
import logging
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Request
from pydantic import ValidationError

from app.core import config as ltc_config
from app.core.rate_limiter import rate_limiter
from app.models import AnalyzeItemPhotoRequest, CANONICAL_ITEM_CATEGORIES, ItemAIHints, ItemAnalysis, ValueHints

from app.models_liquidation import (
    LiquidationBriefDTO,
    LiquidationBriefRequest,
    LiquidationMemberSummary,
    LiquidationPathOptionDTO,
    LiquidationPlanChecklistDTO,
    LiquidationPlanRequest,
)
from app.ai.util.time_json import (
    _now_iso_z,
    _parse_llm_json_obj,
    _unwrap_singleton_wrapper,
    _utcnow,
)

from app.ai.normalization.item_analysis import _normalize_item_analysis_json

from app.ai.prompts.item_analysis import (
    _build_item_analysis_repair_prompt,
    build_item_analysis_prompt,
    build_item_analysis_text_prompt,
)

from app.models_disposition import (
    DispositionOutreachComposeRequest,
    DispositionOutreachComposeResponse,
    DispositionPartnersSearchRequest,
    DispositionPartnersSearchResponse,
    PlaceDetailsDTO,
    PlaceDetailsRequest,
    PlaceDetailsResponse,
)

from app.services.gemini_client import (
    GEMINI_MODEL,
    call_gemini_for_item_analysis,
    call_gemini_for_audio_summary,
)

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
# Normalization + repair helpers
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Missing-valuation guidance
# ---------------------------------------------------------------------------

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


def _missing_details_for_category(category: str | None) -> List[str]:
    if not category:
        return ["Brand/maker", "Materials", "Dimensions/size", "Condition", "Any receipts/certificates"]
    return _CATEGORY_MISSING_DETAILS.get(
        category,
        ["Brand/maker", "Materials", "Dimensions/size", "Condition", "Any receipts/certificates"],
    )


_CANONICAL_CATEGORY_LOOKUP: dict[str, str] = {c.lower(): c for c in CANONICAL_ITEM_CATEGORIES}


def _normalize_category(category: str | None) -> str:
    """
    Defensive guard: Gemini is prompted with a closed category list, but the
    response is still an unconstrained string. Collapse any value that
    doesn't match a canonical category (case-insensitively) to "Other" so an
    invented category can never reach the client.
    """
    if not category:
        return "Other"
    return _CANONICAL_CATEGORY_LOOKUP.get(category.strip().lower(), "Other")


# Upper bound on confidence reported when no value could be estimated.
_NOT_ESTIMATED_MAX_CONFIDENCE = 0.20

_NOT_ESTIMATED_NOTE = (
    "Not estimated. The available information was not sufficient for a reasonable resale estimate "
    "of this specific item. Add the missing details and run the analysis again."
)


def _apply_value_policy(analysis: ItemAnalysis) -> ItemAnalysis:
    """
    Enforce:
    - valueHints exists (so the app always receives confidence, notes, and missing details)
    - partial numbers are completed into a range from the numbers provided
    - if the AI provided no numbers, the value stays unset ("Not estimated"): no generic
      category range is substituted
    """
    now_iso = _now_iso_z()

    if analysis.valueHints is None:
        analysis.valueHints = ValueHints(
            valueLow=None,
            estimatedValue=None,
            valueHigh=None,
            currencyCode="USD",
            confidenceScore=_NOT_ESTIMATED_MAX_CONFIDENCE,
            valuationDate=now_iso,
            aiProvider=GEMINI_MODEL,
            aiNotes=_NOT_ESTIMATED_NOTE,
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
        # Leave the numbers unset. Keep any explanation the AI gave.
        vh.confidenceScore = min(
            vh.confidenceScore if vh.confidenceScore is not None else _NOT_ESTIMATED_MAX_CONFIDENCE,
            _NOT_ESTIMATED_MAX_CONFIDENCE,
        )
        vh.aiNotes = vh.aiNotes or _NOT_ESTIMATED_NOTE
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
        "patha": "pathA_maximizePrice",
        "pathb": "pathB_delegateConsign",
        "pathc": "pathC_quickExit",
        "maximizevalue": "pathA_maximizePrice",
        "consign": "pathB_delegateConsign",
        "consignment": "pathB_delegateConsign",
        "quicksale": "pathC_quickExit",
        "needsinfo": "needsInfo",
        "needs_info": "needsInfo",
        "needsmoreinfo": "needsInfo",
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


# Path values the iOS LiquidationPathDTO enum can decode.
_BRIEF_PATHS = ("pathA_maximizePrice", "pathB_delegateConsign", "pathC_quickExit", "donate", "needsInfo")
# needsInfo is a recommendation state, not a disposition alternative, so it never appears in pathOptions.
_OPTION_PATHS = ("pathA_maximizePrice", "pathB_delegateConsign", "pathC_quickExit", "donate")
_EFFORT_VALUES = ("low", "medium", "high", "veryHigh")
# Used only when Gemini omits or garbles an option's effort (required by the iOS decoder).
_DEFAULT_EFFORT_BY_PATH = {
    "pathA_maximizePrice": "high",
    "pathB_delegateConsign": "medium",
    "pathC_quickExit": "low",
    "donate": "low",
}
_PATH_KEYWORDS = (
    ("maximiz", "pathA_maximizePrice"),
    ("diy", "pathA_maximizePrice"),
    ("consign", "pathB_delegateConsign"),
    ("delegat", "pathB_delegateConsign"),
    ("specialist", "pathB_delegateConsign"),
    ("quick", "pathC_quickExit"),
    ("bulk", "pathC_quickExit"),
    ("donat", "donate"),
    ("more info", "needsInfo"),
    ("needs info", "needsInfo"),
)


# Customer-facing approach names. Must match the app's UserFacingTerms.Liquidation.
_APPROACH_NAMES = {
    "pathA_maximizePrice": "Maximize Price",
    "pathB_delegateConsign": "Consignment",
    "pathC_quickExit": "Quick Sale",
    "donate": "Donation",
    "needsInfo": "More Information Needed",
}
_APPROACH_NAME_BY_LETTER = {"A": "Maximize Price", "B": "Consignment", "C": "Quick Sale"}
# "pathB_delegateConsign", "PathB_DelegateConsign", "path_b_delegate_consign"
_RAW_PATH_ID_RE = re.compile(r"\b[Pp]ath[ _-]?([ABCabc])_[A-Za-z_]+\b")
# "Path B", "PathB" (capital letter only, so ordinary prose like "a path a buyer" is untouched)
_PATH_LETTER_RE = re.compile(r"\b[Pp]ath ?([ABC])\b")
_NEEDS_INFO_RE = re.compile(r"\bneedsInfo\b")
# Leading "Path A — " style prefix on an option label.
_LABEL_PATH_PREFIX_RE = re.compile(r"^\s*[Pp]ath ?[ABC]\s*[—–:\-]\s*")


def _customer_text(value: Any) -> Any:
    """Replace internal path identifiers in text a homeowner will read."""
    if not isinstance(value, str):
        return value
    s = _RAW_PATH_ID_RE.sub(lambda m: _APPROACH_NAME_BY_LETTER[m.group(1).upper()], value)
    s = _PATH_LETTER_RE.sub(lambda m: _APPROACH_NAME_BY_LETTER[m.group(1)], s)
    return _NEEDS_INFO_RE.sub(_APPROACH_NAMES["needsInfo"], s)


def _customer_label(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    return _customer_text(_LABEL_PATH_PREFIX_RE.sub("", value)).strip()


def _specialty_source_text(request: LiquidationBriefRequest) -> str:
    """The item text a specialty block may draw brand/model from."""
    parts: List[str] = [request.title or "", request.description or "", request.category or ""]
    ctx = request.setContext
    if ctx:
        parts += [ctx.setName or "", ctx.setType or "", ctx.story or ""]
        for m in ctx.memberSummaries:
            parts += [m.title or "", m.category or ""]
    return " ".join(parts).lower()


def _normalize_specialty(value: Any, request: LiquidationBriefRequest) -> Optional[Dict[str, Any]]:
    """
    Keep a well-formed optional specialty block; drop anything malformed rather
    than failing the Brief. Brand and model survive only when the item text
    actually contains them.
    """
    if not isinstance(value, dict):
        return None

    def _clean(v: Any, max_len: int) -> Optional[str]:
        if not isinstance(v, str):
            return None
        s = " ".join(v.split())
        if not s or s.lower() in {"null", "none", "n/a", "na", "unknown"}:
            return None
        return s[:max_len].strip()

    item_kind = _clean(value.get("itemKind"), 60)

    raw_terms = value.get("detailTerms")
    if isinstance(raw_terms, str):
        raw_terms = [raw_terms]
    terms: List[str] = []
    seen: set = set()
    for t in raw_terms if isinstance(raw_terms, list) else []:
        term = _clean(t, 40)
        if term and term.lower() not in seen:
            seen.add(term.lower())
            terms.append(term)
        if len(terms) == 4:
            break

    source = _specialty_source_text(request)
    brand = _clean(value.get("brand"), 60)
    if brand and brand.lower() not in source:
        brand = None
    model = _clean(value.get("model"), 60)
    if model and model.lower() not in source:
        model = None

    flag = value.get("isSpecialistItem")
    if isinstance(flag, str):
        flag = flag.strip().lower() in {"true", "yes", "1"}
    is_specialist = flag if isinstance(flag, bool) else False

    if not (item_kind or terms or brand or model):
        return None
    return {
        "itemKind": item_kind,
        "detailTerms": terms,
        "brand": brand,
        "model": model,
        "isSpecialistItem": is_specialist,
    }


def _path_from_text(text: Any) -> Optional[str]:
    """Path named by free text, using the earliest keyword: 'Quick Exit (Bulk Buyer/Donation)' -> pathC."""
    if not isinstance(text, str):
        return None
    lowered = text.lower()
    hits = [(lowered.find(k), path) for k, path in _PATH_KEYWORDS if k in lowered]
    return min(hits)[1] if hits else None


def _infer_option_path(opt: Dict[str, Any]) -> Optional[str]:
    """Identify an option's path from its own fields; never from the recommendation."""
    for key in ("path", "pathType", "pathId", "type", "route", "option", "key"):
        val = _normalize_path_value(opt.get(key))
        if val in _BRIEF_PATHS:
            return val
    for key in ("path", "name", "label", "title", "type"):
        val = _path_from_text(opt.get(key))
        if val:
            return val
    return None


def _is_uuid(value: Any) -> bool:
    try:
        UUID(str(value))
        return True
    except (TypeError, ValueError):
        return False


def _coerce_amount(value: Any) -> Optional[float]:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        amount = float(value)
    elif isinstance(value, str):
        try:
            amount = float(value.replace("$", "").replace(",", "").strip())
        except ValueError:
            return None
    else:
        return None
    return amount if amount >= 0 else None


def _normalize_money_dict(np: Dict[str, Any], currency: str) -> Optional[Dict[str, Any]]:
    """Map Gemini's key drift (min/max, mid, ...) onto MoneyRangeDTO; None when no amount is usable."""
    def first(*keys: str) -> Optional[float]:
        for k in keys:
            amount = _coerce_amount(np.get(k))
            if amount is not None:
                return amount
        return None

    low = first("low", "min", "minimum", "lowEstimate", "from")
    high = first("high", "max", "maximum", "highEstimate", "to")
    likely = first("likely", "mid", "expected", "estimate", "typical", "median")
    if low is not None and high is not None and high < low:
        low, high = high, low
    if likely is not None and ((low is not None and likely < low) or (high is not None and likely > high)):
        likely = None
    if low is None and likely is None and high is None:
        return None
    code = np.get("currencyCode")
    return {
        "currencyCode": code if isinstance(code, str) and code else currency,
        "low": low,
        "likely": likely,
        "high": high,
    }


def _brief_request_has_value(request: LiquidationBriefRequest) -> bool:
    """Whether any value estimate was supplied (a genuine 0 counts); mirrors the prompt's VALUATION block."""
    if request.scope == "set" and request.setContext:
        return any(m.unitValue is not None for m in request.setContext.memberSummaries)
    return request.unitValue is not None or request.valuationLikely is not None


def _normalize_liquidation_brief_obj(*, raw_json: str, request: LiquidationBriefRequest) -> Dict[str, Any]:
    """
    Make the backend tolerant of:
    - wrapper keys: {"LiquidationBriefDTO": {...}}
    - missing required top-level fields we can safely infer/stamp (scope, generatedAt)
    - missing pathOptions ids (generate UUIDs pre-validation)
    - enum drift for recommendedPath/pathOptions[].path and effort
    - schemaVersion drift (e.g., "0.0.1" or "1" as string) -> int
    - pathOptions drift: missing "path" or using alternate keys/names -> map to "path";
      options with no identifiable path, repeated paths, or needsInfo are dropped
    - netProceeds drift (string ranges, min/max keys) -> MoneyRangeDTO dict; null when
      the request carries no value estimate
    - missing label -> fill from path
    - actionSteps drift (list of objects) -> list of strings
    """
    import re

    obj_any = _parse_llm_json_obj(raw_json)
    obj_any = _unwrap_singleton_wrapper(obj_any)

    if not isinstance(obj_any, dict):
        raise ValueError("Liquidation brief JSON was not an object.")

    obj: Dict[str, Any] = dict(obj_any)

    # Required fields we can safely infer/stamp before validation
    obj.setdefault("schemaVersion", request.schemaVersion)

    # Coerce schemaVersion to int if model returns a string like "1" or "0.0.1"
    sv = obj.get("schemaVersion")
    if isinstance(sv, str):
        try:
            obj["schemaVersion"] = int(sv.strip())
        except Exception:
            m = re.search(r"(\d+)", sv)
            if m:
                try:
                    obj["schemaVersion"] = int(m.group(1))
                except Exception:
                    obj["schemaVersion"] = request.schemaVersion
            else:
                obj["schemaVersion"] = request.schemaVersion
    elif not isinstance(sv, int):
        obj["schemaVersion"] = request.schemaVersion

    obj.setdefault("scope", request.scope)

    if "generatedAt" not in obj or obj.get("generatedAt") in (None, ""):
        obj["generatedAt"] = datetime.now(timezone.utc).isoformat()

    # Normalize recommended path
    if "recommendedPath" in obj:
        rec = _normalize_path_value(obj.get("recommendedPath"))
        if rec not in _BRIEF_PATHS:
            # An unrecognizable recommendation is never guessed into a selling path.
            rec = _path_from_text(rec) or "needsInfo"
        obj["recommendedPath"] = rec

    currency = request.currencyCode or "USD"

    label_by_path = _APPROACH_NAMES

    def _parse_money_range(s: str) -> dict:
        txt = (s or "").strip()
        if not txt or txt.lower() in {"unknown", "n/a", "na", "tbd"}:
            return {"currencyCode": currency, "low": None, "likely": None, "high": None}

        nums = re.findall(r"(\d+(?:\.\d+)?)", txt.replace(",", ""))
        if not nums:
            return {"currencyCode": currency, "low": None, "likely": None, "high": None}

        values = [float(n) for n in nums]
        if len(values) == 1:
            v = values[0]
            return {"currencyCode": currency, "low": v, "likely": v, "high": v}

        low = values[0]
        high = values[1]
        if high < low:
            low, high = high, low
        likely = round((low + high) / 2.0, 2)
        return {"currencyCode": currency, "low": low, "likely": likely, "high": high}

    # NEW: Normalize actionSteps into list[str]
    if "actionSteps" in obj and isinstance(obj["actionSteps"], list):
        normalized_steps: List[str] = []
        for step in obj["actionSteps"]:
            if isinstance(step, str):
                s = step.strip()
                if s:
                    normalized_steps.append(s)
                continue

            if isinstance(step, dict):
                # common keys: description/text/stepText
                desc = step.get("description") or step.get("text") or step.get("stepText")
                if isinstance(desc, str) and desc.strip():
                    normalized_steps.append(desc.strip())
                else:
                    # fallback: stringify minimal dict
                    normalized_steps.append(str(step))
                continue

            # fallback for numbers/other types
            normalized_steps.append(str(step))

        obj["actionSteps"] = normalized_steps

    def _normalize_proceeds(np: Any) -> Optional[Dict[str, Any]]:
        if isinstance(np, str):
            parsed = _parse_money_range(np)
            return parsed if parsed["low"] is not None else None
        if isinstance(np, (list, tuple)):
            vals = [a for a in (_coerce_amount(v) for v in np) if a is not None]
            if not vals:
                return None
            low, high = min(vals[:2]), max(vals[:2])
            likely = round((low + high) / 2.0, 2) if len(vals) >= 2 else low
            return {"currencyCode": currency, "low": low, "likely": likely, "high": high}
        if isinstance(np, dict):
            return _normalize_money_dict(np, currency)
        return None

    # Normalize pathOptions: one option per identifiable disposition path. An option
    # whose path cannot be identified is dropped, never relabeled as the recommendation.
    if isinstance(obj.get("pathOptions"), list):
        has_value = _brief_request_has_value(request)
        options: List[Dict[str, Any]] = []
        seen_paths: set = set()
        for opt in obj["pathOptions"]:
            if not isinstance(opt, dict):
                continue

            path = _infer_option_path(opt)
            if path not in _OPTION_PATHS or path in seen_paths:
                continue
            seen_paths.add(path)
            opt["path"] = path

            if not _is_uuid(opt.get("id")):
                opt["id"] = str(uuid4())

            label = opt.get("label")
            if not isinstance(label, str) or not label.strip():
                opt["label"] = label_by_path[path]

            effort = _normalize_effort_value(opt.get("effort"))
            opt["effort"] = effort if effort in _EFFORT_VALUES else _DEFAULT_EFFORT_BY_PATH[path]

            # Without any value estimate there is no basis for proceeds.
            opt["netProceeds"] = _normalize_proceeds(opt.get("netProceeds")) if has_value else None

            risks = opt.get("risks")
            if isinstance(risks, str):
                opt["risks"] = [risks] if risks.strip() else []
            elif isinstance(risks, list):
                opt["risks"] = [str(r) for r in risks if r is not None and str(r).strip()]
            else:
                opt["risks"] = []

            for key in ("timeEstimate", "logisticsNotes"):
                val = opt.get(key)
                if val is not None and not isinstance(val, str):
                    opt[key] = str(val)

            options.append(opt)
        obj["pathOptions"] = options

    # Ensure lists exist if omitted (to avoid nulls)
    if obj.get("pathOptions") is None:
        obj["pathOptions"] = []
    if obj.get("actionSteps") is None:
        obj["actionSteps"] = []
    if obj.get("missingDetails") is None:
        obj["missingDetails"] = []
    if obj.get("assumptions") is None:
        obj["assumptions"] = []

    # Homeowner-facing text never shows internal path identifiers.
    obj["reasoning"] = _customer_text(obj.get("reasoning"))
    for key in ("actionSteps", "missingDetails", "assumptions"):
        if isinstance(obj.get(key), list):
            obj[key] = [_customer_text(s) for s in obj[key]]
    for opt in obj["pathOptions"]:
        if not isinstance(opt, dict):
            continue
        opt["label"] = _customer_label(opt.get("label")) or label_by_path.get(opt.get("path"), opt.get("label"))
        for key in ("timeEstimate", "logisticsNotes"):
            opt[key] = _customer_text(opt.get(key))
        if isinstance(opt.get("risks"), list):
            opt["risks"] = [_customer_text(r) for r in opt["risks"]]

    # Optional metadata: malformed values are dropped, never fatal.
    obj["specialty"] = _normalize_specialty(obj.get("specialty"), request)

    return obj



_PLAN_ACTIONS = {"findHelp", "findSpecialtyHelp"}
_PLAN_GROUPS = {"luxury", "contemporary", "donate", "discard", "other"}
# Safety bound against runaway output, not a target: prompts ask for 3 to 6 steps
# (5 to 9 for a closet lot).
_PLAN_MAX_STEPS = 12
# Internal partner-type codes the earlier Clothing prompt asked Gemini to cite.
_PARTNER_TYPE_NOTE_RE = re.compile(r"\s*\(?\s*partnerType\s*:\s*[A-Za-z_]+\s*\)?")
_LUXURY_HUB_CODE_RE = re.compile(r"\bluxury_hub_mailin\b")


def _plan_text(value: Any, max_len: int) -> Optional[str]:
    """Homeowner-facing Plan text without identifiers or internal codes."""
    if not isinstance(value, str):
        return None
    s = _customer_text(value)
    s = _PARTNER_TYPE_NOTE_RE.sub("", s)
    s = _LUXURY_HUB_CODE_RE.sub("luxury mail-in consignment", s)
    s = " ".join(s.split()).strip()
    return s[:max_len].rstrip() if s else None


def _step_tokens(text: str) -> set:
    return set(re.findall(r"[a-z0-9]+", text.lower()))


def _is_repeated_step(tokens: set, earlier: List[set]) -> bool:
    """
    Exact repeats, or near-identical wording (85%+ shared words). Deliberately
    conservative: steps that differ in what or who they concern are kept.
    """
    for prev in earlier:
        if tokens == prev:
            return True
        if len(tokens) >= 4 and len(prev) >= 4:
            if len(tokens & prev) / len(tokens | prev) >= 0.85:
                return True
    return False


def _normalize_liquidation_plan_obj(*, raw_json: str, request: LiquidationPlanRequest) -> Dict[str, Any]:
    """
    Tolerate wrapper keys and minor drift, then clean the checklist:
    - steps given as strings or with alternate text keys
    - identifiers and internal codes removed from text and detail
    - unknown action/group values dropped (group only for closet lots)
    - repeated steps removed, order renumbered, new steps unchecked
    Raises ValueError when no usable step remains, so the caller can repair or fail.
    """
    obj_any = _parse_llm_json_obj(raw_json)
    obj_any = _unwrap_singleton_wrapper(obj_any)

    if not isinstance(obj_any, dict):
        raise ValueError("Liquidation plan JSON was not an object.")

    obj: Dict[str, Any] = dict(obj_any)

    sv = obj.get("schemaVersion")
    if not isinstance(sv, int) or isinstance(sv, bool):
        obj["schemaVersion"] = request.schemaVersion
    if "createdAt" not in obj or obj.get("createdAt") in (None, ""):
        obj["createdAt"] = datetime.now(timezone.utc).isoformat()

    closet_lot = _plan_is_closet_lot(request)
    raw_items = obj.get("items")
    if not isinstance(raw_items, list):
        raw_items = []

    steps: List[Dict[str, Any]] = []
    seen: List[set] = []
    for raw in raw_items:
        if isinstance(raw, str):
            raw = {"text": raw}
        if not isinstance(raw, dict):
            continue
        text = _plan_text(raw.get("text") or raw.get("step") or raw.get("title") or raw.get("description"), 240)
        if not text:
            continue
        tokens = _step_tokens(text)
        if not tokens or _is_repeated_step(tokens, seen):
            continue
        seen.append(tokens)

        detail = _plan_text(raw.get("detail"), 300)
        if detail and _step_tokens(detail) == tokens:
            detail = None
        action = raw.get("action") if raw.get("action") in _PLAN_ACTIONS else None
        group = raw.get("group") if closet_lot and raw.get("group") in _PLAN_GROUPS else None

        steps.append({
            "order": len(steps) + 1,
            "text": text,
            "detail": detail,
            "action": action,
            "group": group,
            "isCompleted": False,
            "completedAt": None,
            "userNotes": None,
        })
        if len(steps) == _PLAN_MAX_STEPS:
            break

    if not steps:
        raise ValueError("Liquidation plan contained no usable steps.")

    obj["items"] = steps
    obj["focus"] = _plan_text(obj.get("focus"), 240)
    return obj


# ---------------------------------------------------------------------------
# Liquidation prompt helpers
# ---------------------------------------------------------------------------
def _format_money_or_not_estimated(value: Optional[float], currency: str) -> str:
    """A missing value is 'not estimated'; a genuine 0 is shown as 0."""
    if value is None:
        return "not estimated"
    return f"{value:,.2f} {currency}"


def _brief_item_valuation_block(payload: LiquidationBriefRequest, currency: str) -> str:
    """Valuation context for a single-item brief, built only from supplied request data."""
    qty = payload.quantity or 1
    unit = payload.unitValue if payload.unitValue is not None else payload.valuationLikely
    if unit is None:
        return (
            "VALUATION:\n"
            "- Estimated unit resale value: not estimated\n"
            "- No value estimate is available. Do NOT invent one or assume the item has little value.\n"
        )

    lines = [
        "VALUATION (decision support, not a guaranteed selling price):",
        f"- Estimated unit resale value: {_format_money_or_not_estimated(unit, currency)}",
        f"- Estimated total for quantity {qty}: {_format_money_or_not_estimated(unit * qty, currency)}",
    ]
    # Include the AI range only while it still describes the current value
    # (whole-dollar comparison, matching the app's value field precision).
    likely = payload.valuationLikely
    if (likely is not None and round(likely) == round(unit)
            and payload.valuationLow is not None and payload.valuationHigh is not None):
        lines.append(
            f"- AI unit resale range: {_format_money_or_not_estimated(payload.valuationLow, currency)}"
            f" to {_format_money_or_not_estimated(payload.valuationHigh, currency)}"
        )
    return "\n".join(lines) + "\n"


def _brief_set_valuation_line(members: List[LiquidationMemberSummary], currency: str) -> str:
    """Known subtotal vs. incomplete total for a set; missing member values are never treated as 0."""
    valued = [m for m in members if m.unitValue is not None]
    missing = len(members) - len(valued)
    if not valued:
        return "- Set value: not estimated (no member has a value estimate). Do NOT invent one or assume low value.\n"
    subtotal = sum((m.unitValue or 0.0) * (m.quantity or 1) for m in valued)
    if missing == 0:
        return f"- Estimated set total (all members valued): {_format_money_or_not_estimated(subtotal, currency)}\n"
    return (
        f"- Known subtotal for {len(valued)} of {len(members)} members: "
        f"{_format_money_or_not_estimated(subtotal, currency)}. "
        f"{missing} member(s) not estimated, so the full set value is INCOMPLETE and may be higher. "
        "Do not treat this subtotal as the set's total value or assume unvalued members are worthless.\n"
    )


def _build_liquidation_brief_prompt(payload: LiquidationBriefRequest) -> str:
    title = payload.title or "Untitled Set"
    description = payload.description or ""
    category = payload.category or "Uncategorized"
    qty = payload.quantity or 1
    currency = payload.currencyCode or "USD"

    goal = payload.inputs.goal if payload.inputs and payload.inputs.goal else "balanced"
    location = payload.inputs.locationHint if payload.inputs else None

    set_block = ""
    if payload.scope == "set" and payload.setContext:
        ctx = payload.setContext

        members = ""
        if ctx.memberSummaries:
            members = "\n".join(
                f"- {m.title} | {m.category} | qty={m.quantity or 1} | unit≈{_format_money_or_not_estimated(m.unitValue, currency)}"
                for m in ctx.memberSummaries[:30]
            )

        set_block = f"""
SET CONTEXT:
- Set type: {ctx.setType}
- Sell-together preference: {ctx.sellTogetherPreference}
- Completeness: {ctx.completeness}

SET STORY / METADATA:
{ctx.story or "(none)"}

MEMBER SUMMARY:
{members or "(none)"}

SET VALUATION:
{_brief_set_valuation_line(ctx.memberSummaries, currency) if ctx.memberSummaries else "- Set value: not estimated"}
"""

    return f"""You are an expert estate liquidation assistant.
Return STRICT JSON ONLY matching LiquidationBriefDTO. No markdown.

IMPORTANT:
- Return a FLAT JSON object (no wrapper key).
- Do NOT nest under extra keys.

Context:
- Scope: {payload.scope}
- Title: {title}
- Description: {description}
- Category: {category}
- Quantity: {qty}
- Goal: {goal}
- Location: {location or "none"}
- Currency: {currency}

{set_block}
{"" if (payload.scope == "set" and payload.setContext) else _brief_item_valuation_block(payload, currency)}
Rules:
- Always include: schemaVersion, scope, generatedAt, recommendedPath, reasoning, pathOptions, actionSteps.
- recommendedPath MUST be one of:
  pathA_maximizePrice | pathB_delegateConsign | pathC_quickExit | donate | needsInfo
- Path identifiers belong ONLY in recommendedPath and pathOptions[].path. The homeowner reads
  reasoning, label, risks, and logisticsNotes: never write an identifier or "Path A/B/C" there.
  Refer to approaches as Maximize Price, Consignment, Quick Sale, or Donation.
- reasoning: two or three plain sentences on why the recommended approach fits this item.
- When recommendedPath is needsInfo, missingDetails MUST list the specific facts needed.

PATH OPTIONS (pathOptions array):
- Include exactly one option for EACH of pathA_maximizePrice, pathB_delegateConsign, and
  pathC_quickExit. Add one donate option only when donation is a realistic choice.
- Never repeat a path. Never include needsInfo in pathOptions; needsInfo is only a
  recommendedPath value.
- Every option MUST use exactly these field names:
  {{"id": "<UUID string>",
    "path": "pathA_maximizePrice | pathB_delegateConsign | pathC_quickExit | donate",
    "label": "<2 to 5 words: how to pursue this approach for THIS item, e.g. Specialist camera consignment>",
    "netProceeds": {{"currencyCode": "{currency}", "low": <number or null>, "likely": <number or null>, "high": <number or null>}} or null,
    "effort": "low | medium | high | veryHigh",
    "timeEstimate": "<string>" or null,
    "risks": ["<string>"],
    "logisticsNotes": "<string>" or null}}

NET PROCEEDS:
- netProceeds is the COARSE range the owner would likely keep from that path for the whole
  item or set (quantity included) AFTER typical selling costs: marketplace or auction fees,
  consignment commission, shipping, and discounts for selling quickly. It is not the item's value.
- When a value estimate is supplied, give a range for each selling path that reflects that
  path's costs, effort, and uncertainty. Selling costs normally keep net proceeds below the
  estimated value; a quick exit usually nets the least.
- For a donate option, set netProceeds to null.
- Treat any supplied value as decision support, not a guaranteed selling price. Weigh likely
  net proceeds against effort, costs, and uncertainty for each path.
- If the value is not estimated, do not invent one: set netProceeds to null for every option
  and recommend needsInfo unless the item clearly has no resale market.
- If a set total is INCOMPLETE, base proceeds only on the known subtotal, say it is partial,
  and do not recommend donate solely because the known subtotal is low.

SPECIALTY (optional "specialty" object; describes the item, it is not a recommendation):
  {{"itemKind": "<generic noun phrase of at most 6 words, e.g. film camera, designer handbag, oil painting>",
    "detailTerms": ["<up to 4 short identifying terms>"],
    "brand": "<brand or maker>" or null,
    "model": "<model name or number>" or null,
    "isSpecialistItem": true | false}}
- Use ONLY the title, description, category, and set details above. Never guess.
- brand and model: only when they appear in that text; otherwise null.
- isSpecialistItem: true when dealers or consignors who specialize in this kind of item exist
  and would likely serve the owner better than general resale.
- Never include business names, prices, or people's names. If unsure, set "specialty" to null.
"""

# Plan v2 strategy guidance: what a good checklist covers for each chosen approach.
_PLAN_STRATEGY_GUIDANCE = {
    "pathA_maximizePrice": (
        "The owner sells the item themselves for the best price. Cover the most promising selling "
        "channel for THIS item, the preparation buyers in that channel actually expect, how to judge "
        "offers against the Brief's estimate, and safe payment and shipping or pickup."
    ),
    "pathB_delegateConsign": (
        "A business sells the item for the owner. Cover finding consignors or specialist dealers suited "
        "to THIS item, confirming they will accept it before handing it over, comparing commission, "
        "payout timing, and pricing control, preparing the handoff, and keeping the written agreement."
    ),
    "pathC_quickExit": (
        "The owner wants the item gone soon with little effort. Cover a practical channel, a realistic "
        "asking price informed by the Brief's estimate, transaction safety, and finishing promptly."
    ),
    "donate": (
        "The owner gives the item away. Cover choosing a recipient that takes this kind of item, "
        "confirming they will accept it, arranging drop-off or pickup, and getting a receipt when useful."
    ),
}

# Brief assumptions that describe how the Brief was made, not the item.
_NON_ITEM_ASSUMPTION_PREFIXES = ("local fallback", "backend error", "value not estimated")


def _plan_selected_option(req: LiquidationPlanRequest) -> Optional[LiquidationPathOptionDTO]:
    """The option the owner chose: sent explicitly by Plan v2 clients, else found in the Brief."""
    if req.selectedOption is not None and req.selectedOption.path == req.chosenPath:
        return req.selectedOption
    return next((o for o in req.brief.pathOptions if o.path == req.chosenPath), None)


def _plan_is_closet_lot(req: LiquidationPlanRequest) -> bool:
    """Pile-by-pile clothing semantics apply to clothing SETS (closet lots), never to a single garment."""
    if req.scope != "set":
        return False
    names = {_norm(req.category or "")}
    if req.setContext is not None:
        names.add(_norm(req.setContext.setType or ""))
    return bool(names & {"clothing", "closet lot"})


def _plan_money(value: Optional[float], currency: str) -> str:
    return f"{value:,.0f} {currency}" if value is not None else "not estimated"


def _plan_option_block(opt: Optional[LiquidationPathOptionDTO], currency: str) -> str:
    if opt is None:
        return "- (The Brief has no details for this approach.)\n"
    lines = []
    label = _customer_label(opt.label)
    if label:
        lines.append(f"- Specific recommendation: {label}")
    np_ = opt.netProceeds
    if np_ is not None and (np_.low is not None or np_.high is not None):
        lines.append(
            f"- Brief's rough net estimate (advisory, not a price): "
            f"{_plan_money(np_.low, currency)} to {_plan_money(np_.high, currency)}"
        )
    lines.append(f"- Effort: {opt.effort}")
    if opt.timeEstimate:
        lines.append(f"- Time: {_customer_text(opt.timeEstimate)}")
    if opt.risks:
        lines.append("- Risks: " + "; ".join(_customer_text(r) for r in opt.risks[:6]))
    if opt.logisticsNotes:
        lines.append(f"- Logistics: {_customer_text(opt.logisticsNotes)}")
    return "\n".join(lines) + "\n"


def _plan_known_block(req: LiquidationPlanRequest, currency: str) -> str:
    """What LTC already has, so the checklist does not ask the owner to recreate it."""
    lines: List[str] = [f"- Name: {req.title or 'Untitled'}", f"- Category: {req.category or 'Uncategorized'}"]
    ic = req.itemContext
    if ic is not None:
        if ic.description and ic.description.strip():
            lines.append(f"- Saved description: {' '.join(ic.description.split())[:1200]}")
        if ic.quantity:
            lines.append(f"- Quantity: {ic.quantity}")
        if ic.valuationLow is not None or ic.valuationHigh is not None:
            lines.append(
                f"- Preliminary AI value range per unit (advisory): "
                f"{_plan_money(ic.valuationLow, currency)} to {_plan_money(ic.valuationHigh, currency)}"
            )
        elif ic.unitValue is not None:
            lines.append(f"- Estimated value per unit (advisory): {_plan_money(ic.unitValue, currency)}")
        else:
            lines.append("- Value: not estimated")
        if ic.valuationNotes and ic.valuationNotes.strip():
            lines.append(f"- Valuation notes: {' '.join(ic.valuationNotes.split())[:400]}")
        if ic.photoCount is not None:
            lines.append(f"- Photos already saved in LTC: {ic.photoCount}")
        if ic.documentCount:
            types = ", ".join(t for t in ic.documentTypes[:6] if t) or "unspecified"
            lines.append(f"- Supporting documents already saved: {ic.documentCount} ({types})")
        if ic.hasAudioStory:
            lines.append("- An audio story about the item is saved in LTC")

    sc = req.setContext
    if sc is not None:
        lines.append(f"- Set type: {sc.setType or 'unspecified'}")
        if sc.sellTogetherPreference:
            lines.append(f"- Sell-together preference: {sc.sellTogetherPreference}")
        if sc.completeness:
            lines.append(f"- Completeness: {sc.completeness}")
        if sc.story and sc.story.strip():
            lines.append(f"- Set notes: {' '.join(sc.story.split())[:800]}")
        if sc.memberSummaries:
            lines.append(f"- Members already listed in LTC ({len(sc.memberSummaries)}):")
            for m in sc.memberSummaries[:30]:
                photos = f" | photos saved: {m.photoCount}" if m.photoCount is not None else ""
                lines.append(
                    f"  - {m.title or 'Untitled'} | {m.category or 'Uncategorized'} | qty {m.quantity or 1}"
                    f" | value each {_plan_money(m.unitValue, currency)}{photos}"
                )
            counted = [m.photoCount for m in sc.memberSummaries if m.photoCount is not None]
            if counted:
                lines.append(f"- Photos already saved across listed members: {sum(counted)}")

    sp = req.brief.specialty
    if sp is not None:
        if sp.itemKind:
            lines.append(f"- Kind of item: {sp.itemKind}")
        if sp.brand:
            lines.append(f"- Brand or maker: {sp.brand}")
        if sp.model:
            lines.append(f"- Model: {sp.model}")
        if sp.detailTerms:
            lines.append(f"- Identifying details: {', '.join(sp.detailTerms)}")
        if sp.isSpecialistItem:
            lines.append("- Specialist dealers or consignors exist for this kind of item")
    return "\n".join(lines) + "\n"


def _plan_unconfirmed_block(req: LiquidationPlanRequest) -> str:
    facts = [_customer_text(m) for m in (req.brief.missingDetails or []) if m and m.strip()]
    facts += [
        _customer_text(a) for a in (req.brief.assumptions or [])
        if a and a.strip() and not a.strip().lower().startswith(_NON_ITEM_ASSUMPTION_PREFIXES)
    ]
    return "\n".join(f"- {f}" for f in facts[:12]) + "\n" if facts else "- (none recorded)\n"


_PLAN_OUTPUT_SCHEMA = """Return STRICT JSON ONLY (no markdown, no wrapper key):
{
  "schemaVersion": 2,
  "createdAt": "ISO-8601 datetime",
  "focus": "<one plain sentence: how this plan carries out the chosen approach for this item>",
  "items": [
    {"order": 1, "text": "<step>", "detail": "<one short sentence>" or null,
     "action": "findHelp" | "findSpecialtyHelp" | null,%s
     "isCompleted": false, "completedAt": null, "userNotes": null}
  ]
}"""


def _build_liquidation_plan_prompt(req: LiquidationPlanRequest) -> str:
    """
    Plan v2: a short, item-specific checklist for the approach the owner chose.
    Works with app 1.2 requests too (no selectedOption/itemContext): the chosen
    option is then found in the Brief and only title/category are known.
    """
    brief = req.brief
    chosen = req.chosenPath
    currency = (req.itemContext.currencyCode if req.itemContext and req.itemContext.currencyCode else None) \
        or next((o.netProceeds.currencyCode for o in brief.pathOptions if o.netProceeds), None) or "USD"

    chosen_name = _APPROACH_NAMES.get(chosen, "the chosen approach")
    recommended_name = _APPROACH_NAMES.get(brief.recommendedPath, "")
    is_recommended = req.isRecommended if req.isRecommended is not None else (brief.recommendedPath == chosen)
    provisional = brief.recommendedPath == "needsInfo"
    closet_lot = _plan_is_closet_lot(req)

    if provisional:
        choice_line = (
            f"The owner chose {chosen_name}. The Brief could not recommend an approach yet because key facts "
            "are missing (see UNCONFIRMED), so this plan is PROVISIONAL."
        )
    elif is_recommended:
        choice_line = f"The owner chose {chosen_name}, which the Brief recommended."
    else:
        choice_line = (
            f"The owner chose {chosen_name}. The Brief recommended {recommended_name}, but the owner's choice "
            f"governs: plan ONLY for {chosen_name} and do not steer back to {recommended_name}."
        )

    guidance = _PLAN_STRATEGY_GUIDANCE.get(chosen, "Plan the next practical steps for the chosen approach.")

    provisional_rules = ""
    if provisional:
        provisional_rules = """
PROVISIONAL PLAN:
- Make the first step resolve the most important UNCONFIRMED fact in the way this approach needs it.
- Word later steps so they still hold if that fact turns out differently.
"""

    set_rules = ""
    if req.scope == "set" and not closet_lot:
        set_rules = """
SET:
- Members are already listed in LTC; do not ask the owner to inventory them again.
- Early on, settle whether the set sells together or in parts, guided by the sell-together
  preference and completeness. A set may need a few more steps than a single item.
"""

    closet_rules = ""
    group_field = ""
    if closet_lot:
        group_field = '\n     "group": "luxury" | "contemporary" | "donate" | "discard" | "other",'
        closet_rules = """
CLOSET LOT (a clothing set):
- Work pile by pile; never itemize individual garments.
- Begin by splitting the lot: luxury/designer, better contemporary, everyday, worn or damaged, plus a
  small "check the label" pile for anything uncertain.
- Luxury/designer pieces usually do best with a specialist luxury consignor that accepts items by mail.
  Do not donate or quick-sell anything until designer pieces have been ruled out.
- Better contemporary pieces: resale apps or local consignment. Everyday pieces: donation or thrift.
  Worn or damaged pieces: textile recycling or discard.
- Shape the piles' channels to the chosen approach.
- Give EVERY step a "group" naming its pile: luxury, contemporary, donate, discard, or other.
- A lot usually needs 5 to 9 steps.
"""

    return f"""You are an expert estate liquidation assistant writing a homeowner's checklist.

{_PLAN_OUTPUT_SCHEMA % group_field}

CHOSEN APPROACH:
{choice_line}
What a good {chosen_name} plan covers: {guidance}

THE CHOSEN OPTION (from the Brief):
{_plan_option_block(_plan_selected_option(req), currency)}
BRIEF REASONING (context only):
{_customer_text(brief.reasoning)}

KNOWN (already recorded in LTC; do not ask the owner to recreate any of this):
{_plan_known_block(req, currency)}
UNCONFIRMED (facts the Brief could not verify; anything the saved description or notes call untested,
unknown, or not recorded is unconfirmed too):
{_plan_unconfirmed_block(req)}{provisional_rules}{set_rules}{closet_rules}
STEP RULES:
- Usually 3 to 6 steps. Use fewer when fewer are enough; never pad to reach a count.
- Every step must resolve an uncertainty that matters for this approach, or move the item closer to
  being sold, consigned, or donated.
- "text": one short imperative sentence (aim for under 20 words) that produces a concrete result.
- "detail": one short sentence with the specific why or how, or null when there is nothing useful to add.
- Draw on the item's own description and kind; knowledge specific to this kind of item belongs in the steps.
- Do not ask the owner to photograph, describe, measure, inventory, identify, or research anything listed
  under KNOWN. Ask for a specific missing photo or fact only when it changes what a buyer, consignor, or
  recipient will do, and only once, in the step where it matters.
- Treat value figures as rough advisory ranges. Suggest independent verification (such as an appraisal or
  authentication) only when the value is high or uncertain enough to change the outcome.
- Never name a specific business, consignor, dealer, auction house, or resale website. Describe the kind of
  business instead (LTC's Find Help locates real ones). Widely used public marketplaces may be named as
  selling channels.
- Do not invent appraisals, authentication results, acceptance, prices, commissions, deadlines, price
  floors, or guaranteed proceeds. Mention price only as the Brief's estimate range for this approach,
  called an estimate, and never add precision it does not have.
- Combine small related actions into one step. No filler: no "review the brief", "confirm item details",
  "mark complete", or "record the outcome" steps.
- "action": "findHelp" when the step means finding a local business or organization (consignor, dealer,
  buyer, donation center, estate service); "findSpecialtyHelp" when it needs a specialist in this kind of
  item; otherwise null.
- Write for the homeowner. Never write path identifiers, field names, or internal codes.
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
def _build_liquidation_brief_repair_prompt(*, original_prompt: str, raw_json: str, validation_error: str) -> str:
    """
    Repair prompt for LiquidationBriefDTO JSON.

    We reuse the plan repair prompt builder because it already provides:
    - strict JSON-only instruction
    - the original prompt context
    - the validation error context
    - the raw JSON to repair

    The model just needs to return JSON that matches LiquidationBriefDTO.
    """
    return _build_liquidation_plan_repair_prompt(
        original_prompt=original_prompt,
        raw_json=raw_json,
        validation_error=validation_error,
    )



# ---------------------------------------------------------------------------
# Disposition Engine (v1) — backend-first execution support
# ---------------------------------------------------------------------------

_DISPOSITION_MATRIX_PATH = Path(__file__).resolve().parents[1] / "config" / "disposition_matrix.v1.json"

# Partner types served from curated lists, never from Places.
_CURATED_PARTNER_TYPES = {"luxury_hub_mailin"}

# App 1.1 hardcodes this point (downtown Boise) in every Local Help request.
_LEGACY_APP_DEFAULT_CENTER = (43.6150, -116.2023)

# Shared rate-limiter key for the per-instance daily Places call budget.
_PLACES_GLOBAL_BUDGET_KEY = "__all_devices__"

# A business whose Google data does not show the searched type is kept only
# if it was among Google's top N matches for the query.
_UNCONFIRMED_TOP_RANK = 5

_LOCAL_DISCOVERY_NOTICES = {
    "no_results": "No matching local businesses were found in this area. Try a larger radius or a nearby city.",
    "unavailable": "Local business search is temporarily unavailable. Please try again later.",
    "disabled": "Local business search is temporarily unavailable. Please try again later.",
    "limited": "Local business search has reached its usage limit for now. Please try again later.",
}


class _PlacesBudgetExhausted(Exception):
    """The per-instance daily Places call budget is used up."""


logger = logging.getLogger(__name__)



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


_GOAL_ALIASES = {
    "maximizeprice": "maximize_price",
    "maximize_value": "maximize_price",
    "minimizework": "min_effort",
    "minimize_work": "min_effort",
}


def _canonical_goal(goal: Optional[str]) -> Optional[str]:
    if goal is None:
        return None
    g = goal.strip().lower()
    return _GOAL_ALIASES.get(g, g)


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
            # A "*" inside a list admits a missing value (same rule as valueBand UNKNOWN).
            return isinstance(when_val, list) and "*" in when_val
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
        allowed = when.get("valueBand")
        if sc.valueBand in (None, "UNKNOWN"):
            # An unknown value must not be treated as a known low value: it matches
            # any rule that admits "*".
            if not (allowed in (None, "*") or (isinstance(allowed, list) and "*" in allowed)):
                return False
        elif not match_value(allowed, sc.valueBand):
            return False

    # bulky / fragile
    if "bulky" in when:
        if not match_value(when.get("bulky"), sc.bulky):
            return False
    if "fragile" in when:
        if not match_value(when.get("fragile"), sc.fragile):
            return False

    # goals (iOS sends camelCase, e.g. "maximizePrice"; the matrix uses snake_case)
    if "goals" in when:
        if not match_value(when.get("goals"), _canonical_goal(sc.goal), normalize_text=True):
            return False

    # chosenPaths (case-insensitive: iOS sends "donate", older docs say "DONATE")
    if "chosenPaths" in when:
        if not match_value(when.get("chosenPaths"), req.chosenPath, normalize_text=True):
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
    if partner_type in ("dealer", "antique_dealer", "rug_dealer"):
        return [
            "Do you buy outright, take items on consignment, or both?",
            "Do you handle items like mine? Can I send photos first?",
            "How do you arrive at an offer, and what fees apply?",
            *common,
        ][:6]
    if partner_type == "estate_jeweler":
        return [
            "Do you buy estate jewelry outright or offer consignment?",
            "Is there a fee for an evaluation or a written appraisal?",
            "How do you test and price metals and stones?",
            *common,
        ][:6]
    if partner_type == "electronics_resale":
        return [
            "Which brands, models, and conditions do you buy?",
            "Do you wipe data, or should I reset devices first?",
            "How is the offer determined and paid?",
            *common,
        ][:6]
    if partner_type == "recycling":
        return [
            "Which items do you accept, and is there a fee?",
            "Do you provide certificates of data destruction?",
            "Do you offer drop-off hours or pickup?",
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

_INTENT_DISCLAIMER = (
    "Business details come from Google Maps or LTC's reviewed list and may change. "
    "Appearing here does not mean a business will accept your item; confirm directly before sending anything."
)
# Enough specialist matches from the first query that a second query adds little.
_INTENT_ENOUGH_SPECIALISTS = 5
_INTENT_MAX_RESULTS = 10
_DIRECTORY_EVIDENCE_KEYS = {
    "consignment": "consignment",
    "buys_outright": "buysOutright",
    "auction": "auction",
    "marketplace": "marketplace",
    "donations": "donations",
}


def _evidence_partner_type(evidence: Dict[str, str]) -> str:
    """Badge text from what the listing itself says, never from the query that found it."""
    for key, ptype in (("consignment", "consignment"), ("auction", "auction"),
                       ("donations", "donation"), ("buysOutright", "buyer")):
        if evidence.get(key) == "mentioned":
            return ptype
    return "business"


def _intent_partner_search(payload: DispositionPartnersSearchRequest, request: Request) -> DispositionPartnersSearchResponse:
    """
    B1 specialty discovery for a homeowner-reviewed Search Intent.
    - local/regional: at most two Google Places text queries naming the place
    - national: LTC's curated directory only (no Places calls)
    Results come only from those two sources. Nothing about acceptance is
    inferred; the query text and item details are never logged.
    """
    from app.services.partner_discovery import intent as intent_mod
    from app.services.partner_discovery.directory import match_directory
    from app.services.partner_discovery.factory import (
        PartnerDiscoveryConfigError,
        get_partner_discovery_provider,
        running_on_cloud_run,
    )
    from app.services.partner_discovery.providers import PartnerDiscoveryQuery, PartnerDiscoveryUnavailable

    loc = payload.location
    try:
        intent = intent_mod.validate_intent(
            payload.searchIntent, city=loc.city, region=loc.region, country_code=loc.countryCode
        )
    except intent_mod.IntentValidationError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    radius = int(loc.radiusMiles or 25)
    results: list[dict] = []
    discovery_status: Optional[str] = None
    places_calls = 0

    # ---- Google Places (local / regional) ----
    queries = intent_mod.build_queries(intent)
    if queries:
        center_lat = loc.latitude
        center_lng = loc.longitude
        if center_lat is None or center_lng is None:
            center_lat = center_lng = None
        elif (abs(center_lat - _LEGACY_APP_DEFAULT_CENTER[0]) < 1e-6
              and abs(center_lng - _LEGACY_APP_DEFAULT_CENTER[1]) < 1e-6
              and _norm(loc.city) != "boise"):
            center_lat = center_lng = None

        provider = None
        if ltc_config.DISABLE_PLACES:
            discovery_status = "disabled"
        else:
            try:
                provider = get_partner_discovery_provider(stub_fn=_stub_places_search)
            except PartnerDiscoveryConfigError as exc:
                logger.error("Partner discovery not configured: %s", exc)
                discovery_status = "unavailable"
        if provider is not None:
            device_id = getattr(request.state, "device_id", None) or "unknown"
            allowed, _retry = rate_limiter.check_daily(
                device_id=device_id, scope="places-search",
                limit=ltc_config.PLACES_SEARCHES_PER_DEVICE_DAY_LIMIT,
            )
            if not allowed:
                provider, discovery_status = None, "limited"

        pool: dict[str, dict] = {}
        for q in queries if provider is not None else []:
            if not provider.is_stub:
                allowed, _retry = rate_limiter.check_daily(
                    device_id=_PLACES_GLOBAL_BUDGET_KEY, scope="places-calls",
                    limit=ltc_config.PLACES_PER_DAY_LIMIT,
                )
                if not allowed:
                    discovery_status = "limited"
                    break
            try:
                places_calls += 1
                candidates = provider.search(PartnerDiscoveryQuery(
                    query=q.text,
                    city=intent.city,
                    region=intent.region_code,
                    radius_miles=radius,
                    partner_type=q.partner_type,
                    center_lat=center_lat,
                    center_lng=center_lng,
                    language_code="en",
                    region_code="US",
                    use_location_bias=intent.geo_scope == "local",
                ))
            except PartnerDiscoveryUnavailable as exc:
                logger.error("Intent discovery unavailable reason=%s", exc.reason)
                discovery_status = "limited" if exc.reason == "upstream_quota" else "unavailable"
                break
            for c in candidates:
                pid = c.get("partnerId")
                if pid and pid not in pool and not intent_mod.is_excluded(c):
                    pool[pid] = c
            specialists = sum(
                1 for c in pool.values()
                if intent_mod.relevance(c, intent)["level"] == "specialist"
                and intent_mod.area_match(c, intent, radius) != "outside_area"
            )
            if specialists >= _INTENT_ENOUGH_SPECIALISTS:
                break

        for c in pool.values():
            if running_on_cloud_run() and str(c.get("partnerId", "")).startswith("stub:"):
                continue
            evidence = intent_mod.service_evidence(c)
            rel = intent_mod.relevance(c, intent)
            area = intent_mod.area_match(c, intent, radius)
            score = intent_mod.rank_score(
                provider_rank=c.get("providerRank"), rel=rel, distance=c.get("distanceMiles"),
                radius_miles=radius, area=area,
            )
            why = intent_mod.why_text(rel, area, intent)
            contact = dict(c.get("contact") or {})
            contact["website"] = c.get("websiteUri")  # the business's own site only
            results.append({
                "partnerId": c.get("partnerId"),
                "name": c.get("name"),
                "partnerType": _evidence_partner_type(evidence),
                "contact": contact,
                "distanceMiles": c.get("distanceMiles"),
                "rating": c.get("rating"),
                "userRatingsTotal": c.get("userRatingsTotal"),
                "trust": {"trustScore": score, "claimLevel": "listing", "gates": [], "signals": []},
                "ranking": {"score": score, "reasons": [why]},
                "whyRecommended": why,
                "questionsToAsk": intent_mod.questions_for(intent.strategy),
                "source": "google_places",
                "placeId": c.get("placeId"),
                "googleMapsUri": c.get("googleMapsUri"),
                "serviceEvidence": evidence,
                "evidenceSource": "google_places_name_and_type",
                "relevance": rel,
                "geoScope": intent.geo_scope,
                "areaMatch": area,
                "acceptanceStatus": "unknown",
                "attribution": "google_maps",
            })
        results.sort(key=lambda r: r["ranking"]["score"], reverse=True)
        results = results[:_INTENT_MAX_RESULTS]

    # ---- Curated directory (national) ----
    directory_status = "not_applicable"
    if intent.geo_scope == "national":
        matches = match_directory(strategy=intent.strategy, phrase=intent.phrase, detail_terms=list(intent.detail_terms))
        directory_status = "ok" if matches else "no_match"
        for m in matches:
            e, matched = m["entry"], m["matchedTerms"]
            evidence = {_DIRECTORY_EVIDENCE_KEYS[t]: "offered" for t in e["serviceTypes"]}
            why = f"In LTC's reviewed list for {', '.join(matched[:3])}. Confirm they accept your item."
            first_type = e["serviceTypes"][0]
            results.append({
                "partnerId": e["id"],
                "name": e["name"],
                "partnerType": {"buys_outright": "buyer", "donations": "donation"}.get(first_type, first_type),
                "contact": {"phone": None, "website": e["website"], "email": None,
                            "address": None, "city": None, "region": None},
                "distanceMiles": None,
                "rating": None,
                "userRatingsTotal": None,
                "trust": {"trustScore": 1.0, "claimLevel": "curated", "gates": [], "signals": []},
                "ranking": {"score": 1.0, "reasons": [why]},
                "whyRecommended": why,
                "questionsToAsk": e.get("questionsToAsk") or intent_mod.questions_for(intent.strategy),
                "source": "ltc_directory",
                "directoryId": e["id"],
                "serviceEvidence": evidence,
                "evidenceSource": "ltc_directory_review",
                "relevance": {"level": "specialist", "matchedTerms": matched},
                "geoScope": "national",
                "serviceArea": e.get("serviceArea"),
                "intakeModel": e.get("intakeModel"),
                "verifiedAt": e.get("verifiedAt"),
                "acceptanceStatus": "unknown",
            })

    if not queries:
        local_status = "not_applicable"
    elif discovery_status:
        local_status = discovery_status
    elif not any(r["source"] == "google_places" for r in results):
        local_status = "no_results"
    else:
        local_status = "ok"

    # Counts only: never the phrase, location, or businesses.
    logger.info(
        "intent_search strategy=%s scope=%s places_calls=%s results=%s local_status=%s directory_status=%s",
        intent.strategy, intent.geo_scope, places_calls, len(results), local_status, directory_status,
    )

    return DispositionPartnersSearchResponse(
        schemaVersion=1,
        generatedAt=_utcnow(),
        scenarioId=f"intent.{intent.strategy}.{intent.geo_scope}",
        partnerTypes=sorted({r["partnerType"] for r in results}),
        results=results,
        disclaimer=_INTENT_DISCLAIMER,
        localDiscoveryStatus=local_status,
        notice=_LOCAL_DISCOVERY_NOTICES.get(local_status),
        searchScope=intent.geo_scope,
        directoryStatus=directory_status,
    )

@router.post("/disposition/partners/search", response_model=DispositionPartnersSearchResponse)
async def disposition_partners_search(
    payload: DispositionPartnersSearchRequest,
    request: Request,
) -> DispositionPartnersSearchResponse:
    """
    Disposition Engine v1:
    - Select scenario via matrix (priority + wildcard + fallback)
    - Run partner-type searches (Google Places API (New); the stub is dev-only)
    - Evaluate trust gates (required vs boost)
    - Rank + return "why recommended" and "questions to ask"
    - Radius expansion when results are too few (filters the same results)
    - Short-lived in-memory cache plus per-device and daily Places limits
    - If Places is disabled, unconfigured, over budget, or failing, the
      response says so (localDiscoveryStatus); it never substitutes stubs

    v1.1 addition:
    - partnerType == "luxury_hub_mailin" returns curated hub/national channels
      (does NOT depend on Google Places; suitable for secondary markets like Boise).
    """
    from app.services.partner_discovery.factory import (
        PartnerDiscoveryConfigError,
        get_partner_discovery_provider,
        running_on_cloud_run,
    )
    from app.services.partner_discovery.providers import PartnerDiscoveryQuery, PartnerDiscoveryUnavailable
    from app.services.partner_discovery.directory import legacy_luxury_hub_candidates

    # B1: a reviewed Search Intent uses specialty discovery; without one the
    # legacy (app 1.2) scenario-matrix behavior below is unchanged.
    if payload.searchIntent is not None:
        return _intent_partner_search(payload, request)

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
        current = list(payload.scenario.brandHints or [])
        seen = {_norm(x) for x in current if isinstance(x, str) and x.strip()}

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

        payload.scenario.brandHints = current[:6]

    def _curated_luxury_hub_mailin_candidates(*, req: DispositionPartnersSearchRequest) -> list[dict]:
        """
        Curated hub/national channels for luxury clothing & lots.
        These are intentionally NOT discovered via Google Places.

        NOTE: We avoid implying "market price guaranteed".
        The purpose is: specialist-first + correct channel selection.
        """
        brand_hints = []
        for x in (req.scenario.brandHints or []):
            if isinstance(x, str) and x.strip():
                brand_hints.append(x.strip())
        brand_hints = brand_hints[:6]

        hints_txt = ""
        if brand_hints:
            hints_txt = f" (brand hints: {', '.join(brand_hints[:3])})"

        # Entries live in the curated specialty directory; output is unchanged.
        curated = legacy_luxury_hub_candidates(hints_txt)

        return curated

    matrix = _load_disposition_matrix()
    scenario = _pick_scenario(matrix, payload)

    default_radius = int(matrix.get("defaultRadiusMiles", 25))
    base_radius = int(payload.location.radiusMiles or default_radius)
    max_radius = int(matrix.get("maxRadiusMiles", 100))
    min_results = int(matrix.get("minResults", 6))
    max_per_type = int(matrix.get("maxResultsPerType", 8))
    max_queries = max(1, int(ltc_config.PLACES_MAX_QUERIES_PER_TYPE))

    partner_types: list[dict] = scenario.get("partnerTypes", []) or []
    all_results: list[dict] = []

    _normalize_brand_hints()

    center_lat = _as_float(_safe_getattr(payload.location, "latitude", None))
    center_lng = _as_float(_safe_getattr(payload.location, "longitude", None))
    if center_lat is None or center_lng is None:
        # Never pair one real coordinate with a missing one.
        center_lat = center_lng = None
    elif (
        abs(center_lat - _LEGACY_APP_DEFAULT_CENTER[0]) < 1e-6
        and abs(center_lng - _LEGACY_APP_DEFAULT_CENTER[1]) < 1e-6
        and _norm(payload.location.city) != "boise"
    ):
        # App 1.1 sends this fixed Boise point no matter which city the user
        # typed. For any other city it is not the user's location.
        center_lat = center_lng = None

    # ---- Local (Places) discovery availability, decided once per request ----
    local_types = [
        pt for pt in partner_types if pt.get("type") and pt.get("type") not in _CURATED_PARTNER_TYPES
    ]
    discovery_status: Optional[str] = None  # disabled | unavailable | limited, when discovery cannot run
    provider = None

    if local_types:
        if ltc_config.DISABLE_PLACES:
            discovery_status = "disabled"
        else:
            try:
                provider = get_partner_discovery_provider(stub_fn=_stub_places_search)
            except PartnerDiscoveryConfigError as exc:
                logger.error("Partner discovery not configured: %s", exc)
                discovery_status = "unavailable"

        if provider is not None:
            device_id = getattr(request.state, "device_id", None) or "unknown"
            allowed, _retry = rate_limiter.check_daily(
                device_id=device_id,
                scope="places-search",
                limit=ltc_config.PLACES_SEARCHES_PER_DEVICE_DAY_LIMIT,
            )
            if not allowed:
                provider = None
                discovery_status = "limited"

    def _discover(query_str: str, partner_type: str) -> list[dict]:
        """
        One provider call per query. Google Places business details are not
        cached or stored (Places policy allows storing only place IDs). Raises
        PartnerDiscoveryUnavailable or _PlacesBudgetExhausted.
        """
        if not provider.is_stub:
            allowed, _retry = rate_limiter.check_daily(
                device_id=_PLACES_GLOBAL_BUDGET_KEY,
                scope="places-calls",
                limit=ltc_config.PLACES_PER_DAY_LIMIT,
            )
            if not allowed:
                raise _PlacesBudgetExhausted()

        candidates = provider.search(
            PartnerDiscoveryQuery(
                query=query_str,
                city=payload.location.city,
                region=payload.location.region,
                radius_miles=base_radius,
                partner_type=partner_type,
                center_lat=center_lat,
                center_lng=center_lng,
                language_code="en",
                region_code=(payload.location.countryCode or "US").strip().upper() or "US",
            )
        )
        return candidates

    def _radius_tier_filter(pool: list[dict]) -> list[dict]:
        """
        Keep candidates inside the requested radius; widen (50, then 100 miles)
        only when too few qualify. Uses the same results, no extra calls.
        Without a search center there is no distance, so nothing is filtered.
        """
        if center_lat is None:
            return pool
        if pool and not any(
            c.get("distanceMiles") is not None and float(c["distanceMiles"]) <= max_radius for c in pool
        ):
            # Every match is far from the supplied center, so the center does
            # not describe the searched city (e.g. app 1.1 always sends Boise
            # coordinates). Keep the city's results; drop the wrong distances.
            return [dict(c, distanceMiles=None) for c in pool]
        tiers = [base_radius] + [r for r in (50, 100) if base_radius < r <= max_radius]
        chosen: list[dict] = []
        for radius in tiers:
            chosen = [
                c for c in pool
                if c.get("distanceMiles") is not None and float(c["distanceMiles"]) <= radius
            ]
            if len(chosen) >= min_results:
                break
        return chosen

    for pt in partner_types:
        partner_type = pt.get("type")
        if not partner_type:
            continue

        queries = pt.get("queries", []) or []
        trust_gates = pt.get("trustGates", []) or []
        rank_weights = pt.get("rankWeights", {}) or {}

        # Special-case: curated hub channels (no Places search, no radius expansion)
        if partner_type == "luxury_hub_mailin":
            found_for_type: list[dict] = []

            # Treat as a single "query context" so relevance scoring can still run.
            query_str = "luxury mail-in resale"
            if payload.scenario.brandHints:
                query_str = f"{query_str} {' '.join(payload.scenario.brandHints[:2])}"

            candidates = _curated_luxury_hub_mailin_candidates(req=payload)

            for c in candidates:
                sources = c.get("sources", {}) or {}
                gates_eval, trust_score, signals = _evaluate_trust(
                    matrix,
                    partner_payload_sources=sources,
                    trust_gate_ids=trust_gates,
                )

                if not _apply_required_gates(gates_eval):
                    continue

                rel = _relevance_score(c, query_str)

                # Hub channels: distance is not meaningful; keep neutral.
                dist_score = 0.5
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
                        "userRatingsTotal": c.get("userRatingsTotal") or c.get("userRatingCount"),
                        "trust": {
                            "trustScore": trust_score,
                            "claimLevel": "curated",
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

            all_results.extend(found_for_type[:max_per_type])
            continue

        # ---- Local discovery (Google Places in production) ----
        if provider is None:
            continue

        # Businesses whose own name/type text shows they are the wrong kind
        # (e.g. rug cleaners when looking for rug dealers).
        exclude_keywords = [_norm(k) for k in (pt.get("excludeKeywords") or []) if isinstance(k, str) and k.strip()]

        pool: dict[str, dict] = {}
        query_for_candidate: dict[str, str] = {}

        for q in queries[:max_queries]:
            q_template = q.get("q") if isinstance(q, dict) else None
            if not q_template:
                continue

            query_str = (
                q_template.replace("{city}", payload.location.city)
                .replace("{region}", payload.location.region)
                .replace("{category}", payload.scenario.category or "")
            )

            try:
                candidates = _discover(query_str, partner_type)
            except PartnerDiscoveryUnavailable as exc:
                logger.error("Partner discovery unavailable partner_type=%s reason=%s", partner_type, exc.reason)
                discovery_status = "limited" if exc.reason == "upstream_quota" else "unavailable"
                provider = None
                break
            except _PlacesBudgetExhausted:
                logger.error("Partner discovery daily Places budget reached")
                discovery_status = "limited"
                provider = None
                break

            for c in candidates:
                pid = c.get("partnerId")
                if pid and pid not in pool:
                    pool[pid] = c
                    query_for_candidate[pid] = query_str

            if len(_radius_tier_filter(list(pool.values()))) >= min_results:
                break

        found_for_type = []
        for c in _radius_tier_filter(list(pool.values())):
            sources = c.get("sources", {}) or {}
            evidence = _norm(sources.get("website_snippet", ""))
            if any(k in evidence for k in exclude_keywords):
                continue
            gates_eval, trust_score, signals = _evaluate_trust(
                matrix,
                partner_payload_sources=sources,
                trust_gate_ids=trust_gates,
            )

            # A failed required gate means Google's data does not show the
            # business type. Keep it only if it was one of Google's top matches
            # for the query (shown as "likely match, verify").
            provider_rank = c.get("providerRank")
            if not _apply_required_gates(gates_eval):
                if provider_rank is None or int(provider_rank) >= _UNCONFIRMED_TOP_RANK:
                    continue

            query_str = query_for_candidate.get(c.get("partnerId"), "")
            rel = _relevance_score(c, query_str)
            if provider_rank is not None:
                # Google's own text relevance is the strongest signal available.
                rel = round(0.5 * rel + 0.5 * (1.0 - min(int(provider_rank), 19) / 19.0), 3)

            dist_miles = c.get("distanceMiles")
            dist_score = _distance_score(float(dist_miles), base_radius) if dist_miles is not None else 0.5
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
                    "distanceMiles": dist_miles,
                    "rating": c.get("rating"),
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

        found_for_type.sort(key=lambda x: float(x.get("ranking", {}).get("score", 0.0)), reverse=True)
        all_results.extend(found_for_type[:max_per_type])

    # Production guard: fictitious stub businesses never leave Cloud Run.
    if running_on_cloud_run():
        all_results = [r for r in all_results if not str(r.get("partnerId", "")).startswith("stub:")]

    # The same business can match two partner types (e.g. consignment and
    # donation). Show it once, under its best-scoring type.
    all_results_sorted = sorted(
        all_results,
        key=lambda x: float(x.get("ranking", {}).get("score", 0.0)),
        reverse=True,
    )
    seen_ids: set[str] = set()
    deduped: list[dict] = []
    for r in all_results_sorted:
        pid = str(r.get("partnerId") or "")
        if pid in seen_ids:
            continue
        seen_ids.add(pid)
        deduped.append(r)

    local_count = sum(1 for r in deduped if r.get("trust", {}).get("claimLevel") != "curated")
    if not local_types:
        local_status = "not_applicable"
    elif discovery_status:
        local_status = discovery_status
    elif local_count == 0:
        local_status = "no_results"
    else:
        local_status = "ok"

    return DispositionPartnersSearchResponse(
        schemaVersion=1,
        generatedAt=_utcnow(),
        scenarioId=scenario.get("id", "unknown"),
        partnerTypes=[pt.get("type") for pt in partner_types if pt.get("type")],
        results=deduped[: int(matrix.get("maxResultsTotal", 15))],
        disclaimer=(
            "Local business details come from Google Maps and may change. "
            "Verify services, fees, and terms directly with each business. "
            "For curated hub channels, verify current fees, intake rules, and authentication steps directly."
        ),
        recommendedRefreshDays=int(matrix.get("recommendedRefreshDays", 30)),
        localDiscoveryStatus=local_status,
        notice=_LOCAL_DISCOVERY_NOTICES.get(local_status),
    )

_PLACE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{10,300}$")
_MAX_PLACE_DETAILS = 5


@router.post("/disposition/places/details", response_model=PlaceDetailsResponse)
async def disposition_place_details(payload: PlaceDetailsRequest, request: Request) -> PlaceDetailsResponse:
    """
    B2: on-demand details for providers a homeowner saved by Google place ID.
    The app stores only the place ID; name, address, and Maps link are fetched
    here when shown and are not cached. Uses the Place Details Pro field mask.
    """
    from app.services.partner_discovery.factory import PartnerDiscoveryConfigError, get_partner_discovery_provider
    from app.services.partner_discovery.providers import PartnerDiscoveryUnavailable

    ids: list[str] = []
    for pid in payload.placeIds:
        if not isinstance(pid, str) or not _PLACE_ID_RE.match(pid):
            raise HTTPException(status_code=422, detail="Invalid place ID.")
        if pid not in ids:
            ids.append(pid)
    if not ids or len(ids) > _MAX_PLACE_DETAILS:
        raise HTTPException(status_code=422, detail=f"Send 1 to {_MAX_PLACE_DETAILS} place IDs.")

    def _all(status: str) -> PlaceDetailsResponse:
        return PlaceDetailsResponse(
            generatedAt=_utcnow(), status=status,
            places=[PlaceDetailsDTO(placeId=pid, status="unavailable") for pid in ids],
        )

    if ltc_config.DISABLE_PLACES:
        return _all("disabled")
    try:
        provider = get_partner_discovery_provider(stub_fn=_stub_places_search)
    except PartnerDiscoveryConfigError as exc:
        logger.error("Place details not configured: %s", exc)
        return _all("unavailable")
    if provider.is_stub or not hasattr(provider, "details"):
        return _all("unavailable")  # never invent details for a saved place

    device_id = getattr(request.state, "device_id", None) or "unknown"
    allowed, _retry = rate_limiter.check_daily(
        device_id=device_id, scope="places-details", limit=ltc_config.PLACES_DETAILS_PER_DEVICE_DAY_LIMIT,
    )
    if not allowed:
        return _all("limited")

    places: list[PlaceDetailsDTO] = []
    status = "ok"
    for pid in ids:
        allowed, _retry = rate_limiter.check_daily(
            device_id=_PLACES_GLOBAL_BUDGET_KEY, scope="places-calls", limit=ltc_config.PLACES_PER_DAY_LIMIT,
        )
        if not allowed:
            status = "limited"
            places.append(PlaceDetailsDTO(placeId=pid, status="unavailable"))
            continue
        try:
            d = provider.details(pid)
        except PartnerDiscoveryUnavailable as exc:
            logger.error("Place details unavailable reason=%s", exc.reason)
            status = "limited" if exc.reason == "upstream_quota" else "unavailable"
            places.append(PlaceDetailsDTO(placeId=pid, status="unavailable"))
            continue
        if d is None:
            places.append(PlaceDetailsDTO(placeId=pid, status="not_found"))
            continue
        closed = d.get("businessStatus") not in (None, "OPERATIONAL")
        places.append(PlaceDetailsDTO(
            placeId=pid, status="closed" if closed else "ok",
            name=d.get("name"), address=d.get("address"), googleMapsUri=d.get("googleMapsUri"),
        ))

    logger.info("place_details requested=%s status=%s", len(ids), status)
    return PlaceDetailsResponse(generatedAt=_utcnow(), places=places, status=status)


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

from pydantic import BaseModel, Field
from typing import Optional


class SummarizeAudioRequest(BaseModel):
    audioBase64: str = Field(..., description="Base64-encoded audio data.")
    mimeType: str = Field("audio/mp4", description="MIME type, e.g. audio/mp4 or audio/m4a.")
    itemName: Optional[str] = Field(None, description="Optional item name for context.")
    additionalContext: Optional[str] = Field(None, description="Optional additional context.")


class SummarizeAudioResponse(BaseModel):
    summaryText: str

# ---------------------------------------------------------------------------
# Endpoints (existing)
# ---------------------------------------------------------------------------

@router.post("/analyze-item-photo", response_model=ItemAnalysis)
async def analyze_item_photo(payload: AnalyzeItemPhotoRequest) -> ItemAnalysis:
    import logging
    logger = logging.getLogger(__name__)

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
        logger.exception("Gemini call failed in /ai/analyze-item-photo")
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    normalized = _normalize_item_analysis_json(raw_json)

    def _coerce_item_analysis_style_field(json_str: str) -> str:
        # Gemini sometimes emits `style` as a list of tags; our schema expects a string.
        # Keep this local and minimal to avoid changing the model or wider pipeline.
        try:
            obj = json.loads(json_str)
            style = obj.get("style")
            if isinstance(style, list):
                obj["style"] = " · ".join(str(s).strip() for s in style if str(s).strip())
                return json.dumps(obj, ensure_ascii=False)
        except Exception:
            pass
        return json_str

    try:
        analysis = ItemAnalysis.model_validate_json(_coerce_item_analysis_style_field(normalized))
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
            analysis = ItemAnalysis.model_validate_json(_coerce_item_analysis_style_field(repaired_norm))
        except Exception as exc:  # noqa: BLE001
            logger.exception("Gemini repair attempt failed in /ai/analyze-item-photo")
            raise HTTPException(
                status_code=502,
                detail=f"Failed to decode ItemAnalysis JSON from Gemini: {ve}",
            ) from exc
    except Exception as exc:  # noqa: BLE001
        logger.exception("Unexpected JSON validation failure in /ai/analyze-item-photo")
        raise HTTPException(
            status_code=502,
            detail=f"Failed to decode ItemAnalysis JSON from Gemini: {exc}",
        ) from exc

    analysis.category = _normalize_category(analysis.category)
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
        raise HTTPException(
            status_code=501,
            detail="Text-only item analysis is not enabled on this server build.",
        )

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

    # Always use the TEXT-ONLY prompt for this endpoint.
    # If title/description/category are missing, fall back to hints.
    effective_title = title or (hints.userWrittenTitle if hints else None)
    effective_description = description or (hints.userWrittenDescription if hints else None)
    effective_category = category or (hints.knownCategory if hints else None)

    prompt = build_item_analysis_text_prompt(
        effective_title,
        effective_description,
        effective_category,
    )

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

    analysis.category = _normalize_category(analysis.category)
    analysis = _apply_value_policy(analysis)
    return analysis


@router.post("/summarize-audio", response_model=SummarizeAudioResponse)
async def summarize_audio(payload: SummarizeAudioRequest) -> SummarizeAudioResponse:
    import logging
    logger = logging.getLogger(__name__)

    # Validate base64
    try:
        base64.b64decode(payload.audioBase64, validate=True)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=400, detail="audioBase64 is not valid base64") from exc

    mime = (payload.mimeType or "audio/mp4").strip().lower()
    allowed = {"audio/mp4", "audio/m4a", "audio/x-m4a", "audio/wav", "audio/mpeg"}
    if mime not in allowed:
        raise HTTPException(status_code=400, detail=f"mimeType '{mime}' is not supported")

    item_line = f"Item: {payload.itemName}\n" if payload.itemName else ""
    extra_line = f"Context: {payload.additionalContext}\n" if payload.additionalContext else ""

    prompt = (
        "You are summarizing a short owner-recorded provenance note for an estate inventory item.\n"
        "Return a concise, professional summary in 1–2 sentences.\n"
        "Do NOT include bullet points, headers, or quotes.\n"
        "Do NOT speculate beyond what is stated.\n"
        "Write in neutral third-person (e.g., 'Owner notes that...').\n\n"
        f"{item_line}{extra_line}"
        "Summary:"
    )

    try:
        text = await call_gemini_for_audio_summary(
            prompt=prompt,
            audio_base64=payload.audioBase64,
            mime_type=mime,
        )
    except RuntimeError as exc:
        logger.exception("Gemini call failed in /ai/summarize-audio")
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    cleaned = " ".join((text or "").split())
    if len(cleaned) > 320:
        cleaned = cleaned[:317].rstrip() + "..."

    if not cleaned:
        raise HTTPException(status_code=502, detail="Empty summary returned from AI")

    return SummarizeAudioResponse(summaryText=cleaned)

@router.post("/generate-liquidation-brief", response_model=LiquidationBriefDTO)
async def generate_liquidation_brief(payload: LiquidationBriefRequest) -> LiquidationBriefDTO:
    import logging
    logger = logging.getLogger(__name__)

    if call_gemini_for_liquidation_brief is None:
        raise HTTPException(status_code=501, detail="Liquidation brief generation is not enabled on this server build.")

    if payload.photoJpegBase64:
        try:
            base64.b64decode(payload.photoJpegBase64, validate=True)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=400, detail="photoJpegBase64 is not valid base64") from exc

    prompt = _build_liquidation_brief_prompt(payload)

    try:
        raw_json = await call_gemini_for_liquidation_brief(
            prompt=prompt,
            photo_base64=payload.photoJpegBase64,
        )
    except RuntimeError as exc:
        logger.exception("Gemini call failed in /generate-liquidation-brief")
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
            repaired = await call_gemini_for_liquidation_brief(
                prompt=repair_prompt,
                photo_base64=payload.photoJpegBase64,
            )
            repaired_obj = _normalize_liquidation_brief_obj(raw_json=repaired, request=payload)
            brief = LiquidationBriefDTO.model_validate(repaired_obj)
        except Exception as exc:  # noqa: BLE001
            logger.exception("Gemini repair attempt failed in /generate-liquidation-brief")
            raise HTTPException(
                status_code=502,
                detail=f"Failed to decode LiquidationBriefDTO JSON from Gemini: {ve}",
            ) from exc
    except Exception as exc:  # noqa: BLE001
        logger.exception("Unexpected JSON validation failure in /generate-liquidation-brief")
        raise HTTPException(
            status_code=502,
            detail=f"Failed to decode LiquidationBriefDTO JSON from Gemini: {exc}",
        ) from exc

    # Stamp required fields & IDs
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

    # First pass normalize + validate. No usable steps counts as invalid (repair once).
    try:
        obj = _normalize_liquidation_plan_obj(raw_json=raw_json, request=payload)
        plan = LiquidationPlanChecklistDTO.model_validate(obj)
    except (ValidationError, ValueError) as ve:
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
    plan.aiProvider = "gemini"
    plan.aiModel = GEMINI_MODEL

    # Ensure sequential order
    if plan.items:
        for idx, item in enumerate(plan.items):
            if getattr(item, "order", None) is None:
                item.order = idx + 1

    return plan
