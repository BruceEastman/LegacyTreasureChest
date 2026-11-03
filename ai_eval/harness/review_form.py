"""Generate a local review form for the selected items of a private collection.

  python3 -I harness/review_form.py private/inventory_v1 [--all]

Writes <collection>/review_form.html (self-contained; open it in a browser, never upload it).
Each selected item shows its photos, Claude's provisional identification, and what is already
recorded, with fields for corrections and actual sale information. Answers autosave in the
browser. "Save review file" downloads review_<collection>.json, which
harness/import_review.py turns into items.csv and sales.csv rows.
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import html
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_suite import CANONICAL  # noqa: E402
from catalog import read_csv  # noqa: E402
from common import read_json  # noqa: E402
from prepare_photos import prepare_one  # noqa: E402

FACT_FIELDS = [("maker", "Maker / brand"), ("model", "Model, pattern or reference"),
               ("era", "Era or year"), ("materials", "Materials"), ("condition", "Condition"),
               ("set_size", "Quantity or set size you own(ed)")]
OUTCOMES = ["", "sold", "still own", "donated", "gave to family", "discarded", "unknown"]
EVIDENCE_TYPES = ["asking", "appraisal", "offer", "estimate", "sold"]


def esc(x) -> str:
    return html.escape(str(x or ""), quote=True)


def img_data(coll: Path, ph: str) -> str:
    out = coll / "review_imgs" / f"{ph}.jpg"
    if not out.exists():
        cat = {p["id"]: p for p in read_json(coll / "catalog.json")["photos"]}
        prepare_one(coll / "originals" / cat[ph]["original"], out, max_px=640)
    return "data:image/jpeg;base64," + base64.b64encode(out.read_bytes()).decode()


def field(name, label, value="", kind="text", wide=False, placeholder=""):
    cls = "f wide" if wide else "f"
    if kind == "textarea":
        ctl = f'<textarea name="{name}" rows="2" placeholder="{esc(placeholder)}">{esc(value)}</textarea>'
    else:
        ctl = f'<input type="{kind}" name="{name}" value="{esc(value)}" placeholder="{esc(placeholder)}">'
    return f'<label class="{cls}"><span>{esc(label)}</span>{ctl}</label>'


def select(name, label, options, value=""):
    opts = "".join(f'<option value="{esc(o)}"{" selected" if o == value else ""}>{esc(o) or "(choose)"}</option>'
                   for o in options)
    return f'<label class="f"><span>{esc(label)}</span><select name="{name}">{opts}</select></label>'


def item_block(coll, it, notes_by_photo, sales):
    iid = it["item_id"]
    phs = [it["primary_photo"]] + [x.strip() for x in it.get("supporting_photos", "").split(";") if x.strip()]
    imgs = "".join(f'<figure><img src="{img_data(coll, ph)}" alt="{esc(ph)}"><figcaption>{esc(ph)}'
                   f'{" (primary)" if i == 0 else " (supporting)"}</figcaption></figure>' for i, ph in enumerate(phs))
    n = notes_by_photo.get(it["primary_photo"], {})
    sold = next((s for s in sales if s["item_id"] == iid and s.get("type") == "sold"), {})
    other = next((s for s in sales if s["item_id"] == iid and s.get("type") != "sold"), {})
    facts = {k: it.get(k, "") for k, _ in FACT_FIELDS}
    recorded = []
    if it.get("identity"):
        recorded.append(f"Identity: {it['identity']}")
    if sold:
        q = f" for {sold.get('quantity')} units" if (sold.get("quantity") or "1") != "1" else ""
        recorded.append(f"Sold: ${sold.get('price')}{q}, {sold.get('source', '')}")
    return f"""
<section class="item" data-item="{esc(iid)}">
  <h2>{esc(iid)} <small>{esc(n.get('category_guess', ''))}</small></h2>
  <div class="imgs">{imgs}</div>
  <p class="prov"><b>Claude's provisional identification (unverified):</b> {esc(it.get('provisional_description') or n.get('description'))}</p>
  {'<p class="rec"><b>Already recorded:</b> ' + esc(' · '.join(recorded)) + '</p>' if recorded else ''}
  <fieldset><legend>Identification</legend>
    <div class="radios">Is the provisional identification right?
      {''.join(f'<label><input type="radio" name="id_check" value="{v}"> {v}</label>' for v in ("yes", "partly", "no"))}</div>
    {field("identity", "What it actually is (your words)", it.get("identity"), "textarea", True)}
    <div class="row">{''.join(field(k, lbl, facts[k]) for k, lbl in FACT_FIELDS)}</div>
    <div class="row">{select("category", "LTC category", [""] + CANONICAL, it.get("category", ""))}</div>
    {field("must_mention", "Facts a correct AI answer should state from this photo (separate with ;)", it.get("must_mention"), "text", True,
           "e.g. TAG Heuer; Carrera; automatic")}
    {field("must_not_claim", "Claims that would be wrong or invented (separate with ;)", it.get("must_not_claim"), "text", True,
           "e.g. chronograph; quartz")}
    <div class="row">{field("hint_title", "Title you would type in LTC", it.get("hint_title"))}
    {field("hint_description", "Description you would type in LTC", it.get("hint_description"), "text", True)}</div>
  </fieldset>
  <fieldset><legend>Actual outcome</legend>
    <div class="row">{select("outcome", "What happened to it", OUTCOMES, "sold" if sold else "")}
    {field("sold_price", "Sale price ($)", sold.get("price", ""))}
    {field("sold_quantity", "Units covered by that price", sold.get("quantity", "") or "")}
    {field("sold_date", "Sale date (approximate is fine)", sold.get("date", ""))}
    {field("sold_source", "Where and how it sold", sold.get("source", ""))}</div>
    {field("sold_notes", "Sale notes (condition at sale, bundle, negotiation, fees)", sold.get("notes", ""), "text", True)}
    <div class="row">{select("other_type", "Other price evidence", [""] + EVIDENCE_TYPES, other.get("type", ""))}
    {field("other_price", "Price ($)", other.get("price", ""))}
    {field("other_quantity", "Units", other.get("quantity", "") or "")}
    {field("other_date", "Date", other.get("date", ""))}
    {field("other_source", "Source", other.get("source", ""))}</div>
  </fieldset>
  <fieldset><legend>Test setup</legend>
    <div class="row">{select("repeat", "Runs per model", ["1", "3"], it.get("repeat") or "1")}
    {select("status", "Status", ["selected", "alternate", "candidate", "excluded"], it.get("status") or "selected")}</div>
    {field("review_notes", "Anything else a reviewer should know", it.get("review_notes"), "textarea", True)}
  </fieldset>
</section>"""


CSS = """
:root{--bg:#f7f6f3;--card:#fff;--text:#1d1d1f;--muted:#6b6b70;--line:#e3e1dc;--accent:#1f5fa8;--warnbg:#fbf3dc}
@media (prefers-color-scheme:dark){:root{--bg:#161617;--card:#222224;--text:#f2f2f2;--muted:#a1a1a6;--line:#38383b;--accent:#7fb2ee;--warnbg:#3a3220}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.45 -apple-system,system-ui,sans-serif}
main{max-width:980px;margin:0 auto;padding:24px 16px 120px}h1{font-size:22px;margin:0 0 6px}.sub{color:var(--muted)}
.item,.box{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin:18px 0}
h2{margin:0 0 10px;font-size:18px}h2 small{color:var(--muted);font-weight:500;margin-left:6px}
.imgs{display:flex;gap:10px;flex-wrap:wrap}figure{margin:0}figure img{max-height:300px;max-width:100%;border-radius:8px;display:block}
figcaption{font-size:12px;color:var(--muted)}.prov{background:var(--warnbg);padding:8px 10px;border-radius:8px}.rec{color:var(--muted)}
fieldset{border:1px solid var(--line);border-radius:10px;margin:12px 0 0;padding:10px 12px}legend{font-weight:600;padding:0 6px}
.row{display:flex;flex-wrap:wrap;gap:10px}.f{display:flex;flex-direction:column;gap:3px;flex:1 1 180px;margin:6px 0}.f.wide{flex-basis:100%}
.f span{font-size:12px;color:var(--muted)}input,textarea,select{font:inherit;padding:7px 9px;border:1px solid var(--line);border-radius:7px;background:var(--bg);color:var(--text);width:100%}
.radios{margin:4px 0 6px}.radios label{margin-left:14px}.bar{position:fixed;left:0;right:0;bottom:0;background:var(--card);border-top:1px solid var(--line);padding:10px 16px;display:flex;gap:10px;justify-content:center;flex-wrap:wrap}
button{font:inherit;font-weight:600;padding:9px 16px;border-radius:8px;border:1px solid var(--accent);background:var(--accent);color:#fff;cursor:pointer}
button.alt{background:transparent;color:var(--accent)}#out{width:100%;height:160px;font:12px ui-monospace,Menlo,monospace;display:none;margin-top:10px}
#status{color:var(--muted);align-self:center;font-size:13px}
"""

JS = r"""
const KEY = "ltc-review-" + COLLECTION;
function collect(){
  const data = {collection: COLLECTION, generated: GENERATED, saved: new Date().toISOString(), items: {}, associations: {}, general_notes: ""};
  document.querySelectorAll("section.item").forEach(sec => {
    const o = {};
    sec.querySelectorAll("input,textarea,select").forEach(el => {
      if (el.type === "radio") { if (el.checked) o[el.name] = el.value; }
      else o[el.name] = el.value.trim();
    });
    data.items[sec.dataset.item] = o;
  });
  document.querySelectorAll("[data-assoc]").forEach(el => { data.associations[el.dataset.assoc] = el.value.trim(); });
  data.general_notes = document.getElementById("general").value.trim();
  return data;
}
function restore(){
  let d; try { d = JSON.parse(localStorage.getItem(KEY) || "null"); } catch(e) { d = null; }
  if (!d || d.generated !== GENERATED) return;
  document.querySelectorAll("section.item").forEach(sec => {
    const o = d.items[sec.dataset.item] || {};
    sec.querySelectorAll("input,textarea,select").forEach(el => {
      if (!(el.name in o)) return;
      if (el.type === "radio") el.checked = (o[el.name] === el.value); else el.value = o[el.name];
    });
  });
  document.querySelectorAll("[data-assoc]").forEach(el => { if (d.associations[el.dataset.assoc]) el.value = d.associations[el.dataset.assoc]; });
  document.getElementById("general").value = d.general_notes || "";
  document.getElementById("status").textContent = "Restored your unsaved answers.";
}
function autosave(){ try { localStorage.setItem(KEY, JSON.stringify(collect())); document.getElementById("status").textContent = "Autosaved " + new Date().toLocaleTimeString(); } catch(e) {} }
function download(){
  const blob = new Blob([JSON.stringify(collect(), null, 2)], {type: "application/json"});
  const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = "review_" + COLLECTION + ".json";
  document.body.appendChild(a); a.click(); a.remove();
  document.getElementById("status").textContent = "Saved review_" + COLLECTION + ".json to your Downloads folder. Tell Claude it is ready.";
}
function showText(){ const t = document.getElementById("out"); t.style.display = "block"; t.value = JSON.stringify(collect(), null, 2); t.select(); }
document.addEventListener("input", autosave); document.addEventListener("change", autosave);
window.addEventListener("load", restore);
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("collection", type=Path)
    ap.add_argument("--all", action="store_true", help="include alternates and candidates")
    args = ap.parse_args()
    coll = args.collection.resolve()
    cat = read_json(coll / "catalog.json")
    notes = read_json(coll / "provisional_notes.json") if (coll / "provisional_notes.json").exists() else {}
    notes_by_photo = {p["id"]: notes.get(p["original"], {}) for p in cat["photos"]}
    items = read_csv(coll / "items.csv")
    sales = read_csv(coll / "sales.csv")
    chosen = [it for it in items if args.all or it.get("status") == "selected"]
    generated = dt.datetime.now().isoformat(timespec="seconds")
    assoc = notes.get("_associations", {})
    assoc_html = "".join(
        f'<label class="f wide"><span><b>{esc(k)}</b>: {esc(v)}</span>'
        f'<input data-assoc="{esc(k)}" placeholder="Confirm, correct, or leave blank"></label>' for k, v in assoc.items())
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LTC Item Review</title><style>{CSS}</style></head><body><main>
<h1>LTC evaluation: item review</h1>
<p class="sub">{len(chosen)} items · {esc(coll.name)} · generated {generated[:16]} · local file, private.
Fill in only what you know; blanks are fine. Answers autosave in this browser. When done, press <b>Save review file</b>.</p>
<div class="box"><h2>Photo associations</h2>{assoc_html}</div>
{''.join(item_block(coll, it, notes_by_photo, sales) for it in chosen)}
<div class="box"><h2>General notes</h2><textarea id="general" rows="3" placeholder="Anything else about the collection or the test"></textarea>
<textarea id="out" readonly></textarea></div>
</main>
<div class="bar"><button onclick="download()">Save review file</button>
<button class="alt" onclick="showText()">Show as text (to paste)</button><span id="status"></span></div>
<script>const COLLECTION={json.dumps(coll.name)};const GENERATED={json.dumps(generated)};{JS}</script>
</body></html>"""
    out = coll / "review_form.html"
    out.write_text(page, encoding="utf-8")
    print(f"review form: {out} ({len(chosen)} items)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
