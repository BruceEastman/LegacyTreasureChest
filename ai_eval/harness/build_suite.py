"""Build suite.json + references.json from the editable CSVs (no JSON editing needed).

  python3 -I harness/build_suite.py private/inventory_v1 [--variants photo,photo_text]

Inputs you edit (Numbers, Excel or any text editor; save as CSV, UTF-8):
  items.csv   one row per item
    item_id              neutral id, e.g. inv-07 (keep stable)
    status               selected | alternate | candidate | excluded
                         only 'selected' items run; the others stay in the collection
    repeat               how many times to run the item per model (variance check)
    primary_photo        ph-id from the contact sheet
    supporting_photos    ph-ids separated by ';' (recorded now, used by future multi-photo tests)
    identity             what the item really is, in your words (reference fact)
    category             expected LTC category; acceptable_categories adds others, ';'-separated
    must_mention         facts a good answer should state, ';'-separated (e.g. TAG Heuer; Carrera)
    must_not_claim       things that would be invented or wrong, ';'-separated
    hint_title, hint_description   what you would type in LTC (used by the photo_text variant)
    review_notes         anything a reviewer should know
  sales.csv   one row per price observation
    item_id, type (sold | asking | appraisal | offer | estimate), price, quantity, date, source, notes
    quantity = number of units the price covers (default 1). A bundled sale of 3 for $900 is
    price 900, quantity 3: it is kept as a bundle, never rewritten as a per-unit price.
    Only 'sold' rows count as realized outcomes. Several rows per item are fine.

Outputs (generated; do not edit):
  suite.json, references.json  in the same folder

Variants:
  photo       primary photo, no text hints (pure identification) -> case id = item_id
  photo_text  primary photo + hint_title/hint_description         -> case id = item_id + "-pt"
              (only for items that have a hint)
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from catalog import read_csv  # noqa: E402
from common import read_json, write_json  # noqa: E402

CANONICAL = ["Uncategorized", "Art", "Furniture", "Jewelry", "Collectibles", "Documents", "Electronics",
             "Appliance", "Rug", "China & Crystal", "Luxury Personal Items", "Clothing", "Tools", "Luggage",
             "Decor", "Other"]
SALE_TYPES = {"sold", "asking", "appraisal", "offer", "estimate"}
STATUSES = {"selected", "alternate", "candidate", "excluded"}


def _list(s: str) -> list:
    return [x.strip() for x in (s or "").split(";") if x.strip()]


def _price(s: str):
    s = re.sub(r"[,$\s]", "", s or "")
    if not s:
        return None
    return float(s)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("collection", type=Path)
    ap.add_argument("--variants", default="photo")
    ap.add_argument("--suite-name", default=None)
    args = ap.parse_args()
    coll = args.collection.resolve()
    variants = set(args.variants.split(","))

    cat = read_json(coll / "catalog.json")
    photos = {p["id"]: p for p in cat["photos"]}
    items = read_csv(coll / "items.csv")
    sales = read_csv(coll / "sales.csv")
    errors, warnings = [], []

    seen = set()
    for it in items:
        iid = it.get("item_id", "")
        if not iid:
            errors.append("a row in items.csv has no item_id")
            continue
        if iid in seen:
            errors.append(f"duplicate item_id {iid}")
        seen.add(iid)
        if it.get("status", "candidate") not in STATUSES:
            errors.append(f"{iid}: status must be one of {sorted(STATUSES)}")
        for ph in [it.get("primary_photo", "")] + _list(it.get("supporting_photos", "")):
            if ph and ph not in photos:
                errors.append(f"{iid}: unknown photo id {ph}")
            elif ph and photos[ph].get("missing"):
                errors.append(f"{iid}: original for {ph} is missing")
        for c in [it.get("category", "")] + _list(it.get("acceptable_categories", "")):
            if c and c not in CANONICAL:
                warnings.append(f"{iid}: category {c!r} is not an LTC category {CANONICAL}")
    for s in sales:
        if s.get("item_id") not in seen:
            errors.append(f"sales.csv: unknown item_id {s.get('item_id')!r}")
        if (s.get("type") or "").lower() not in SALE_TYPES:
            errors.append(f"sales.csv {s.get('item_id')}: type must be one of {sorted(SALE_TYPES)}")
        try:
            _price(s.get("price", ""))
        except ValueError:
            errors.append(f"sales.csv {s.get('item_id')}: price {s.get('price')!r} is not a number")
        if (s.get("quantity") or "1").strip() and not (s.get("quantity") or "1").strip().isdigit():
            errors.append(f"sales.csv {s.get('item_id')}: quantity {s.get('quantity')!r} must be a whole number")
    if errors:
        print("Fix these in the CSVs, then re-run:")
        for e in errors:
            print("  -", e)
        return 2

    cases, refs = [], {}
    for it in items:
        iid = it["item_id"]
        status = it.get("status") or "candidate"
        if status == "excluded" or not it.get("primary_photo"):
            continue
        accept = ([it["category"]] if it.get("category") else []) + _list(it.get("acceptable_categories", ""))
        ref = {
            "identity": it.get("identity", ""),
            "acceptableCategories": accept,
            "mustMention": _list(it.get("must_mention", "")),
            "mustNotClaim": _list(it.get("must_not_claim", "")),
            "saleEvidence": [{"type": s["type"].lower(), "price": _price(s.get("price")),
                              "quantity": int(s.get("quantity") or 1), "date": s.get("date", ""),
                              "source": s.get("source", ""), "notes": s.get("notes", "")}
                             for s in sales if s.get("item_id") == iid and _price(s.get("price")) is not None],
            "reviewNotes": it.get("review_notes", ""),
            "supportingPhotos": _list(it.get("supporting_photos", "")),
            "facts": {k: it[k] for k in ("maker", "model", "era", "materials", "condition", "set_size")
                      if it.get(k)},
            "outcome": it.get("outcome", ""),
        }
        base = {"type": "photo", "photo": f"photos/{it['primary_photo']}.jpg",
                "repeat": int(it.get("repeat") or 1), "enabled": status == "selected",
                "item_id": iid, "status": status}
        if "photo" in variants:
            cases.append({"id": iid, **base, "hints": None, "variant": "photo"})
            refs[iid] = ref
        if "photo_text" in variants and (it.get("hint_title") or it.get("hint_description")):
            cases.append({"id": f"{iid}-pt", **base, "variant": "photo_text",
                          "hints": {"userWrittenTitle": it.get("hint_title") or None,
                                    "userWrittenDescription": it.get("hint_description") or None,
                                    "knownCategory": None}})
            refs[f"{iid}-pt"] = ref

    name = args.suite_name or coll.name
    write_json(coll / "suite.json", {
        "suite": name, "version": "generated",
        "description": "GENERATED by harness/build_suite.py from items.csv and sales.csv. Do not edit; edit the CSVs.",
        "references": "references.json", "cases": cases})
    write_json(coll / "references.json", {
        "description": "GENERATED from items.csv and sales.csv. Reference facts are kept separate from model answers.",
        "cases": refs})
    on = [c for c in cases if c["enabled"]]
    print(f"suite.json: {len(cases)} cases ({len(on)} enabled, {sum(c['repeat'] for c in on)} runs per model)")
    print(f"references: {sum(1 for r in refs.values() if r['identity'])} with identity, "
          f"{sum(1 for r in refs.values() if any(e['type'] == 'sold' for e in r['saleEvidence']))} with a sold price")
    for w in warnings:
        print("  warning:", w)
    return 0


if __name__ == "__main__":
    sys.exit(main())
