"""Automated checks. These are technical and heuristic signals, not quality verdicts.

Severity:
  fail  - technical failure or hard rule broken (e.g. non-200, invalid range ordering)
  warn  - needs human review (e.g. possible invented detail, implied sales evidence)
  info  - recorded fact for comparison (e.g. word count, benchmark ratio)

Anything about correctness of identification, description usefulness or valuation
realism is ultimately judged by a person using the review sheet.
"""
from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional

IOS_TIMEOUT_S = 35.0
SLOW_WARN_S = 20.0

# Phrases suggesting the model checked real transactions or listings. The gateway has no
# sales-data retrieval, so any of these is an unsupported assertion to review.
IMPLIED_EVIDENCE_RE = re.compile(
    r"\b(recently sold|sold for|sold at|sold on|sells? for|selling for|completed sales?|sold listings?|"
    r"realized prices?|auction results?|recent sales|sales data|sales history|comparable sales|"
    r"comps show|based on (?:recent )?(?:ebay|auction|sales)|ebay sold|according to (?:recent )?sales|"
    r"market data shows|listings? (?:show|range))\b",
    re.IGNORECASE,
)


def _c(name: str, severity: str, detail: str = "", **data) -> Dict[str, Any]:
    d = {"check": name, "severity": severity, "detail": detail}
    if data:
        d["data"] = data
    return d


def count(checks: List[Dict[str, Any]]) -> Dict[str, int]:
    out = {"fail": 0, "warn": 0}
    for c in checks:
        if c["severity"] in out:
            out[c["severity"]] += 1
    return out


def _texts(obj: Any) -> List[str]:
    if isinstance(obj, str):
        return [obj]
    if isinstance(obj, list):
        return [t for x in obj for t in _texts(x)]
    if isinstance(obj, dict):
        return [t for v in obj.values() for t in _texts(v)]
    return []


def _words(s: Optional[str]) -> int:
    return len((s or "").split())


def _stage(record, name) -> List[Dict[str, Any]]:
    return [s for s in record.get("stages", []) if s["stage"] == name]


def _first_model_category(record) -> Optional[str]:
    s = _stage(record, "3_normalize_category")
    return s[-1].get("input") if s else None


def technical_checks(record) -> List[Dict[str, Any]]:
    out = []
    if record.get("status") == "input_error":
        return [_c("input", "fail", record.get("error", ""))]
    st = record.get("http_status")
    out.append(_c("http_200", "info" if st == 200 else "fail", f"status={st}"))
    for e in record.get("route_errors", []):
        out.append(_c("route_error", "fail", f"HTTP {e['status']}: {e['detail'][:300]}"))
    m = record.get("metrics", {})
    if m.get("repairs"):
        out.append(_c("repair_needed", "warn", f"{m['repairs']} repair call(s): first answer failed validation"))
    if m.get("retries"):
        out.append(_c("retry_needed", "warn", f"{m['retries']} retry call(s) after an upstream or parse error"))
    for c in record.get("gemini_calls", []):
        if c.get("http_status") and c["http_status"] != 200:
            out.append(_c("upstream_error", "fail", f"Gemini HTTP {c['http_status']} on call {c['seq']}"))
        if c.get("transport_error"):
            out.append(_c("upstream_transport", "fail", c["transport_error"][:200]))
        if c.get("finish_reason") not in (None, "STOP"):
            out.append(_c("finish_reason", "warn", f"call {c['seq']} finishReason={c.get('finish_reason')}"))
        if (c.get("text_part_count") or 0) > 1:
            out.append(_c("multi_text_parts", "warn",
                          f"call {c['seq']} returned {c['text_part_count']} text parts; gateway reads only the first"))
    calls = record.get("gemini_calls") or []
    if calls and calls[-1].get("finish_reason") == "MAX_TOKENS" and record.get("http_status") == 200:
        # The answer the app received came from a call that hit the output limit: it is incomplete.
        out.append(_c("output_truncated", "fail",
                      "final answer was cut off at the output-token limit (thinking tokens count toward it)"))
    lat = record.get("latency_total_s")
    if lat is not None:
        sev = "fail" if lat > IOS_TIMEOUT_S else ("warn" if lat > SLOW_WARN_S else "info")
        out.append(_c("latency", sev, f"{lat:.1f}s end-to-end (iOS times out at {IOS_TIMEOUT_S:.0f}s)", seconds=lat))
    versions = m.get("model_versions") or []
    req = record.get("requested_model")
    if versions and any(not v.startswith(req) for v in versions):
        out.append(_c("model_version_mismatch", "warn", f"requested {req}, served {versions}"))
    return out


def identity_checks(final: Dict[str, Any], ref: Dict[str, Any]) -> List[Dict[str, Any]]:
    out = []
    text_fields = " ".join(_texts({k: final.get(k) for k in
                                   ("title", "description", "brand", "materials", "style", "origin",
                                    "eraOrYear", "features", "tags")})).lower()
    accept = ref.get("acceptableCategories") or ([ref["category"]] if ref.get("category") else [])
    if accept:
        ok = final.get("category") in accept
        out.append(_c("category_matches_reference", "info" if ok else "warn",
                      f"got {final.get('category')!r}, acceptable {accept}"))
    for term in ref.get("mustMention", []):
        if term.lower() not in text_fields:
            out.append(_c("missing_key_fact", "warn", f"did not mention {term!r}"))
    for term in ref.get("mustNotClaim", []):
        if term.lower() in text_fields:
            out.append(_c("possible_unsupported_claim", "warn",
                          f"mentions {term!r}; check whether it is asserted or appropriately hedged"))
    return out


def valuation_checks(final: Dict[str, Any], ref: Dict[str, Any], record) -> List[Dict[str, Any]]:
    out = []
    vh = final.get("valueHints") or {}
    lo, est, hi = vh.get("valueLow"), vh.get("estimatedValue"), vh.get("valueHigh")
    conf = vh.get("confidenceScore")
    if lo is None and est is None and hi is None:
        out.append(_c("not_estimated", "info", "no value returned", confidence=conf))
    else:
        nums = [x for x in (lo, est, hi) if x is not None]
        if nums != sorted(nums):
            out.append(_c("range_order", "fail", f"low/likely/high out of order: {lo}/{est}/{hi}"))
        if lo and hi and lo > 0 and hi / lo > 5:
            out.append(_c("range_very_wide", "warn", f"high/low ratio {hi / lo:.1f}"))
        out.append(_c("value_range", "info", f"{lo} / {est} / {hi} (conf {conf})",
                      low=lo, likely=est, high=hi, confidence=conf))
    if conf is not None and not (0 <= conf <= 1):
        out.append(_c("confidence_bounds", "fail", f"confidenceScore={conf}"))

    # Reference benchmarks. Only 'sold' evidence is treated as a realized outcome.
    for ev in ref.get("saleEvidence", []):
        price, kind = ev.get("price"), (ev.get("type") or "").lower()
        if price is None:
            continue
        qty = int(ev.get("quantity") or 1)
        label = f"{kind} ${price:,.0f}" + (f" for {qty} units (bundle)" if qty > 1 else "") + (
            f" ({ev.get('source')})" if ev.get("source") else "")
        if qty > 1:
            # A bundle is not an observed single-unit price. The per-unit figure is only a
            # derived average, used as a rough benchmark for a single-item estimate.
            label += f"; derived average ${price / qty:,.0f} per unit"
            price = price / qty
        if kind == "sold":
            if est is None and lo is None and hi is None:
                out.append(_c("vs_sold", "warn", f"no estimate; {label}"))
                continue
            mid = est if est is not None else (lo + hi) / 2 if lo is not None and hi is not None else (lo or hi)
            ratio = mid / price if price else None
            inside = (lo is None or lo <= price) and (hi is None or price <= hi)
            sev = "info"
            if ratio is not None and (ratio > 1.5 or ratio < 0.5):
                sev = "warn"
            basis = "derived per-unit average" if qty > 1 else "sold price"
            out.append(_c("vs_sold", sev,
                          f"likely/{basis} = {ratio:.2f}; {basis} {'inside' if inside else 'outside'} range; {label}",
                          ratio=ratio, inside=inside, sold=price))
        else:
            out.append(_c("vs_non_sold_reference", "info",
                          f"{label} is not a realized sale; context only", price=price, kind=kind))

    # Did LTC's valuation policy change the model's numbers?
    pol = _stage(record, "4_apply_value_policy")
    if pol:
        before = (pol[-1].get("input") or {}).get("valueHints") or {}
        after = (pol[-1].get("output") or {}).get("valueHints") or {}
        changed = [k for k in ("valueLow", "estimatedValue", "valueHigh", "confidenceScore", "aiNotes")
                   if before.get(k) != after.get(k)]
        if changed:
            out.append(_c("policy_adjusted", "info", f"LTC value policy changed {changed}",
                          before={k: before.get(k) for k in changed}, after={k: after.get(k) for k in changed}))
    return out


def evidence_language_checks(obj: Any) -> List[Dict[str, Any]]:
    hits = []
    for t in _texts(obj):
        for m in IMPLIED_EVIDENCE_RE.finditer(t):
            s = max(0, m.start() - 60)
            hits.append(t[s:m.end() + 60].replace("\n", " "))
    if hits:
        return [_c("implied_sales_evidence", "warn",
                   "language implies checked sales/listings, but the gateway has no sales-data access",
                   snippets=hits[:5])]
    return []


def item_checks(case, record) -> List[Dict[str, Any]]:
    final = record.get("final_response") or {}
    if record.get("http_status") != 200:
        return []
    ref = case.get("_reference") or {}
    out = []
    model_cat = _first_model_category(record)
    if model_cat is not None and model_cat != final.get("category"):
        out.append(_c("category_normalized", "warn",
                      f"model returned {model_cat!r}; LTC changed it to {final.get('category')!r}"))
    dw = _words(final.get("description"))
    out.append(_c("description_words", "warn" if dw > 150 else "info", f"{dw} words", words=dw))
    out += identity_checks(final, ref)
    out += valuation_checks(final, ref, record)
    out += evidence_language_checks({k: final.get(k) for k in ("description", "valueHints")})
    return out


def audio_checks(case, record) -> List[Dict[str, Any]]:
    final = record.get("final_response") or {}
    if record.get("http_status") != 200:
        return []
    text = final.get("summaryText") or ""
    out = []
    sentences = [s for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s]
    out.append(_c("sentences", "warn" if len(sentences) > 2 else "info", f"{len(sentences)} sentence(s)"))
    out.append(_c("length", "info", f"{len(text)} chars"))
    if text.endswith("..."):
        out.append(_c("truncated_by_ltc", "warn", "summary exceeded 320 chars and was cut"))
    if re.search(r"\b(I|my|me|we|our)\b", text):
        out.append(_c("first_person", "warn", "summary is not in third person"))
    for fact in (case.get("_reference") or {}).get("expectedFacts", []):
        if fact.lower() not in text.lower():
            out.append(_c("missing_fact", "warn", f"did not mention {fact!r}"))
    return out


def brief_checks(case, record) -> List[Dict[str, Any]]:
    final = record.get("final_response") or {}
    if record.get("http_status") != 200:
        return []
    out = []
    opts = final.get("pathOptions") or []
    out.append(_c("path_options", "info", f"{len(opts)} options; recommended {final.get('recommendedPath')}"))
    for o in opts:
        np_ = o.get("netProceeds") or {}
        nums = [np_.get(k) for k in ("low", "likely", "high") if np_.get(k) is not None]
        if nums != sorted(nums):
            out.append(_c("net_proceeds_order", "fail", f"{o.get('path')}: {nums}"))
    out.append(_c("reasoning_words", "info", f"{_words(final.get('reasoning'))} words"))
    out += evidence_language_checks(final)
    return out


def plan_checks(case, record) -> List[Dict[str, Any]]:
    final = record.get("final_response") or {}
    if record.get("http_status") != 200:
        return []
    items = final.get("items") or []
    out = [_c("plan_steps", "warn" if len(items) < 3 else "info", f"{len(items)} steps")]
    out += evidence_language_checks(final)
    return out


def run_checks(case, record) -> List[Dict[str, Any]]:
    out = technical_checks(record)
    t = case["type"]
    if t in ("photo", "text"):
        out += item_checks(case, record)
    elif t == "audio":
        out += audio_checks(case, record)
    elif t == "brief":
        out += brief_checks(case, record)
    elif t == "plan":
        out += plan_checks(case, record)
    return out


if __name__ == "__main__":  # tiny self-test
    print(json.dumps(evidence_language_checks({"a": "Similar sets recently sold for $400 on eBay."}), indent=1))
