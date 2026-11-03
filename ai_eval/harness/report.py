"""Compare model runs and produce review material.

  python3 -I harness/report.py results/<run-dir> [results/<other-run-dir> ...]

Several run directories can be combined, e.g. a 2.5 Flash baseline recorded in November
with a later run of another model. Checks are recomputed with the CURRENT reference files,
so adding a sold price later re-scores old runs without re-calling any model.

Writes (into the first run directory, which Git ignores):
  comparison.md      full side-by-side with outputs and reference facts (private)
  review_sheet.csv   blind sheet: models shown as A/B/... in random order per case (private)
  review_key.json    which letter is which model, per case (private)
And into ai_eval/reports/ (candidate for Git after you review it):
  <run>_summary.md   aggregate metrics and check counts only: no item text, values or media
"""
from __future__ import annotations

import csv
import json
import random
import statistics
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import checks as checks_mod  # noqa: E402
from common import REPORTS_DIR, load_suite, read_json, write_json  # noqa: E402

CRITERIA = ["identification", "description", "valuation", "speed", "guidance"]


def load_runs(run_dirs, models=None):
    """Return {variant: {"meta":..., "records": {(case_id, run): record}}} and case defs.

    models: optional set of model names to keep (others in the run dirs are ignored)."""
    variants, cases = {}, {}
    for rd in run_dirs:
        rd = Path(rd)
        meta = read_json(rd / "run_meta.json")
        for c in read_json(rd / "cases_resolved.json"):
            cases.setdefault(c["id"], c)
        # Refresh references from the suite files as they are now.
        for s in meta["suites"]:
            try:
                for c in load_suite(Path(s["path"]))["cases"]:
                    if c["id"] in cases:
                        cases[c["id"]]["_reference"] = c["_reference"]
            except Exception:  # noqa: BLE001
                pass
        for model in meta["models"]:
            if models and model not in models:
                continue
            mdir = rd / model
            if not (mdir / "cases").exists():
                continue
            name = model if len(run_dirs) == 1 else f"{model} [{meta['label']} {rd.name[:8]}]"
            recs = {}
            for f in sorted((mdir / "cases").glob("*.json")):
                r = read_json(f)
                recs[(r["case_id"], r["run_index"])] = r
            variants[name] = {"meta": meta, "records": recs, "model": model}
    return variants, cases


def recheck(variants, cases):
    for v in variants.values():
        for key, r in v["records"].items():
            c = cases.get(r["case_id"])
            if c:
                r["checks"] = checks_mod.run_checks(c, r)


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    k = max(0, min(len(xs) - 1, round(p / 100 * (len(xs) - 1))))
    return xs[k]


def aggregate(v):
    recs = list(v["records"].values())
    lat = [r["latency_total_s"] for r in recs if r.get("latency_total_s") is not None]
    m = [r.get("metrics", {}) for r in recs]
    ok = sum(1 for r in recs if r.get("http_status") == 200)
    calls = sum(x.get("gemini_calls", 0) for x in m)
    cost = sum(x.get("cost_usd", 0) or 0 for x in m)
    counts = {"fail": 0, "warn": 0}
    for r in recs:
        for k, n in checks_mod.count(r.get("checks", [])).items():
            counts[k] += n
    versions = sorted({mv for x in m for mv in (x.get("model_versions") or [])})
    return {
        "runs": len(recs), "ok": ok,
        "first_pass_valid": sum(1 for r, x in zip(recs, m) if r.get("http_status") == 200 and not x.get("repairs")),
        "repairs": sum(x.get("repairs", 0) for x in m), "retries": sum(x.get("retries", 0) for x in m),
        "p50": pct(lat, 50), "p95": pct(lat, 95), "max": max(lat) if lat else None,
        "over_ios_timeout": sum(1 for x in lat if x > checks_mod.IOS_TIMEOUT_S),
        "calls": calls, "cost": cost, "cost_per_run": cost / len(recs) if recs else 0,
        "in_tok": statistics.mean([x.get("input_tokens", 0) for x in m]) if m else 0,
        "out_tok": statistics.mean([x.get("output_tokens", 0) for x in m]) if m else 0,
        "think_tok": statistics.mean([x.get("thinking_tokens", 0) for x in m]) if m else 0,
        "fails": counts["fail"], "warns": counts["warn"], "versions": versions,
    }


def fmt(x, nd=1):
    if x is None:
        return "-"
    if isinstance(x, float):
        return f"{x:.{nd}f}"
    return str(x)


def aggregate_table(variants, types=None):
    lines = ["| Model | Runs | OK | First-pass valid | Repairs | Retries | p50 s | p95 s | Max s | >35s | "
             "Avg in tok | Avg out tok | Avg thinking tok | Est cost | Cost/run | Check fails | Check warns | Served version |",
             "|" + "---|" * 18]
    for name, v in variants.items():
        vv = v if types is None else {**v, "records": {k: r for k, r in v["records"].items() if r["type"] in types}}
        a = aggregate(vv)
        if not a["runs"]:
            continue
        lines.append(f"| {name} | {a['runs']} | {a['ok']} | {a['first_pass_valid']} | {a['repairs']} | {a['retries']} | "
                     f"{fmt(a['p50'])} | {fmt(a['p95'])} | {fmt(a['max'])} | {a['over_ios_timeout']} | "
                     f"{a['in_tok']:.0f} | {a['out_tok']:.0f} | {a['think_tok']:.0f} | ${a['cost']:.4f} | "
                     f"${a['cost_per_run']:.4f} | {a['fails']} | {a['warns']} | {', '.join(a['versions']) or '-'} |")
    return "\n".join(lines)


def short_output(r):
    f = r.get("final_response") or {}
    t = r["type"]
    if r.get("http_status") != 200:
        return f"FAILED http={r.get('http_status')}: {json.dumps(f)[:300]}"
    if t in ("photo", "text"):
        vh = f.get("valueHints") or {}
        rng = f"${fmt(vh.get('valueLow'), 0)} / ${fmt(vh.get('estimatedValue'), 0)} / ${fmt(vh.get('valueHigh'), 0)}"
        if vh.get("valueLow") is None and vh.get("estimatedValue") is None and vh.get("valueHigh") is None:
            rng = "Not estimated"
        return (f"**{f.get('title')}** [{f.get('category')}] brand={f.get('brand')}; era={f.get('eraOrYear')}\n\n"
                f"{f.get('description')}\n\nValue: {rng} (conf {fmt(vh.get('confidenceScore'), 2)})\n\n"
                f"AI notes: {vh.get('aiNotes')}\n\nMissing details: {vh.get('missingDetails')}")
    if t == "audio":
        return f.get("summaryText", "")
    if t == "brief":
        opts = "; ".join(f"{o.get('path')}: {o.get('label')} net {((o.get('netProceeds') or {}).get('low'))}-"
                         f"{((o.get('netProceeds') or {}).get('high'))}" for o in f.get("pathOptions") or [])
        return f"Recommended: {f.get('recommendedPath')}\n\n{f.get('reasoning')}\n\nOptions: {opts}\n\nSteps: {f.get('actionSteps')}"
    if t == "plan":
        return "\n".join(f"{i.get('order')}. {i.get('text')}" for i in f.get("items") or [])
    return json.dumps(f)[:500]


def ref_text(c):
    ref = c.get("_reference") or {}
    if not ref:
        return "_No reference facts recorded._"
    parts = []
    if ref.get("identity"):
        parts.append(f"Identity: {ref['identity']}")
    if ref.get("facts"):
        parts.append("Facts: " + "; ".join(f"{k}: {v}" for k, v in ref["facts"].items()))
    for e in ref.get("saleEvidence", []):
        qty = int(e.get("quantity") or 1)
        q = f" for {qty} units (bundle, ${e['price'] / qty:,.0f} avg each)" if qty > 1 and e.get("price") else ""
        parts.append(f"{(e.get('type') or '?').upper()}: ${e.get('price')}{q} {e.get('date') or ''} {e.get('source') or ''} {e.get('notes') or ''}".strip())
    if ref.get("reviewNotes"):
        parts.append(f"Review: {ref['reviewNotes']}")
    return "  \n".join(parts)


def valuation_divergence(variants, case_id):
    likely = {}
    for name, v in variants.items():
        r = v["records"].get((case_id, 1))
        if r and r.get("http_status") == 200:
            vh = (r.get("final_response") or {}).get("valueHints") or {}
            if vh.get("estimatedValue"):
                likely[name] = vh["estimatedValue"]
    if len(likely) >= 2:
        hi, lo = max(likely.values()), min(likely.values())
        if lo > 0 and hi / lo >= 2:
            return f"likely values differ {hi / lo:.1f}x: " + ", ".join(f"{k} ${v:,.0f}" for k, v in likely.items())
    return None


def variance(v, case_id):
    runs = [r for (cid, _), r in v["records"].items() if cid == case_id and r.get("http_status") == 200]
    if len(runs) < 2:
        return None
    vals = [((r.get("final_response") or {}).get("valueHints") or {}).get("estimatedValue") for r in runs]
    cats = {(r.get("final_response") or {}).get("category") for r in runs}
    titles = [(r.get("final_response") or {}).get("title") for r in runs]
    nums = [x for x in vals if x is not None]
    spread = f"${min(nums):,.0f}-${max(nums):,.0f}" if nums else "n/a"
    return f"{len(runs)} runs: likely {spread}; categories {sorted(c for c in cats if c)}; titles {titles}"


def write_comparison(path, variants, cases, judgment):
    out = ["# LTC AI comparison (private)", ""]
    for name, v in variants.items():
        g = v["meta"]["gateway"]
        out.append(f"- **{name}**: run {v['meta']['created'][:16]}, pipeline fingerprint {g['pipeline_fingerprint']}, "
                   f"git {g['git'].get('commit')}{' (dirty)' if g['git'].get('gateway_app_dirty') else ''}"
                   f"{', MOCK' if v['meta'].get('mock') else ''}")
    out += ["", "## Aggregate", "", aggregate_table(variants), ""]
    for t in ("photo", "text", "brief", "plan", "audio"):
        out += [f"### {t}", "", aggregate_table(variants, {t}), ""]
    if judgment:
        out += ["## Cases needing Bruce's judgment", ""] + [f"- **{cid}**: {why}" for cid, why in judgment] + [""]
    out += ["## Case by case", ""]
    for cid, c in cases.items():
        if not any((cid, 1) in v["records"] for v in variants.values()):
            continue
        out += [f"### {cid} ({c['type']})", "", f"_{c.get('note', '')}_", "", "**Reference (independent of models):**  ",
                ref_text(c), ""]
        for name, v in variants.items():
            r = v["records"].get((cid, 1))
            if not r:
                continue
            m = r.get("metrics", {})
            flags = [f"{x['severity'].upper()} {x['check']}: {x['detail']}" for x in r.get("checks", [])
                     if x["severity"] in ("fail", "warn") or x["check"] in ("vs_sold", "policy_adjusted")]
            out += [f"#### {name}",
                    f"{fmt(r.get('latency_total_s'))}s, calls {m.get('gemini_calls')}, repairs {m.get('repairs')}, "
                    f"tokens in/out/thinking {m.get('input_tokens')}/{m.get('output_tokens')}/{m.get('thinking_tokens')}, "
                    f"${m.get('cost_usd', 0):.4f}, served {m.get('model_versions')}", "", short_output(r), ""]
            var = variance(v, cid)
            if var:
                out += [f"Repeat runs: {var}", ""]
            if flags:
                out += ["Flags:"] + [f"- {x}" for x in flags] + [""]
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def write_review_sheet(run_dir, variants, cases, blind_types=None):
    rng = random.Random(f"blind-{run_dir.name}")
    names = list(variants)
    letters = [chr(ord("A") + i) for i in range(len(names))]
    key, rows = {}, []
    # Balanced blinding: shuffle the case list, then rotate which model is "A" so each model
    # is A about equally often (a lopsided pattern could give the models away).
    eligible = [cid for cid, c in cases.items()
                if any((cid, 1) in variants[n]["records"] for n in names)
                and not (blind_types and c["type"] not in blind_types)]
    slot = {cid: i for i, cid in enumerate(rng.sample(eligible, len(eligible)))}
    for cid, c in cases.items():
        if cid not in slot:
            continue
        present = sorted((n for n in names if (cid, 1) in variants[n]["records"]),
                         key=lambda n: variants[n]["model"])
        k = slot[cid] % len(present)
        order = present[k:] + present[:k]
        key[cid] = {letters[i]: n for i, n in enumerate(order)}
        row = {"case_id": cid, "type": c["type"], "reference": ref_text(c).replace("  \n", " | ")}
        for i, n in enumerate(order):
            r = variants[n]["records"][(cid, 1)]
            row[f"{letters[i]}_output"] = short_output(r)
            row[f"{letters[i]}_seconds"] = fmt(r.get("latency_total_s"))
            for crit in CRITERIA:
                row[f"{letters[i]}_{crit}_1to5"] = ""
        row["preferred"] = ""
        row["notes"] = ""
        rows.append(row)
    if not rows:
        return
    fields = list(dict.fromkeys(k for r in rows for k in r))
    with open(run_dir / "review_sheet.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    write_json(run_dir / "review_key.json", key)


def write_sanitized(path, run_dir, variants, cases):
    out = [f"# AI regression summary: {run_dir.name}", "",
           "Sanitized: aggregate metrics and check names only. No item text, values, prompts or media.", ""]
    for name, v in variants.items():
        g = v["meta"]["gateway"]
        out.append(f"- {name}: pipeline {g['pipeline_fingerprint']}, git {g['git'].get('commit')}, "
                   f"suites {[s['suite'] + '@' + s['version'] for s in v['meta']['suites']]}"
                   f"{', MOCK' if v['meta'].get('mock') else ''}")
    out += ["", "## Aggregate", "", aggregate_table(variants), ""]
    for t in ("photo", "text", "brief", "plan", "audio"):
        tbl = aggregate_table(variants, {t})
        if tbl.count("\n") > 1:
            out += [f"### {t}", "", tbl, ""]
    out += ["## Per case (status, seconds, repairs, failing/warning checks)", "",
            "| Case | Type | " + " | ".join(variants) + " |", "|---|---|" + "---|" * len(variants)]
    for cid, c in cases.items():
        cells = []
        for v in variants.values():
            r = v["records"].get((cid, 1))
            if not r:
                cells.append("-")
                continue
            bad = sorted({x["check"] for x in r.get("checks", []) if x["severity"] in ("fail", "warn")})
            cells.append(f"{r.get('http_status')} {fmt(r.get('latency_total_s'))}s r{r.get('metrics', {}).get('repairs', 0)} "
                         f"{' '.join(bad)}".strip())
        if any(x != "-" for x in cells):
            out.append(f"| {cid} | {c['type']} | " + " | ".join(cells) + " |")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run_dirs", nargs="+", type=Path)
    ap.add_argument("--models", help="comma-separated models to include (default: all in the run dirs)")
    ap.add_argument("--blind-types", help="comma-separated case types for the blind sheet (default: all)")
    args = ap.parse_args()
    run_dirs = [p.resolve() for p in args.run_dirs]
    models = set(args.models.split(",")) if args.models else None
    blind_types = set(args.blind_types.split(",")) if args.blind_types else None
    variants, cases = load_runs(run_dirs, models)
    if not variants:
        print("No model results found.")
        return 1
    recheck(variants, cases)
    judgment = []
    for cid, c in cases.items():
        if c["type"] in ("photo", "text"):
            d = valuation_divergence(variants, cid)
            if d:
                judgment.append((cid, d))
            for name, v in variants.items():
                r = v["records"].get((cid, 1))
                for x in (r or {}).get("checks", []):
                    if x["check"] == "vs_sold" and x["severity"] == "warn":
                        judgment.append((cid, f"{name}: {x['detail']}"))
    main_dir = run_dirs[0]
    write_comparison(main_dir / "comparison.md", variants, cases, judgment)
    write_review_sheet(main_dir, variants, cases, blind_types)
    san = REPORTS_DIR / f"{main_dir.name}_summary.md"
    write_sanitized(san, main_dir, variants, cases)
    print(f"Private comparison: {main_dir / 'comparison.md'}")
    print(f"Blind review sheet: {main_dir / 'review_sheet.csv'} (key in review_key.json)")
    print(f"Sanitized summary:  {san}")
    print()
    print(aggregate_table(variants))
    return 0


if __name__ == "__main__":
    sys.exit(main())
