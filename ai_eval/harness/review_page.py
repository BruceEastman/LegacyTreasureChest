"""Blind side-by-side review page (local HTML, photos embedded) for one or more runs.

  python3 -I harness/report.py results/<run> [results/<run2> ...]        # writes review_key.json
  python3 -I harness/review_page.py results/<run> [results/<run2> ...]   # same run dirs, same order
  Both accept --models a,b to compare only some models; report.py also takes --blind-types photo,text.

Writes <first run dir>/blind_review.html (private; results/ is ignored by Git).
Models appear as A/B using the letters in review_key.json. Speed and technical checks are hidden
until "Reveal models" is pressed, because they would identify the model. Scores are kept in the
browser and saved with "Save scores" as blind_scores_<run>.json in Downloads.
"""
from __future__ import annotations

import base64
import html
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import read_json  # noqa: E402
from report import load_runs, recheck, ref_text, short_output  # noqa: E402

TECHNICAL = {"repair_needed", "retry_needed", "latency", "finish_reason", "multi_text_parts", "model_version_mismatch",
             "upstream_error", "upstream_transport", "route_error", "input", "category_normalized", "policy_adjusted"}
TYPE_ORDER = ["photo", "text", "audio", "brief", "plan"]
CRITERIA = [("identification", "Identification"), ("description", "Description"), ("valuation", "Valuation"),
            ("guidance", "Guidance / usefulness")]
E = html.escape


def money(x):
    return "?" if x is None else f"${x:,.0f}"


def img_tag(case):
    p = case.get("_photo_path")
    if not p:
        return ""
    p = Path(p)
    alt = p.parent.parent / "review_imgs" / p.name
    src = alt if alt.exists() else p
    data = base64.b64encode(src.read_bytes()).decode()
    return f'<img src="data:image/jpeg;base64,{data}" alt="{E(case["id"])}">'


def value_line(f):
    vh = f.get("valueHints") or {}
    lo, est, hi = vh.get("valueLow"), vh.get("estimatedValue"), vh.get("valueHigh")
    if lo is None and est is None and hi is None:
        return "Not estimated"
    return f"{money(lo)} to {money(hi)}, likely {money(est)}"


def option_html(case, recs):
    r = recs[0]
    f = r.get("final_response") or {}
    if r.get("http_status") != 200:
        body = f"<p class=bad>Failed (HTTP {r.get('http_status')})</p>"
    elif case["type"] in ("photo", "text"):
        vh = f.get("valueHints") or {}
        extras = ""
        if len(recs) > 1:
            extras = "<p class=rep>Repeat runs: " + "; ".join(
                f"run {x['run_index']}: {E(str((x.get('final_response') or {}).get('title')))}, "
                f"{value_line(x.get('final_response') or {})}" for x in recs[1:]) + "</p>"
        body = (f"<h4>{E(str(f.get('title')))}</h4><p class=meta>{E(str(f.get('category')))}"
                f"{' · ' + E(str(f.get('brand'))) if f.get('brand') else ''}"
                f"{' · ' + E(str(f.get('eraOrYear'))) if f.get('eraOrYear') else ''}</p>"
                f"<p>{E(str(f.get('description') or ''))}</p>"
                f"<p class=val>{value_line(f)} <span class=conf>(confidence {vh.get('confidenceScore')})</span></p>"
                f"<p class=notes>{E(str(vh.get('aiNotes') or ''))}</p>"
                + (f"<p class=notes>Missing: {E('; '.join(map(str, vh.get('missingDetails') or [])))}</p>"
                   if vh.get("missingDetails") else "") + extras)
    else:
        body = "<pre>" + E(short_output(r)) + "</pre>"
    flags = [c for x in recs for c in x.get("checks", []) if c["severity"] in ("fail", "warn")]
    qual = sorted({f"{c['severity']}: {c['detail']}" for c in flags if c["check"] not in TECHNICAL})
    tech = sorted({f"{c['severity']}: {c['check']}: {c['detail']}" for c in flags if c["check"] in TECHNICAL})
    lat = ", ".join(f"{x.get('latency_total_s', 0):.1f}s" for x in recs)
    return body, qual, tech, lat


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run_dirs", nargs="+", type=Path)
    ap.add_argument("--models", help="comma-separated models to include (use the same value as report.py)")
    args = ap.parse_args()
    run_dirs = args.run_dirs
    variants, cases = load_runs(run_dirs, set(args.models.split(",")) if args.models else None)
    recheck(variants, cases)
    key = read_json(run_dirs[0] / "review_key.json")
    sections = {t: [] for t in TYPE_ORDER}
    for cid, c in cases.items():
        if cid not in key:
            continue
        cols = []
        for letter, vname in sorted(key[cid].items()):
            recs = sorted((r for (k, _), r in variants[vname]["records"].items() if k == cid),
                          key=lambda r: r["run_index"])
            body, qual, tech, lat = option_html(c, recs)
            scores = "".join(
                f'<label>{lbl} <select data-k="{cid}|{letter}|{k}"><option></option>'
                + "".join(f"<option>{i}</option>" for i in range(1, 6)) + "</select></label>"
                for k, lbl in CRITERIA)
            cols.append(
                f'<div class=opt><div class=letter>Option {letter}</div>{body}'
                + (f"<ul class=flags>{''.join(f'<li>{E(q)}</li>' for q in qual)}</ul>" if qual else "")
                + f'<div class=reveal hidden><b>{E(variants[vname]["model"])}</b> · {lat}'
                + (f"<ul>{''.join(f'<li>{E(t)}</li>' for t in tech)}</ul>" if tech else "") + "</div>"
                + f'<div class=scores>{scores}</div></div>')
        ref = E(ref_text(c)).replace("  \n", "<br>")
        inp = ""
        if c["type"] != "photo":
            ci = {k: v for k, v in c.items() if not k.startswith("_") and k not in ("id", "type", "repeat", "enabled")}
            inp = f"<details><summary>Input sent to the model</summary><pre>{E(json.dumps(ci, indent=1)[:4000])}</pre></details>"
        sections[c["type"]].append(
            f'<section class=case><h3>{E(cid)}</h3><div class=top>{img_tag(c)}'
            f'<div class=ref><b>Reference (not sent to the model)</b><br>{ref}{inp}</div></div>'
            f'<div class=opts>{"".join(cols)}</div>'
            f'<div class=pref>Preferred: '
            + "".join(f'<label><input type=radio name="p_{cid}" value="{v}" data-k="{cid}|pref">{v}</label>'
                      for v in list(sorted(key[cid])) + ["Tie"])
            + f'<textarea data-k="{cid}|notes" placeholder="Notes"></textarea></div></section>')
    body = "".join(f"<h2>{t.title()} ({len(s)})</h2>{''.join(s)}" for t, s in sections.items() if s)
    run = run_dirs[0].name
    page = f"""<!doctype html><html lang=en><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1"><title>Blind Model Review</title><style>
:root{{--bg:#fafaf8;--fg:#1d1d1b;--mut:#666;--card:#fff;--line:#ddd;--warn:#9a5b00;--bad:#b00020;--acc:#2a5db0}}
@media (prefers-color-scheme:dark){{:root{{--bg:#161616;--fg:#eee;--mut:#aaa;--card:#202020;--line:#383838;--warn:#e0a040;--bad:#ff6b6b;--acc:#7aa7ff}}}}
body{{background:var(--bg);color:var(--fg);font:15px/1.45 -apple-system,system-ui,sans-serif;margin:0 auto;max-width:1200px;padding:16px}}
.case{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px;margin:14px 0}}
.top{{display:flex;gap:14px;flex-wrap:wrap}} .top img{{max-width:320px;width:100%;border-radius:6px}}
.ref{{flex:1;min-width:260px;font-size:14px;color:var(--mut)}} .opts{{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:12px}}
@media (max-width:760px){{.opts{{grid-template-columns:1fr}}}}
.opt{{border:1px solid var(--line);border-radius:8px;padding:10px}} .letter{{font-weight:700;color:var(--acc)}}
h4{{margin:6px 0 2px}} .meta,.conf,.notes,.rep{{color:var(--mut);font-size:13px}} .val{{font-weight:600}}
.flags{{color:var(--warn);font-size:13px;padding-left:18px}} .bad{{color:var(--bad)}}
.reveal{{background:var(--bg);border-radius:6px;padding:6px;font-size:13px;margin-top:6px}}
.scores label{{display:inline-block;margin:4px 10px 0 0;font-size:13px}} pre{{white-space:pre-wrap;font-size:13px}}
.pref{{margin-top:10px}} .pref label{{margin-right:12px}} textarea{{width:100%;min-height:40px;margin-top:6px;background:var(--card);color:var(--fg);border:1px solid var(--line);border-radius:6px}}
.bar{{position:sticky;top:0;background:var(--bg);padding:8px 0;border-bottom:1px solid var(--line);z-index:2}}
button{{font:inherit;padding:6px 12px;margin-right:8px;border-radius:6px;border:1px solid var(--line);background:var(--card);color:var(--fg);cursor:pointer}}
</style></head><body>
<h1>Blind model review</h1>
<p>Each item shows two answers, A and B, in random order. Response times and technical details are hidden because they would
reveal the model. Score 1 (poor) to 5 (excellent). Judge identification first, then description, then valuation
(real sales beat asking prices; agreement between the two answers is not proof either is right). Scores save in this browser
as you go.</p>
<div class=bar><button id=save>Save scores</button><button id=rev>Reveal models</button><span id=st></span></div>
{body}
<script>
const KEY="blind_review_{run}";let s={{}};try{{s=JSON.parse(localStorage.getItem(KEY)||"{{}}")}}catch(e){{}}
document.querySelectorAll("[data-k]").forEach(el=>{{const k=el.dataset.k;
 if(el.type==="radio"){{if(s[k]===el.value)el.checked=true}}else if(s[k]!=null)el.value=s[k];
 el.addEventListener("change",()=>{{s[k]=el.value;try{{localStorage.setItem(KEY,JSON.stringify(s))}}catch(e){{}}}})}});
document.getElementById("save").onclick=()=>{{const b=new Blob([JSON.stringify({{run:"{run}",saved:new Date().toISOString(),scores:s}},null,1)],{{type:"application/json"}});
 const a=document.createElement("a");a.href=URL.createObjectURL(b);a.download="blind_scores_{run}.json";a.click();
 document.getElementById("st").textContent=" Saved to Downloads."}};
document.getElementById("rev").onclick=()=>{{if(confirm("Reveal which model is A and B? Do this after scoring."))
 document.querySelectorAll(".reveal").forEach(e=>e.hidden=false)}};
</script></body></html>"""
    out = run_dirs[0] / "blind_review.html"
    out.write_text(page, encoding="utf-8")
    print(f"Blind review page: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
