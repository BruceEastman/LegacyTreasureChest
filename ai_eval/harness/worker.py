"""Runs one model against a list of cases, in-process, through the real gateway routes.

Launched by run_suite.py with the gateway's venv Python. Never run this directly against
production: it has no knowledge of Cloud Run, and its network guard only permits
POST .../models/<model>:generateContent on generativelanguage.googleapis.com.

The API key arrives on stdin (one line) and is held only in this process's memory.
"""
from __future__ import annotations

import argparse
import base64
import copy
import json
import os
import statistics  # noqa: F401  (kept for ad-hoc debugging)
import sys
import time
import traceback
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common import (  # noqa: E402
    ENDPOINTS, GATEWAY_DIR, cost_from_usage, jpeg_private_metadata, load_pricing,
    read_json, sha256_bytes, write_json,
)
import checks as checks_mod  # noqa: E402

ALLOWED_HOST = "generativelanguage.googleapis.com"

# Per-case recording context (the worker runs cases sequentially).
CTX: dict = {}


def _new_ctx(case_id: str, run_index: int, case_type: str) -> None:
    CTX.clear()
    CTX.update({"case_id": case_id, "run_index": run_index, "type": case_type,
                "calls": [], "stages": [], "last_payload_hash": None})


# ---------------------------------------------------------------------------
# Redaction
# ---------------------------------------------------------------------------

def _redact_payload(payload: dict) -> dict:
    """Replace inline media with hash + size so results never duplicate private media."""
    p = copy.deepcopy(payload)
    for content in p.get("contents", []):
        for part in content.get("parts", []):
            inline = part.get("inline_data") or part.get("inlineData")
            if inline and "data" in inline:
                raw = inline["data"]
                try:
                    nbytes = len(base64.b64decode(raw))
                except Exception:  # noqa: BLE001
                    nbytes = None
                inline["data"] = {"omitted": True, "sha256": sha256_bytes(raw.encode())[:16], "bytes": nbytes}
    return p


def _scrub(obj, secret: str):
    """Remove the API key from any string anywhere in obj (defense in depth)."""
    if not secret or len(secret) < 8:
        return obj
    if isinstance(obj, str):
        return obj.replace(secret, "<redacted>")
    if isinstance(obj, list):
        return [_scrub(x, secret) for x in obj]
    if isinstance(obj, dict):
        return {k: _scrub(v, secret) for k, v in obj.items()}
    return obj


# ---------------------------------------------------------------------------
# Mock Gemini (offline verification of the harness itself)
# ---------------------------------------------------------------------------

def _mock_text(case_type: str, scenario: str, call_no: int) -> str:
    if scenario == "repair" and call_no == 0 and case_type in ("photo", "text", "brief"):
        return json.dumps({"description": "missing required fields"})
    if case_type in ("photo", "text"):
        return json.dumps({
            "title": "Mock item", "description": "Mock description of a household item.",
            "category": "Silverware" if scenario == "invented_category" else "Decor",
            "confidence": 0.5,
            "style": ["mid-century", "modern"] if scenario == "style_list" else "Mid-century modern",
            "valueHints": {"valueLow": 20, "estimatedValue": None, "valueHigh": 40,
                           "confidenceScore": 0.4, "aiNotes": "Recently sold for about $30 on eBay.",
                           "missingDetails": ["Maker"]},
        })
    if case_type == "audio":
        return "Owner notes that the mock item came from a relative."
    if case_type == "brief":
        return json.dumps({
            "schemaVersion": 1, "scope": "item", "generatedAt": "2026-10-16T00:00:00Z",
            "recommendedPath": "pathB_delegateConsign", "reasoning": "Mock reasoning.",
            "pathOptions": [
                {"id": "a", "path": "pathA_maximizePrice", "label": "Sell it yourself", "effort": "high", "risks": []},
                {"id": "b", "path": "pathB_delegateConsign", "label": "Consign", "effort": "medium", "risks": []},
                {"id": "c", "path": "pathC_quickExit", "label": "Quick sale", "effort": "low", "risks": []},
            ],
            "actionSteps": ["Mock step"],
        })
    if case_type == "plan":
        return json.dumps({"schemaVersion": 2, "createdAt": "2026-10-16T00:00:00Z",
                           "items": [{"order": 1, "text": "Mock step one"}, {"order": 2, "text": "Mock step two"}]})
    return "{}"


def _mock_response(model: str, scenario: str) -> dict:
    text = _mock_text(CTX.get("type", ""), scenario, len(CTX.get("calls", [])))
    return {
        "candidates": [{"content": {"parts": [{"text": text}], "role": "model"}, "finishReason": "STOP"}],
        "usageMetadata": {"promptTokenCount": 1000, "candidatesTokenCount": 300, "thoughtsTokenCount": 200,
                          "totalTokenCount": 1500,
                          "promptTokensDetails": [{"modality": "TEXT", "tokenCount": 1000}]},
        "modelVersion": f"{model}-MOCK",
    }


# ---------------------------------------------------------------------------
# Network guard + Gemini call recorder
# ---------------------------------------------------------------------------

def install_network_guard(httpx, model: str, mock: bool, scenario: str, pricing: dict) -> None:
    orig_async_send = httpx.AsyncClient.send
    orig_sync_send = httpx.Client.send

    async def guarded_async_send(self, request, *args, **kwargs):
        url = request.url
        allowed = (request.method == "POST" and url.host == ALLOWED_HOST
                   and url.path.endswith(":generateContent") and "/models/" in url.path)
        if not allowed:
            raise RuntimeError(f"ai_eval network guard blocked {request.method} {url.host}{url.path}")
        requested_model = url.path.split("/models/")[1].split(":")[0]
        payload = json.loads(request.content or b"{}")
        payload_hash = sha256_bytes(json.dumps(payload, sort_keys=True).encode())
        if not CTX.get("calls"):
            kind = "initial"
        elif payload_hash == CTX.get("last_payload_hash"):
            kind = "retry"
        else:
            kind = "repair"
        CTX["last_payload_hash"] = payload_hash

        record = {"seq": len(CTX["calls"]) + 1, "kind": kind, "requested_model": requested_model,
                  "endpoint": f"{url.host}{url.path}", "request": _redact_payload(payload)}
        t0 = time.perf_counter()
        try:
            if mock:
                resp = httpx.Response(200, json=_mock_response(model, scenario), request=request)
            else:
                resp = await orig_async_send(self, request, *args, **kwargs)
        except Exception as exc:  # noqa: BLE001
            record.update({"latency_s": round(time.perf_counter() - t0, 3),
                           "transport_error": f"{type(exc).__name__}: {exc}"})
            CTX["calls"].append(record)
            raise
        record["latency_s"] = round(time.perf_counter() - t0, 3)
        record["http_status"] = resp.status_code
        try:
            body = resp.json()
        except Exception:  # noqa: BLE001
            body = {"_non_json_body": resp.text[:4000]}
        record["response_raw"] = body
        if isinstance(body, dict):
            record["model_version"] = body.get("modelVersion")
            record["usage"] = body.get("usageMetadata")
            cands = body.get("candidates") or []
            if cands:
                record["finish_reason"] = cands[0].get("finishReason")
                parts = (cands[0].get("content") or {}).get("parts") or []
                record["text_part_count"] = sum(1 for p in parts if "text" in p and not p.get("thought"))
                record["has_thought_signature"] = any("thoughtSignature" in p or "thought_signature" in p for p in parts)
            record["cost_usd"] = cost_from_usage(record.get("usage") or {}, requested_model, pricing)
        CTX["calls"].append(record)
        return resp

    def guarded_sync_send(self, request, *args, **kwargs):
        # Only the in-process TestClient may use the sync client.
        if request.url.host != "testserver":
            raise RuntimeError(f"ai_eval network guard blocked sync {request.url.host}")
        return orig_sync_send(self, request, *args, **kwargs)

    httpx.AsyncClient.send = guarded_async_send
    httpx.Client.send = guarded_sync_send


# ---------------------------------------------------------------------------
# Stage recorders: separate model output from LTC application processing
# ---------------------------------------------------------------------------

def _dump(obj):
    if hasattr(obj, "model_dump"):
        return obj.model_dump(mode="json")
    return copy.deepcopy(obj)


def install_stage_recorders(route, gemini_client) -> None:
    def wrap(module, name, stage, capture):
        orig = getattr(module, name)

        def wrapper(*args, **kwargs):
            before = capture("before", args, kwargs, None)
            try:
                out = orig(*args, **kwargs)
            except Exception as exc:  # noqa: BLE001
                CTX["stages"].append({"stage": stage, "input": before, "error": f"{type(exc).__name__}: {exc}"})
                raise
            CTX["stages"].append({"stage": stage, "input": before, "output": capture("after", args, kwargs, out)})
            return out

        setattr(module, name, wrapper)

    def first_arg(when, args, kwargs, out):
        if when == "before":
            return _dump(args[0]) if args else _dump(kwargs.get("raw_json") or kwargs.get("raw_text"))
        return _dump(out)

    def raw_json_kw(when, args, kwargs, out):
        if when == "before":
            return kwargs.get("raw_json", args[0] if args else None)
        return _dump(out)

    # Record the detail of every HTTPException the routes raise. Production hides 5xx detail
    # from clients ("Upstream service error."), but it is the key diagnostic for parse failures.
    base_exc = route.HTTPException

    class RecordingHTTPException(base_exc):
        def __init__(self, status_code, detail=None, *a, **kw):
            CTX.setdefault("route_errors", []).append({"status": status_code, "detail": str(detail)[:4000]})
            super().__init__(status_code, detail, *a, **kw)

    route.HTTPException = RecordingHTTPException

    wrap(gemini_client, "clean_llm_json", "1_clean_llm_json", first_arg)
    wrap(route, "_normalize_item_analysis_json", "2_normalize_item_analysis", first_arg)
    wrap(route, "_normalize_category", "3_normalize_category", first_arg)
    wrap(route, "_apply_value_policy", "4_apply_value_policy", first_arg)
    for name, stage in (("_normalize_liquidation_brief_obj", "2_normalize_brief"),
                        ("_normalize_liquidation_plan_obj", "2_normalize_plan")):
        if hasattr(route, name):
            wrap(route, name, stage, raw_json_kw)


# ---------------------------------------------------------------------------
# Case execution
# ---------------------------------------------------------------------------

def _read_b64(path: str) -> str:
    return base64.b64encode(Path(path).read_bytes()).decode()


def build_request(case: dict) -> dict:
    t = case["type"]
    if t == "photo":
        data = Path(case["_photo_path"]).read_bytes()
        meta = jpeg_private_metadata(data)
        if meta:
            raise RuntimeError(f"photo still carries metadata {meta}; run prepare_photos.py first")
        return {"imageJpegBase64": base64.b64encode(data).decode(), "hints": case.get("hints")}
    if t == "text":
        return {"hints": case["hints"]}
    if t == "audio":
        return {"audioBase64": _read_b64(case["_audio_path"]), "mimeType": case["mimeType"],
                "itemName": case.get("itemName"), "additionalContext": None}
    if t == "brief":
        body = copy.deepcopy(case["request"])
        if case.get("_photo_path"):
            data = Path(case["_photo_path"]).read_bytes()
            if jpeg_private_metadata(data):
                raise RuntimeError("brief photo still carries metadata; run prepare_photos.py first")
            body["photoJpegBase64"] = base64.b64encode(data).decode()
        return body
    if t == "plan":
        return copy.deepcopy(case["request"])
    raise ValueError(t)


def _stage_map(stages):
    """Collapse stage records into the first-pass and final views used by checks/reports."""
    out = {}
    for s in stages:
        out.setdefault(s["stage"], []).append(s)
    return out


def run_case(client, case: dict, run_index: int, model: str, secret: str) -> dict:
    _new_ctx(case["id"], run_index, case["type"])
    record = {"case_id": case["id"], "run_index": run_index, "type": case["type"],
              "suite": case["_suite"], "suite_version": case["_suite_version"],
              "requested_model": model, "endpoint": ENDPOINTS[case["type"]]}
    try:
        body = build_request(case)
    except Exception as exc:  # noqa: BLE001
        record.update({"status": "input_error", "error": str(exc)})
        return record
    headers = {"X-LTC-Device-ID": "ai-eval-harness", "X-Request-ID": f"eval-{case['id']}-{run_index}"}
    t0 = time.perf_counter()
    try:
        resp = client.post(ENDPOINTS[case["type"]], json=body, headers=headers)
        status = resp.status_code
        try:
            final = resp.json()
        except Exception:  # noqa: BLE001
            final = {"_non_json_body": resp.text[:2000]}
    except Exception as exc:  # noqa: BLE001
        status, final = None, {"_harness_exception": f"{type(exc).__name__}: {exc}",
                               "_traceback": traceback.format_exc()[-2000:]}
    record["latency_total_s"] = round(time.perf_counter() - t0, 3)
    record["http_status"] = status
    record["status"] = "ok" if status == 200 else "failed"
    record["final_response"] = final
    record["gemini_calls"] = CTX["calls"]
    record["stages"] = CTX["stages"]
    record["route_errors"] = CTX.get("route_errors", [])
    calls = CTX["calls"]
    record["metrics"] = {
        "gemini_calls": len(calls),
        "repairs": sum(1 for c in calls if c["kind"] == "repair"),
        "retries": sum(1 for c in calls if c["kind"] == "retry"),
        "model_versions": sorted({c.get("model_version") for c in calls if c.get("model_version")}),
        "finish_reasons": [c.get("finish_reason") for c in calls],
        "input_tokens": sum((c.get("usage") or {}).get("promptTokenCount", 0) or 0 for c in calls),
        "output_tokens": sum((c.get("usage") or {}).get("candidatesTokenCount", 0) or 0 for c in calls),
        "thinking_tokens": sum((c.get("usage") or {}).get("thoughtsTokenCount", 0) or 0 for c in calls),
        "cost_usd": round(sum(c.get("cost_usd") or 0 for c in calls), 6),
        "gemini_latency_s": round(sum(c.get("latency_s") or 0 for c in calls), 3),
    }
    record["case_input"] = {k: v for k, v in case.items() if not k.startswith("_") and k != "request"} | (
        {"request_summary": {k: v for k, v in case["request"].items() if k != "brief"}} if "request" in case else {})
    record["checks"] = checks_mod.run_checks(case, record)
    return _scrub(record, secret)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--cases", required=True, help="JSON file with resolved cases (written by run_suite.py)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--mock", action="store_true")
    ap.add_argument("--mock-scenario", default="normal")
    args = ap.parse_args()

    secret = "" if args.mock else sys.stdin.readline().strip()
    if not args.mock and not secret:
        print("worker: no API key received on stdin", file=sys.stderr)
        return 2

    # Environment for the in-process gateway. Set before any gateway import.
    os.environ["GEMINI_API_KEY"] = secret or "mock-key-not-used"
    os.environ["GEMINI_MODEL"] = args.model
    os.environ.update({"LTC_DISABLE_ALL_AI": "false", "LTC_DISABLE_PLACES": "true",
                       "LTC_AI_PER_MINUTE_LIMIT": "100000", "LTC_AI_PER_DAY_LIMIT": "100000",
                       "LTC_ANALYZE_PER_MINUTE_LIMIT": "100000", "PARTNER_DISCOVERY_PROVIDER": "stub"})
    for var in ("K_SERVICE", "K_REVISION", "GOOGLE_PLACES_API_KEY"):
        os.environ.pop(var, None)

    os.chdir(GATEWAY_DIR)
    sys.path.insert(0, str(GATEWAY_DIR))
    import httpx  # noqa: E402

    pricing = load_pricing()
    install_network_guard(httpx, args.model, args.mock, args.mock_scenario, pricing)

    import main as gw_main  # noqa: E402
    from app.routes import analyze_item_photo as route  # noqa: E402
    from app.services import gemini_client  # noqa: E402

    if gemini_client.GEMINI_MODEL != args.model:
        print(f"worker: gateway resolved model {gemini_client.GEMINI_MODEL!r}, expected {args.model!r}", file=sys.stderr)
        return 3
    install_stage_recorders(route, gemini_client)

    import logging  # noqa: E402
    logging.getLogger("app").setLevel(logging.WARNING)
    logging.getLogger("app.middleware.request_context").setLevel(logging.WARNING)

    from fastapi.testclient import TestClient  # noqa: E402
    client = TestClient(gw_main.app, raise_server_exceptions=False)

    cases = read_json(Path(args.cases))
    out_dir = Path(args.out)
    (out_dir / "cases").mkdir(parents=True, exist_ok=True)
    summary_lines = []
    for case in cases:
        for r in range(1, int(case.get("repeat", 1)) + 1):
            rec = run_case(client, case, r, args.model, secret)
            write_json(out_dir / "cases" / f"{case['id']}__r{r}.json", rec)
            m = rec.get("metrics", {})
            line = {"case_id": rec["case_id"], "run": r, "type": rec["type"], "status": rec["status"],
                    "http": rec.get("http_status"), "latency_s": rec.get("latency_total_s"),
                    "repairs": m.get("repairs"), "retries": m.get("retries"), "cost_usd": m.get("cost_usd"),
                    "model_versions": m.get("model_versions"),
                    "check_counts": checks_mod.count(rec.get("checks", []))}
            summary_lines.append(line)
            print(f"  [{args.model}] {rec['case_id']} r{r}: {rec['status']} http={rec.get('http_status')} "
                  f"{rec.get('latency_total_s')}s repairs={m.get('repairs')} {line['check_counts']}", flush=True)
    (out_dir / "summary.jsonl").write_text("\n".join(json.dumps(x) for x in summary_lines) + "\n")

    # Final safety check: the key must not appear in anything written.
    if secret:
        for p in out_dir.rglob("*"):
            if p.is_file() and secret.encode() in p.read_bytes():
                print(f"worker: SECRET FOUND IN {p}; deleting run output", file=sys.stderr)
                for q in out_dir.rglob("*"):
                    if q.is_file():
                        q.unlink()
                return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
