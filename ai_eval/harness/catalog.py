"""Photo catalog for a private evaluation collection.

  python3 -I harness/catalog.py private/inventory_v1          # scan, prepare, seed CSVs, render sheet
  python3 -I harness/catalog.py private/inventory_v1 --sheet  # re-render the contact sheet only

What it does (originals are only ever read, never renamed or modified):
  catalog.json        stable photo ids (ph-01, ph-02, ...) keyed by original filename + sha256.
                      New files get the next id; ids are never reused or reassigned.
  photos/<ph-id>.jpg  upright JPEG q85 with EXIF/GPS/XMP removed (what the harness sends)
  thumbs/<ph-id>.jpg  small metadata-free thumbnails for the contact sheet
  items.csv           one row per item (seeded one item per photo if missing; you edit it)
  sales.csv           sale outcomes and listings (header only if missing; you edit it)
  contact_sheet.html  local, self-contained review page (never uploaded anywhere)
"""
from __future__ import annotations

import argparse
import base64
import csv
import datetime as dt
import html
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import read_json, sha256_file, write_json  # noqa: E402
from prepare_photos import EXTS, prepare_one  # noqa: E402

ITEM_FIELDS = [
    "item_id", "status", "repeat", "primary_photo", "supporting_photos", "provisional_description",
    "identity", "category", "acceptable_categories", "must_mention", "must_not_claim",
    "hint_title", "hint_description", "review_notes",
    "maker", "model", "era", "materials", "condition", "set_size", "outcome", "id_check",
]
SALE_FIELDS = ["item_id", "type", "price", "quantity", "date", "source", "notes"]


def _sips_prop(path: Path, prop: str) -> str:
    out = subprocess.run(["sips", "-g", prop, str(path)], capture_output=True, text=True).stdout.strip().splitlines()
    return out[-1].split(":", 1)[1].strip() if len(out) > 1 and ":" in out[-1] else ""


def scan(coll: Path) -> dict:
    originals = coll / "originals"
    cat_path = coll / "catalog.json"
    cat = read_json(cat_path) if cat_path.exists() else {"photos": []}
    by_name = {p["original"]: p for p in cat["photos"]}
    next_n = max([int(p["id"].split("-")[1]) for p in cat["photos"]] + [0]) + 1
    present = set()
    for f in sorted(x for x in originals.iterdir() if x.suffix.lower() in EXTS):
        present.add(f.name)
        sha = sha256_file(f)
        rec = by_name.get(f.name)
        if rec is None:
            rec = {"id": f"ph-{next_n:02d}", "original": f.name, "added": dt.date.today().isoformat()}
            next_n += 1
            cat["photos"].append(rec)
            by_name[f.name] = rec
        if rec.get("sha256") and rec["sha256"] != sha:
            rec["changed_since_cataloged"] = True
        rec.update({
            "sha256": sha,
            "original_width": int(_sips_prop(f, "pixelWidth") or 0),
            "original_height": int(_sips_prop(f, "pixelHeight") or 0),
            "captured": _sips_prop(f, "creation"),
            "camera": _sips_prop(f, "model"),
            "original_has_gps": b"GPS" in f.read_bytes()[:300_000],
            "missing": False,
        })
        info = prepare_one(f, coll / "photos" / f"{rec['id']}.jpg")
        rec["prepared"] = {"width": info["width"], "height": info["height"], "bytes": info["bytes"]}
        prepare_one(f, coll / "thumbs" / f"{rec['id']}.jpg", max_px=360)
    for rec in cat["photos"]:
        if rec["original"] not in present:
            rec["missing"] = True
    write_json(cat_path, cat)
    return cat


def seed_csvs(coll: Path, cat: dict) -> None:
    items_path, sales_path = coll / "items.csv", coll / "sales.csv"
    notes_path = coll / "provisional_notes.json"
    notes = read_json(notes_path) if notes_path.exists() else {}
    if not items_path.exists():
        with open(items_path, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=ITEM_FIELDS)
            w.writeheader()
            for i, p in enumerate(cat["photos"], 1):
                n = notes.get(p["original"], {})
                w.writerow({"item_id": f"inv-{i:02d}", "status": n.get("status", "candidate"),
                            "repeat": n.get("repeat", 1), "primary_photo": p["id"],
                            "supporting_photos": "", "provisional_description": n.get("description", ""),
                            "category": "", "review_notes": ""})
        print(f"seeded {items_path.name}")
    if not sales_path.exists():
        with open(sales_path, "w", newline="", encoding="utf-8") as fh:
            csv.DictWriter(fh, fieldnames=SALE_FIELDS).writeheader()
        print(f"seeded {sales_path.name}")


def read_csv(path: Path) -> list:
    if not path.exists():
        return []
    with open(path, newline="", encoding="utf-8-sig") as fh:
        return [{k.strip(): (v or "").strip() for k, v in row.items() if k} for row in csv.DictReader(fh)]


CSS = """
:root{--bg:#f7f6f3;--card:#fff;--text:#1d1d1f;--muted:#6b6b70;--line:#e3e1dc;--sel:#1f6f43;--selbg:#e6f3ea;--alt:#7a5a00;--altbg:#fbf3dc}
@media (prefers-color-scheme:dark){:root{--bg:#161617;--card:#222224;--text:#f2f2f2;--muted:#a1a1a6;--line:#38383b;--sel:#7ad19a;--selbg:#1d3326;--alt:#e8c46a;--altbg:#3a3220}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 -apple-system,system-ui,sans-serif}
main{max-width:1200px;margin:0 auto;padding:24px 16px 64px}h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:32px 0 10px}
.sub{color:var(--muted);margin:0 0 18px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden;display:flex;flex-direction:column}
.card img{width:100%;height:200px;object-fit:contain;background:#00000010}.body{padding:10px 12px 12px;display:flex;flex-direction:column;gap:4px}
.ids{display:flex;justify-content:space-between;font-weight:600}.fn{color:var(--muted);font:11px ui-monospace,Menlo,monospace;word-break:break-all}
.meta{color:var(--muted);font-size:12px}.desc{margin-top:4px}.badge{display:inline-block;padding:1px 8px;border-radius:99px;font-size:12px;font-weight:600}
.selected{color:var(--sel);background:var(--selbg)}.candidate{color:var(--muted);background:#8881}.alternate{color:var(--alt);background:var(--altbg)}
.flag{color:var(--alt);font-size:12px}table{border-collapse:collapse;width:100%;background:var(--card);border:1px solid var(--line);border-radius:8px}
th,td{text-align:left;padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}th{font-size:12px;color:var(--muted);font-weight:600}
.wrap{overflow-x:auto}td:nth-child(-n+4){white-space:nowrap}
"""


def render_sheet(coll: Path, cat: dict) -> Path:
    items = read_csv(coll / "items.csv")
    sales = read_csv(coll / "sales.csv")
    notes_path = coll / "provisional_notes.json"
    notes = read_json(notes_path) if notes_path.exists() else {}
    item_by_photo = {}
    for it in items:
        for ph in [it.get("primary_photo", "")] + [x.strip() for x in it.get("supporting_photos", "").split(";")]:
            if ph:
                item_by_photo[ph] = it
    sold_items = {s["item_id"] for s in sales if s.get("type", "").lower() == "sold" and s.get("price")}
    cards = []
    for p in cat["photos"]:
        thumb = coll / "thumbs" / f"{p['id']}.jpg"
        src = "data:image/jpeg;base64," + base64.b64encode(thumb.read_bytes()).decode() if thumb.exists() else ""
        it = item_by_photo.get(p["id"], {})
        n = notes.get(p["original"], {})
        status = it.get("status") or "candidate"
        role = "primary" if it.get("primary_photo") == p["id"] else ("supporting" if it else "")
        flags = []
        if p.get("missing"):
            flags.append("original file missing")
        if p.get("original_has_gps"):
            flags.append("original has GPS (stripped in prepared copy)")
        if max(p.get("original_width", 0), p.get("original_height", 0)) < 800:
            flags.append("low resolution")
        if n.get("related"):
            flags.append("related: " + n["related"])
        if it.get("item_id") in sold_items:
            flags.append("has sold price")
        cards.append(f"""
<div class="card"><img src="{src}" alt="{html.escape(p['id'])}">
<div class="body"><div class="ids"><span>{html.escape(p['id'])}</span><span>{html.escape(it.get('item_id', ''))} {html.escape(role)}</span></div>
<div><span class="badge {html.escape(status)}">{html.escape(status)}</span> {html.escape(n.get('category_guess', ''))}</div>
<div class="fn">{html.escape(p['original'])}</div>
<div class="meta">{html.escape(p.get('captured', ''))} · {html.escape(p.get('camera', ''))} · {p.get('original_width')}×{p.get('original_height')}</div>
<div class="desc">{html.escape(it.get('identity') or it.get('provisional_description') or n.get('description', ''))}</div>
{''.join(f'<div class="flag">• {html.escape(f)}</div>' for f in flags)}
</div></div>""")
    sel_rows = []
    for it in items:
        if it.get("status") in ("selected", "alternate"):
            n = next((notes.get(p["original"], {}) for p in cat["photos"] if p["id"] == it.get("primary_photo")), {})
            sel_rows.append(
                f"<tr><td>{html.escape(it['item_id'])}</td><td>{html.escape(it.get('primary_photo', ''))}</td>"
                f"<td><span class='badge {html.escape(it['status'])}'>{html.escape(it['status'])}</span></td>"
                f"<td>{html.escape(it.get('repeat', '1'))}</td>"
                f"<td>{html.escape(n.get('category_guess', ''))}</td>"
                f"<td>{html.escape(it.get('provisional_description', ''))}</td>"
                f"<td>{html.escape(n.get('why', ''))}</td></tr>")
    assoc = [f"<li><b>{html.escape(k)}</b>: {html.escape(v)}</li>" for k, v in (notes.get("_associations") or {}).items()]
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LTC Eval Photos</title><style>{CSS}</style></head><body><main>
<h1>LTC evaluation photo collection</h1>
<p class="sub">{html.escape(coll.name)} · {len(cat['photos'])} photos · generated {dt.datetime.now():%Y-%m-%d %H:%M} · local file, private.
Descriptions marked provisional are Claude's visual guesses, not reference facts.</p>
<h2>Proposed initial comparison</h2>
<div class="wrap"><table><tr><th>Item</th><th>Photo</th><th>Status</th><th>Runs</th><th>Category (guess)</th><th>Provisional description</th><th>Why included</th></tr>
{''.join(sel_rows) or '<tr><td colspan=7>None marked yet.</td></tr>'}</table></div>
<h2>Possible associations to confirm</h2><ul>{''.join(assoc) or '<li>None proposed.</li>'}</ul>
<h2>All photos</h2><div class="grid">{''.join(cards)}</div>
</main></body></html>"""
    out = coll / "contact_sheet.html"
    out.write_text(page, encoding="utf-8")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("collection", type=Path)
    ap.add_argument("--sheet", action="store_true", help="only re-render the contact sheet")
    args = ap.parse_args()
    coll = args.collection.resolve()
    if args.sheet:
        cat = read_json(coll / "catalog.json")
    else:
        cat = scan(coll)
        seed_csvs(coll, cat)
        print(f"cataloged {len(cat['photos'])} photos")
    print(f"contact sheet: {render_sheet(coll, cat)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
