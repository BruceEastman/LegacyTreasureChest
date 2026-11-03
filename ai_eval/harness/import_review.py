"""Apply a saved review (from review_form.html) to items.csv and sales.csv, then rebuild the suite.

  python3 -I harness/import_review.py private/inventory_v1 [path/to/review_inventory_v1.json] [--dry-run]

If no path is given, the newest ~/Downloads/review_<collection>*.json is used.
Both CSVs are backed up (backups/<timestamp>/) before anything is written, and every change is
printed. Blank answers never erase existing values.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import shutil
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from catalog import ITEM_FIELDS, SALE_FIELDS, read_csv  # noqa: E402
from common import read_json  # noqa: E402

ITEM_KEYS = ["identity", "category", "must_mention", "must_not_claim", "hint_title", "hint_description",
             "review_notes", "repeat", "status", "maker", "model", "era", "materials", "condition", "set_size",
             "outcome", "id_check"]


def _write(path: Path, fields, rows) -> None:
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fields})


def _upsert_sale(sales, iid, typ, price, qty, date, source, notes, changes):
    if not price:
        return
    row = {"item_id": iid, "type": typ, "price": price.replace("$", "").replace(",", "").strip(),
           "quantity": qty or "1", "date": date, "source": source, "notes": notes}
    existing = [s for s in sales if s["item_id"] == iid and s.get("type") == typ]
    if existing:
        s = existing[0]
        diff = {k: (s.get(k, ""), v) for k, v in row.items() if v and s.get(k, "") != v}
        if diff:
            s.update({k: v for k, v in row.items() if v})
            changes.append(f"{iid}: updated {typ} sale {diff}")
    else:
        sales.append(row)
        changes.append(f"{iid}: added {typ} ${row['price']} x{row['quantity']} ({source})")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("collection", type=Path)
    ap.add_argument("review", nargs="?", type=Path)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    coll = args.collection.resolve()
    path = args.review
    if path is None:
        found = sorted(Path.home().joinpath("Downloads").glob(f"review_{coll.name}*.json"),
                       key=lambda p: p.stat().st_mtime)
        if not found:
            print(f"No ~/Downloads/review_{coll.name}*.json found. Pass the path explicitly.")
            return 2
        path = found[-1]
    review = read_json(path)
    print(f"review file: {path} (saved {review.get('saved')})")

    items = read_csv(coll / "items.csv")
    sales = read_csv(coll / "sales.csv")
    fields = list(dict.fromkeys(ITEM_FIELDS + list(items[0].keys() if items else []) + ITEM_KEYS))
    by_id = {it["item_id"]: it for it in items}
    changes = []
    for iid, ans in review.get("items", {}).items():
        it = by_id.get(iid)
        if it is None:
            changes.append(f"{iid}: not in items.csv; skipped")
            continue
        for k in ITEM_KEYS:
            v = (ans.get(k) or "").strip()
            if v and it.get(k, "") != v:
                changes.append(f"{iid}: {k} {it.get(k, '')!r} -> {v!r}")
                it[k] = v
        _upsert_sale(sales, iid, "sold", ans.get("sold_price", ""), ans.get("sold_quantity", ""),
                     ans.get("sold_date", ""), ans.get("sold_source", ""), ans.get("sold_notes", ""), changes)
        if ans.get("other_type"):
            _upsert_sale(sales, iid, ans["other_type"], ans.get("other_price", ""), ans.get("other_quantity", ""),
                         ans.get("other_date", ""), ans.get("other_source", ""), "", changes)
    for k, v in (review.get("associations") or {}).items():
        if v:
            changes.append(f"association note [{k}]: {v}")
    if review.get("general_notes"):
        changes.append(f"general notes: {review['general_notes']}")

    print("\n".join(changes) if changes else "No changes.")
    if args.dry_run or not changes:
        return 0
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    bdir = coll / "backups" / stamp
    bdir.mkdir(parents=True, exist_ok=True)
    for name in ("items.csv", "sales.csv"):
        if (coll / name).exists():
            shutil.copy2(coll / name, bdir / name)
    shutil.copy2(path, bdir / path.name)
    _write(coll / "items.csv", fields, items)
    _write(coll / "sales.csv", SALE_FIELDS, sales)
    print(f"\nbacked up previous CSVs to {bdir}")
    return subprocess.call([sys.executable, "-I", str(Path(__file__).with_name("build_suite.py")), str(coll)])


if __name__ == "__main__":
    sys.exit(main())
