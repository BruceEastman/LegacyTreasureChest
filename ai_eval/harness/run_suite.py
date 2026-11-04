"""LTC AI regression suite runner.

Examples (run from LegacyTreasureChest_App/ai_eval):

  # Show the manifest, call counts and cost estimate. No network, no key.
  python3 -I harness/run_suite.py --suite suites/core_v1/suite.json \
      --suite private/inventory_v1/suite.json \
      --model gemini-2.5-flash --model gemini-3.5-flash-lite --dry-run

  # Offline end-to-end test of the harness with a fake Gemini.
  python3 -I harness/run_suite.py --suite suites/core_v1/suite.json --model gemini-2.5-flash --mock

  # Live run. The key is read from Secret Manager into memory and handed to the worker on stdin.
  python3 -I harness/run_suite.py --suite ... --model gemini-2.5-flash --model gemini-3.5-flash-lite --label baseline

Safety: the worker runs the gateway locally and only permits outbound
POST generativelanguage.googleapis.com/.../:generateContent. Nothing is sent to Cloud Run,
nothing in Google Cloud is modified, and the key is never printed or written to disk.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common import (  # noqa: E402
    GATEWAY_PYTHON, HARNESS_DIR, HARNESS_VERSION, RESULTS_DIR, SuiteError, gateway_fingerprint,
    jpeg_private_metadata, load_pricing, load_suites, price_for, write_json,
)

DEFAULT_PROJECT = "legacy-treasure-chest"
DEFAULT_SECRET = "gemini-api-key"  # the secret production Cloud Run reads

# Planning assumptions for the cost estimate (tokens per call). Prompt sizes were measured
# from the current prompts; thinking use is a rough guess and is replaced by real numbers
# once a run completes.
EST_INPUT = {"photo": 560, "text": 710, "brief": 1100, "plan": 1000, "audio": 250}
EST_IMAGE_TOKENS = {"gemini-2.5": 1300, "default": 1120}
EST_OUTPUT = {"photo": 900, "text": 900, "brief": 1500, "plan": 1200, "audio": 80}
EST_THINKING = {"gemini-2.5-flash": 1500, "gemini-3.5-flash-lite": 150, "gemini-3.6-flash": 1500}
MAX_OUT = {"audio": 256, "default": 4096}


def _call_estimate(case: dict, model: str, pricing: dict, worst: bool) -> float:
    t = case["type"]
    p = price_for(model, pricing)
    if not p:
        return 0.0
    inp = EST_INPUT[t]
    audio_tokens = 0
    if t == "photo" or (t == "brief" and case.get("photo")):
        inp += EST_IMAGE_TOKENS["gemini-2.5"] if model.startswith("gemini-2.5") else EST_IMAGE_TOKENS["default"]
    if t == "audio":
        audio_tokens = 25 * int(case.get("seconds", 30))
    cap = MAX_OUT.get(t, MAX_OUT["default"])
    out = cap if worst else min(cap, EST_OUTPUT[t] + EST_THINKING.get(model, 1500))
    in_rate = p["input_per_m"]
    cost = (inp * in_rate["default"] + audio_tokens * in_rate.get("AUDIO", in_rate["default"])
            + out * p["output_per_m"]) / 1e6
    return cost * (2 if worst else 1)  # worst case: every call needs one repair


def manifest(suites, models, pricing) -> dict:
    rows, totals = [], {m: {"calls": 0, "worst_calls": 0, "est": 0.0, "worst": 0.0} for m in models}
    problems = []
    for s in suites:
        for c in s["cases"]:
            reps = int(c.get("repeat", 1))
            for key in ("_photo_path", "_audio_path"):
                if key in c:
                    p = Path(c[key])
                    if not p.exists():
                        problems.append(f"{c['id']}: missing {key[1:-5]} file {p}")
                    elif key == "_photo_path":
                        try:
                            meta = jpeg_private_metadata(p.read_bytes())
                            if meta:
                                problems.append(f"{c['id']}: photo has metadata {meta}; run prepare_photos.py")
                        except ValueError as e:
                            problems.append(f"{c['id']}: {e}")
            rows.append({"suite": s["meta"]["suite"], "id": c["id"], "type": c["type"], "repeat": reps,
                         "has_reference": bool(c["_reference"]),
                         "sold_evidence": sum(1 for e in c["_reference"].get("saleEvidence", [])
                                              if (e.get("type") or "").lower() == "sold"
                                              and e.get("price") is not None)})
            for m in models:
                totals[m]["calls"] += reps
                totals[m]["worst_calls"] += 2 * reps
                totals[m]["est"] += reps * _call_estimate(c, m, pricing, False)
                totals[m]["worst"] += reps * _call_estimate(c, m, pricing, True)
    return {"rows": rows, "totals": totals, "problems": problems}


def print_manifest(man: dict) -> None:
    by_type = {}
    for r in man["rows"]:
        by_type.setdefault(r["type"], []).append(r)
    print("\nTEST MANIFEST")
    for t in ("photo", "text", "brief", "plan", "audio"):
        rs = by_type.get(t, [])
        if not rs:
            continue
        runs = sum(r["repeat"] for r in rs)
        print(f"  {t:6s} {len(rs):3d} cases, {runs:3d} runs per model: "
              + ", ".join(f"{r['id']}{'x' + str(r['repeat']) if r['repeat'] > 1 else ''}"
                          f"{'*' if r['sold_evidence'] else ''}" for r in rs))
    print("  (* = has sold-price reference)")
    print("\nCALLS AND ESTIMATED COST")
    grand_est = grand_worst = 0.0
    for m, t in man["totals"].items():
        print(f"  {m:24s} {t['calls']:3d} calls (up to {t['worst_calls']} with repairs)  "
              f"est ${t['est']:.2f}, worst ${t['worst']:.2f}")
        grand_est += t["est"]
        grand_worst += t["worst"]
    print(f"  {'TOTAL':24s} est ${grand_est:.2f}, worst ${grand_worst:.2f}")
    if man["problems"]:
        print("\nPROBLEMS (must be fixed before a live run):")
        for p in man["problems"]:
            print("  -", p)


def fetch_key(project: str, secret: str, version: str) -> str:
    r = subprocess.run(["gcloud", "secrets", "versions", "access", version, f"--secret={secret}",
                        f"--project={project}"], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"Could not read secret {secret} (gcloud exit {r.returncode}). Re-run `gcloud auth login`.")
    return r.stdout.strip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--suite", action="append", required=True, type=Path)
    ap.add_argument("--model", action="append", required=True)
    ap.add_argument("--only", help="comma-separated case ids")
    ap.add_argument("--types", help="comma-separated case types to include, e.g. photo,text")
    ap.add_argument("--label", default="run")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--mock", action="store_true", help="fake Gemini responses; no network")
    ap.add_argument("--mock-scenario", default="normal", choices=["normal", "repair", "invented_category", "style_list"])
    ap.add_argument("--project", default=DEFAULT_PROJECT)
    ap.add_argument("--secret", default=DEFAULT_SECRET)
    ap.add_argument("--secret-version", default="latest")
    ap.add_argument("--yes", action="store_true", help="skip the confirmation prompt for live runs")
    args = ap.parse_args()

    try:
        suites = load_suites(args.suite)
    except SuiteError as e:
        print("Suite error:", e)
        return 2
    only = set(args.only.split(",")) if args.only else None
    types = set(args.types.split(",")) if args.types else None
    for s in suites:
        s["cases"] = [c for c in s["cases"] if (not only or c["id"] in only) and (not types or c["type"] in types)]

    pricing = load_pricing()
    man = manifest(suites, args.model, pricing)
    print_manifest(man)
    if args.dry_run:
        return 0
    if man["problems"]:
        print("\nRefusing to run until the problems above are fixed.")
        return 2
    if not args.mock and not args.yes:
        if input("\nProceed with LIVE Gemini calls? Type 'yes': ").strip().lower() != "yes":
            print("Cancelled.")
            return 1

    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = RESULTS_DIR / f"{stamp}_{args.label}{'_MOCK' if args.mock else ''}"
    cases = [c for s in suites for c in s["cases"]]
    write_json(run_dir / "cases_resolved.json", cases)
    write_json(run_dir / "run_meta.json", {
        "created": dt.datetime.now().astimezone().isoformat(), "harness_version": HARNESS_VERSION,
        "label": args.label, "mock": args.mock, "mock_scenario": args.mock_scenario if args.mock else None,
        "models": args.model, "pricing": pricing,
        "suites": [{"path": s["path"], "suite": s["meta"]["suite"], "version": s["meta"]["version"],
                    "sha256": s["sha256"]} for s in suites],
        "gateway": gateway_fingerprint(), "manifest": man,
        "key_source": None if args.mock else f"secret-manager:{args.project}/{args.secret}:{args.secret_version}",
    })

    key = "" if args.mock else fetch_key(args.project, args.secret, args.secret_version)
    rc_all = 0
    for model in args.model:
        print(f"\n== {model}")
        cmd = [str(GATEWAY_PYTHON), "-I", str(HARNESS_DIR / "worker.py"), "--model", model,
               "--cases", str(run_dir / "cases_resolved.json"), "--out", str(run_dir / model)]
        if args.mock:
            cmd += ["--mock", "--mock-scenario", args.mock_scenario]
        proc = subprocess.run(cmd, input=(key + "\n") if key else "", text=True)
        if proc.returncode != 0:
            print(f"worker for {model} exited {proc.returncode}")
            rc_all = proc.returncode
    key = ""  # drop the reference
    print(f"\nResults: {run_dir}")
    print(f"Next: python3 -I harness/report.py {run_dir}")
    return rc_all


if __name__ == "__main__":
    sys.exit(main())
