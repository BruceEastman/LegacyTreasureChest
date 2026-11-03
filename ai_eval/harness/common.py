"""Shared paths and helpers for the LTC AI evaluation harness (standard library only)."""
from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

HARNESS_VERSION = "1.0.0"

HARNESS_DIR = Path(__file__).resolve().parent
AI_EVAL_DIR = HARNESS_DIR.parent
REPO_DIR = AI_EVAL_DIR.parent
GATEWAY_DIR = REPO_DIR / "LTC_AI_Gateway"
GATEWAY_PYTHON = GATEWAY_DIR / ".venv" / "bin" / "python"
RESULTS_DIR = AI_EVAL_DIR / "results"
REPORTS_DIR = AI_EVAL_DIR / "reports"
PRICING_PATH = HARNESS_DIR / "pricing.json"

# Files whose content defines "what the model is asked and how the answer is processed".
# Their hashes are recorded with every run so prompt or pipeline changes are visible.
FINGERPRINT_FILES = [
    "app/ai/prompts/item_analysis.py",
    "app/ai/normalization/item_analysis.py",
    "app/routes/analyze_item_photo.py",
    "app/services/gemini_client.py",
    "app/utils/json_cleaner.py",
    "app/models.py",
    "app/models_liquidation.py",
]

CASE_TYPES = {"photo", "text", "audio", "brief", "plan"}

ENDPOINTS = {
    "photo": "/ai/analyze-item-photo",
    "text": "/ai/analyze-item-text",
    "audio": "/ai/summarize-audio",
    "brief": "/ai/generate-liquidation-brief",
    "plan": "/ai/generate-liquidation-plan",
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False, default=str) + "\n", encoding="utf-8")


def gateway_fingerprint() -> Dict[str, Any]:
    files = {}
    for rel in FINGERPRINT_FILES:
        p = GATEWAY_DIR / rel
        files[rel] = sha256_file(p)[:16] if p.exists() else None
    combined = sha256_bytes(json.dumps(files, sort_keys=True).encode())[:16]
    git = {}
    try:
        git["commit"] = subprocess.run(
            ["git", "-C", str(REPO_DIR), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True).stdout.strip()
        dirty = subprocess.run(
            ["git", "-C", str(REPO_DIR), "status", "--porcelain", "--", "LTC_AI_Gateway/app"],
            capture_output=True, text=True, check=True).stdout.strip()
        git["gateway_app_dirty"] = bool(dirty)
    except Exception:  # noqa: BLE001
        git["commit"] = None
    return {"pipeline_fingerprint": combined, "files": files, "git": git}


# ---------------------------------------------------------------------------
# Suite loading
# ---------------------------------------------------------------------------

class SuiteError(Exception):
    pass


def load_suite(path: Path) -> Dict[str, Any]:
    """Load a suite file and its separate reference file. Resolves asset paths."""
    path = path.resolve()
    suite = read_json(path)
    for key in ("suite", "version", "cases"):
        if key not in suite:
            raise SuiteError(f"{path}: missing '{key}'")
    base = path.parent
    refs: Dict[str, Any] = {}
    if suite.get("references"):
        ref_path = (base / suite["references"]).resolve()
        if ref_path.exists():
            refs = read_json(ref_path).get("cases", {})
    cases = []
    for c in suite["cases"]:
        if c.get("enabled", True) is False:
            continue
        if c.get("type") not in CASE_TYPES:
            raise SuiteError(f"{path}: case {c.get('id')} has unknown type {c.get('type')}")
        c = dict(c)
        c["_suite"] = suite["suite"]
        c["_suite_version"] = suite["version"]
        for asset_key in ("photo", "audio"):
            if c.get(asset_key):
                c[f"_{asset_key}_path"] = str((base / c[asset_key]).resolve())
        c["_reference"] = refs.get(c["id"], {})
        cases.append(c)
    return {"path": str(path), "sha256": sha256_file(path)[:16], "meta": suite, "cases": cases}


def load_suites(paths: List[Path]) -> List[Dict[str, Any]]:
    suites = [load_suite(p) for p in paths]
    seen = set()
    for s in suites:
        for c in s["cases"]:
            if c["id"] in seen:
                raise SuiteError(f"duplicate case id {c['id']}")
            seen.add(c["id"])
    return suites


# ---------------------------------------------------------------------------
# JPEG metadata inspection (used to refuse photos that still carry EXIF/GPS)
# ---------------------------------------------------------------------------

def jpeg_segments(data: bytes) -> List[tuple]:
    """Return [(marker, start, end)] for header segments up to SOS. Raises on non-JPEG."""
    if data[:2] != b"\xff\xd8":
        raise ValueError("not a JPEG (missing SOI)")
    i = 2
    segs = []
    n = len(data)
    while i < n:
        if data[i] != 0xFF:
            raise ValueError(f"bad marker at {i}")
        while i < n and data[i] == 0xFF:
            i += 1
        marker = data[i]
        i += 1
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            continue
        seg_len = int.from_bytes(data[i:i + 2], "big")
        segs.append((marker, i - 2, i + seg_len))
        if marker == 0xDA:  # SOS: entropy-coded data follows
            break
        i += seg_len
    return segs


def jpeg_private_metadata(data: bytes) -> List[str]:
    """List metadata segments that could carry private info (EXIF/GPS/XMP/IPTC/comments)."""
    found = []
    for marker, start, end in jpeg_segments(data):
        payload = data[start + 4:end]
        if marker == 0xE1:
            found.append("APP1(EXIF)" if payload.startswith(b"Exif") else "APP1(XMP/other)")
        elif marker == 0xED:
            found.append("APP13(IPTC)")
        elif marker == 0xFE:
            found.append("COM")
        elif 0xE3 <= marker <= 0xEF and marker != 0xEE:
            found.append(f"APP{marker - 0xE0}")
    return found


def load_pricing() -> Dict[str, Any]:
    return read_json(PRICING_PATH)


def price_for(model: str, pricing: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    models = pricing.get("models", {})
    if model in models:
        return models[model]
    for name, p in models.items():
        if model.startswith(name):
            return p
    return None


def cost_from_usage(usage: Dict[str, Any], model: str, pricing: Dict[str, Any]) -> Optional[float]:
    p = price_for(model, pricing)
    if not p or not usage:
        return None
    in_rates = p["input_per_m"]
    details = usage.get("promptTokensDetails") or []
    if details:
        in_cost = sum(d.get("tokenCount", 0) * in_rates.get(d.get("modality"), in_rates["default"]) for d in details)
    else:
        in_cost = usage.get("promptTokenCount", 0) * in_rates["default"]
    out_tokens = (usage.get("candidatesTokenCount") or 0) + (usage.get("thoughtsTokenCount") or 0)
    return round((in_cost + out_tokens * p["output_per_m"]) / 1_000_000, 6)
