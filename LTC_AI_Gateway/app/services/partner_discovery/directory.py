# app/services/partner_discovery/directory.py
"""
Curated national specialty providers (app/config/specialty_directory.v1.json).

The directory is selective and maintained by hand: each entry records what the
provider itself publishes (service types, intake, reach) and when it was last
checked. It serves two callers:
- intent searches with national scope (match_directory)
- the legacy luxury clothing results, whose output must stay byte-identical
  (legacy_luxury_hub_candidates)
"""
from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List

_DIRECTORY_PATH = Path(__file__).resolve().parents[2] / "config" / "specialty_directory.v1.json"

_VALID_STRATEGIES = {"maximizePrice", "consignment", "quickSale", "donation"}
_VALID_SERVICE_TYPES = {"consignment", "buys_outright", "auction", "marketplace", "donations"}


class DirectoryError(Exception):
    """The directory file is malformed."""


def _validate(entry: Dict[str, Any]) -> None:
    for key in ("id", "name", "website", "serviceTypes", "strategies", "matchTerms"):
        if not entry.get(key):
            raise DirectoryError(f"directory entry missing {key}: {entry.get('id')}")
    if not str(entry["website"]).startswith("https://"):
        raise DirectoryError(f"directory website must be https: {entry['id']}")
    if set(entry["strategies"]) - _VALID_STRATEGIES:
        raise DirectoryError(f"unknown strategy in {entry['id']}")
    if set(entry["serviceTypes"]) - _VALID_SERVICE_TYPES:
        raise DirectoryError(f"unknown service type in {entry['id']}")
    if entry.get("intentEligible") and not entry.get("verifiedAt"):
        raise DirectoryError(f"intent-eligible entry needs verifiedAt: {entry['id']}")


@lru_cache(maxsize=1)
def load_directory() -> List[Dict[str, Any]]:
    data = json.loads(_DIRECTORY_PATH.read_text(encoding="utf-8"))
    providers = data.get("providers") or []
    ids = set()
    for entry in providers:
        _validate(entry)
        if entry["id"] in ids:
            raise DirectoryError(f"duplicate directory id {entry['id']}")
        ids.add(entry["id"])
    return providers


def _words(text: str) -> List[str]:
    return re.findall(r"[a-z0-9]+", (text or "").lower())


def _contains_term(haystack_words: List[str], term: str) -> bool:
    """Whole-word (or whole multi-word phrase) match, tolerant of a trailing plural 's'."""
    tw = _words(term)
    if not tw:
        return False
    n = len(tw)
    normalized = [w[:-1] if len(w) > 3 and w.endswith("s") else w for w in haystack_words]
    target = [w[:-1] if len(w) > 3 and w.endswith("s") else w for w in tw]
    return any(normalized[i:i + n] == target for i in range(len(normalized) - n + 1))


def match_directory(*, strategy: str, phrase: str, detail_terms: List[str], limit: int = 5) -> List[Dict[str, Any]]:
    """
    Verified entries that serve the chosen strategy and whose specialty terms
    appear in the homeowner's phrase or detail terms. Ordered by number of
    matched terms, then directory order. Returns (entry, matched_terms) pairs.
    """
    words = _words(" ".join([phrase, *detail_terms]))
    matches = []
    for order, entry in enumerate(load_directory()):
        if not entry.get("intentEligible") or strategy not in entry["strategies"]:
            continue
        matched = [t for t in entry["matchTerms"] if _contains_term(words, t)]
        if matched:
            matches.append((len(matched), -order, entry, matched))
    matches.sort(key=lambda m: (m[0], m[1]), reverse=True)
    return [{"entry": m[2], "matchedTerms": m[3]} for m in matches[:limit]]


def legacy_luxury_hub_candidates(hints_txt: str) -> List[Dict[str, Any]]:
    """The legacy luxury clothing channels, in their original shape and wording."""
    legacy = sorted(
        (e for e in load_directory() if e.get("legacyLuxuryHub")),
        key=lambda e: e["legacyLuxuryHub"]["order"],
    )
    return [
        {
            "partnerId": e["id"],
            "name": e["name"],
            "partnerType": "luxury_hub_mailin",
            "contact": {
                "phone": None,
                "website": e["website"],
                "email": None,
                "address": None,
                "city": None,
                "region": None,
            },
            "distanceMiles": None,
            "rating": None,
            "userRatingsTotal": None,
            "sources": {
                "website_snippet": e["legacyLuxuryHub"]["website_snippet"],
                "place_details": e["legacyLuxuryHub"]["place_details"] + hints_txt,
                "reviews_snippet": "",
            },
        }
        for e in legacy
    ]
