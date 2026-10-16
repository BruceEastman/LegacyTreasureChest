# app/services/partner_discovery/intent.py
"""
B1 specialty discovery from a homeowner-reviewed Search Intent.

Pure functions (no I/O) so they can be tested directly:
- validate_intent: server-side checks that mirror the app's (phrase limits,
  no emails/URLs/long numbers, known strategy and scope, US only)
- build_queries: at most two Google Places text queries for the chosen
  strategy, phrase, and place, never an unrestricted nationwide search
- service_evidence / relevance / area_match: what Google's own name and type
  text supports, kept separate from relevance, never acceptance
- rank_score: provider order + relevance + distance, with no hard drops for
  specialists that lack generic resale words or a distance
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

STRATEGIES = ("maximizePrice", "consignment", "quickSale", "donation")
SCOPES = ("local", "regional", "national")
VALUE_BANDS = ("LOW", "MED", "HIGH")

MAX_PHRASE_CHARS = 60
MAX_PHRASE_WORDS = 8
MAX_DETAIL_TERMS = 4
MAX_DETAIL_TERM_CHARS = 30
MAX_PLACES_QUERIES = 2

_EMAIL_RE = re.compile(r"[^\s@]+@[^\s@]+\.[^\s@]+")
_URL_RE = re.compile(r"(https?://|www\.)|\b[a-z0-9-]+\.(com|net|org|io|co|us|info|biz)\b", re.IGNORECASE)
_NUMBER_RUN_RE = re.compile(r"\d[\d\s().-]*\d")  # digits with phone/serial separators
_ALLOWED_RE = re.compile(r"^[\w\s&'’.,/()+-]+$", re.UNICODE)

US_STATES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
    "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia",
    "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois",
    "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
    "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
    "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
    "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
    "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon",
    "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
    "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia",
    "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
}
_STATE_BY_NAME = {name.lower(): code for code, name in US_STATES.items()}

# Words that say little about what the item is; ignored for relevance.
_GENERIC_WORDS = {
    "used", "vintage", "old", "antique", "the", "and", "of", "for", "a", "an", "in", "with", "set",
    "item", "items", "goods", "stuff", "misc", "other", "lot", "collection", "piece", "pieces",
    "household", "home", "general",
}

# Never relevant to a homeowner's specialty search (vehicle auctions, repair, cleaning).
_EXCLUDE_KEYWORDS = (
    "auto auction", "car auction", "car dealer", "vehicle", "towing", "salvage", "impound",
    "insurance auto", "carpet cleaning", "dry clean", "repair shop",
)


class IntentValidationError(ValueError):
    """A Search Intent that cannot be searched. Messages never echo the phrase."""


@dataclass(frozen=True)
class NormalizedIntent:
    strategy: str
    phrase: str
    detail_terms: Tuple[str, ...]
    geo_scope: str
    value_band: Optional[str]
    city: str = ""
    region_code: str = ""  # two-letter US state code, when known
    region_name: str = ""  # full state name for query text


def _clean_text(value: Any, *, max_chars: int, max_words: Optional[int], label: str) -> str:
    if not isinstance(value, str):
        raise IntentValidationError(f"{label} must be text.")
    s = " ".join(value.split())
    if not s:
        raise IntentValidationError(f"{label} is empty.")
    if len(s) > max_chars:
        raise IntentValidationError(f"{label} is too long.")
    if max_words is not None and len(s.split()) > max_words:
        raise IntentValidationError(f"{label} has too many words.")
    if _EMAIL_RE.search(s) or _URL_RE.search(s):
        raise IntentValidationError(f"{label} must not contain an email address or web address.")
    if any(sum(ch.isdigit() for ch in m.group()) >= 7 for m in _NUMBER_RUN_RE.finditer(s)):
        raise IntentValidationError(f"{label} must not contain long numbers.")
    if not _ALLOWED_RE.match(s):
        raise IntentValidationError(f"{label} contains unsupported characters.")
    return s


def resolve_state(region: str) -> Tuple[str, str]:
    """('ID', 'Idaho') from 'ID', 'id', or 'Idaho'; ('', '') when not a US state."""
    r = " ".join((region or "").split())
    if r.upper() in US_STATES:
        return r.upper(), US_STATES[r.upper()]
    code = _STATE_BY_NAME.get(r.lower())
    return (code, US_STATES[code]) if code else ("", "")


def validate_intent(intent: Any, *, city: str, region: str, country_code: str) -> NormalizedIntent:
    strategy = getattr(intent, "strategy", None)
    if strategy not in STRATEGIES:
        raise IntentValidationError("Unknown strategy.")
    geo_scope = getattr(intent, "geoScope", None)
    if geo_scope not in SCOPES:
        raise IntentValidationError("Unknown search scope.")

    phrase = _clean_text(getattr(intent, "phrase", None), max_chars=MAX_PHRASE_CHARS,
                         max_words=MAX_PHRASE_WORDS, label="Search phrase")
    if len(phrase) < 2:
        raise IntentValidationError("Search phrase is too short.")

    raw_terms = getattr(intent, "detailTerms", None) or []
    if len(raw_terms) > MAX_DETAIL_TERMS:
        raise IntentValidationError("Too many detail terms.")
    terms: List[str] = []
    for t in raw_terms:
        term = _clean_text(t, max_chars=MAX_DETAIL_TERM_CHARS, max_words=4, label="Detail term")
        if term.lower() not in {x.lower() for x in terms}:
            terms.append(term)

    value_band = getattr(intent, "valueBand", None)
    value_band = value_band if value_band in VALUE_BANDS else None

    if (country_code or "US").strip().upper() != "US":
        raise IntentValidationError("Specialty search is available in the United States only.")

    city_clean = " ".join((city or "").split())
    code, name = resolve_state(region)
    if geo_scope == "local":
        if not city_clean or not code:
            raise IntentValidationError("Local search needs a city and a US state.")
        city_clean = _clean_text(city_clean, max_chars=60, max_words=6, label="City")
    elif geo_scope == "regional":
        if not code:
            raise IntentValidationError("Regional search needs a US state.")
        city_clean = ""
    else:
        city_clean, code, name = "", "", ""

    return NormalizedIntent(strategy, phrase, tuple(terms), geo_scope, value_band, city_clean, code, name)


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class PlannedQuery:
    text: str
    partner_type: str  # what this query looks for (consignment, specialist_dealer, ...)


def _place_text(intent: NormalizedIntent) -> str:
    if intent.geo_scope == "local":
        return f"{intent.city}, {intent.region_name}"
    return intent.region_name


def _with_used(phrase: str) -> str:
    first = phrase.split()[0].lower()
    return phrase if first in {"used", "vintage", "antique", "pre-owned", "secondhand"} else f"used {phrase}"


def build_queries(intent: NormalizedIntent) -> List[PlannedQuery]:
    """
    At most two text queries naming the place explicitly, so Google never falls
    back to the server's own location. National scope makes no Places queries.
    The phrase leads; brand/model detail terms are left to ranking so results
    are not narrowed to businesses that name a brand.
    """
    if intent.geo_scope == "national":
        return []
    p, where = intent.phrase, _place_text(intent)
    by_strategy = {
        "consignment": [
            PlannedQuery(f"{p} consignment in {where}", "consignment"),
            PlannedQuery(f"{p} specialist dealer in {where}", "specialist_dealer"),
        ],
        "maximizePrice": [
            PlannedQuery(f"{p} specialist dealer in {where}", "specialist_dealer"),
            PlannedQuery(f"{p} auction house in {where}", "auction"),
        ],
        "quickSale": [
            PlannedQuery(f"{_with_used(p)} buyer in {where}", "buyer"),
            PlannedQuery(f"{p} dealer in {where}", "specialist_dealer"),
        ],
        "donation": [
            PlannedQuery(f"{p} donation center in {where}", "donation"),
            PlannedQuery(f"charity that accepts {p} in {where}", "donation"),
        ],
    }
    return by_strategy[intent.strategy][:MAX_PLACES_QUERIES]


# ---------------------------------------------------------------------------
# Evidence, relevance, area
# ---------------------------------------------------------------------------

def listing_text(candidate: Dict[str, Any]) -> str:
    """The business's own Google name and type text (never the query)."""
    return (candidate.get("sources", {}) or {}).get("website_snippet", "").lower()


def is_excluded(candidate: Dict[str, Any]) -> bool:
    text = listing_text(candidate)
    return any(k in text for k in _EXCLUDE_KEYWORDS)


def service_evidence(candidate: Dict[str, Any]) -> Dict[str, str]:
    """
    Services the listing itself mentions. A mention is evidence of what the
    business says it does, not that it will accept a particular item.
    """
    t = listing_text(candidate)

    def mentioned(*keys: str) -> str:
        return "mentioned" if any(k in t for k in keys) else "not_mentioned"

    return {
        "consignment": mentioned("consign"),
        "buysOutright": mentioned("we buy", "buyer", "buyers", "pawn", "cash for", "buy sell", "buy & sell"),
        "auction": mentioned("auction"),
        "donations": mentioned("donat", "thrift", "charity", "charitable"),
    }


def _stem(word: str) -> str:
    return word[:-1] if len(word) > 3 and word.endswith("s") else word


def relevance(candidate: Dict[str, Any], intent: NormalizedIntent) -> Dict[str, Any]:
    """'specialist' when the listing names what the item is; 'general' otherwise."""
    listing = {_stem(w) for w in re.findall(r"[a-z0-9]+", listing_text(candidate))}
    phrase_words = [w for w in re.findall(r"[a-z0-9]+", intent.phrase.lower()) if w not in _GENERIC_WORDS]
    matched = sorted({w for w in phrase_words if _stem(w) in listing})
    for term in intent.detail_terms:
        words = [_stem(w) for w in re.findall(r"[a-z0-9]+", term.lower())]
        if words and all(w in listing for w in words):
            matched.append(term)
    return {"level": "specialist" if matched else "general", "matchedTerms": matched}


def area_match(candidate: Dict[str, Any], intent: NormalizedIntent, radius_miles: int) -> str:
    """Whether a result lies in the requested area, as far as real data shows."""
    address = ((candidate.get("contact") or {}).get("address") or "")
    if intent.geo_scope == "regional":
        if not address:
            return "unknown"
        in_state = (re.search(rf",\s*{intent.region_code}\b", address) is not None
                    or intent.region_name.lower() in address.lower())
        return "in_area" if in_state else "outside_area"
    distance = candidate.get("distanceMiles")
    if distance is not None:
        return "in_area" if float(distance) <= radius_miles else "outside_area"
    if address and intent.city.lower() in address.lower():
        return "in_area"
    return "unknown"


def rank_score(*, provider_rank: Optional[int], rel: Dict[str, Any], distance: Optional[float],
               radius_miles: int, area: str) -> float:
    """
    Google's own order for the query, plus whether the listing names the item,
    plus nearness. Unknown distance is neutral rather than disqualifying.
    """
    order = 1.0 - min(int(provider_rank), 19) / 19.0 if provider_rank is not None else 0.5
    rel_score = 1.0 if rel["level"] == "specialist" else 0.0
    if distance is None or radius_miles <= 0:
        near = 0.5
    else:
        near = max(0.0, 1.0 - min(float(distance) / float(radius_miles), 2.0) / 2.0)
    score = 0.45 * order + 0.4 * rel_score + 0.15 * near
    if area == "outside_area":
        score -= 0.3
    return round(max(0.0, min(1.0, score)), 3)


_QUESTIONS = {
    "consignment": [
        "Do you take items like this on consignment right now?",
        "What commission and consignment period apply?",
        "How is pricing decided, and when am I paid after a sale?",
    ],
    "maximizePrice": [
        "Do you buy, consign, or auction items like this?",
        "How do you arrive at an offer or estimate?",
        "What fees apply, and when would I be paid?",
    ],
    "quickSale": [
        "Do you buy items like this outright?",
        "Can you give an offer from photos before I bring it in?",
        "How and when do you pay?",
    ],
    "donation": [
        "Do you accept this kind of item right now?",
        "Do you offer pickup, or what are drop-off hours?",
        "Do you provide a donation receipt?",
    ],
}


def questions_for(strategy: str) -> List[str]:
    return list(_QUESTIONS[strategy])


def why_text(rel: Dict[str, Any], area: str, intent: NormalizedIntent) -> str:
    parts = []
    if rel["level"] == "specialist":
        parts.append("Listing mentions " + ", ".join(rel["matchedTerms"][:3]))
    else:
        parts.append("Appeared in Google Maps results for this search")
    if area == "outside_area":
        parts.append("outside the requested area" if intent.geo_scope == "local"
                     else f"outside {intent.region_name}")
    return "; ".join(parts) + ". Confirm they accept your item."
