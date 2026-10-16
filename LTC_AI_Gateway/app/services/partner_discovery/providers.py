# app/services/partner_discovery/providers.py
from __future__ import annotations

import logging
import math
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Protocol

import httpx

logger = logging.getLogger(__name__)

PartnerCandidate = Dict[str, Any]

# Places API (New) rejects a locationBias circle larger than 50 km.
_MAX_BIAS_RADIUS_METERS = 50_000.0


class PartnerDiscoveryUnavailable(Exception):
    """
    Raised when the configured provider cannot return results right now
    (upstream error, timeout, quota). The route turns this into an honest
    "unavailable" response; it never falls back to fabricated businesses.
    """

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


@dataclass(frozen=True)
class PartnerDiscoveryQuery:
    query: str
    city: str
    region: str
    radius_miles: int
    partner_type: str
    center_lat: Optional[float] = None
    center_lng: Optional[float] = None
    language_code: str = "en"
    region_code: str = "US"
    # False for regional searches: the center is still used for distances, but
    # the query text alone names the area (a 50 km bias would skew a state).
    use_location_bias: bool = True


class PartnerDiscoveryProvider(Protocol):
    name: str
    is_stub: bool

    def search(self, q: PartnerDiscoveryQuery) -> List[PartnerCandidate]:
        ...


def _miles_to_meters(mi: int) -> float:
    return float(max(0, mi)) * 1609.344


def _haversine_miles(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 3958.7613
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)

    a = math.sin(dphi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * (math.sin(dlambda / 2.0) ** 2)
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))
    return r * c


def _safe_float(x: Any) -> Optional[float]:
    try:
        if x is None:
            return None
        return float(x)
    except Exception:
        return None


def _safe_int(x: Any) -> Optional[int]:
    try:
        if x is None:
            return None
        if isinstance(x, bool):
            return None
        return int(x)
    except Exception:
        return None


class StubPartnerDiscoveryProvider:
    """
    Thin wrapper so the stub stays available for local development and tests.
    The factory refuses to build it on Cloud Run.
    """

    name = "stub"
    is_stub = True

    def __init__(self, stub_fn):
        self._stub_fn = stub_fn

    def search(self, q: PartnerDiscoveryQuery) -> List[PartnerCandidate]:
        return self._stub_fn(
            query=q.query,
            city=q.city,
            region=q.region,
            radius_miles=q.radius_miles,
            partner_type=q.partner_type,
        )


class GooglePlacesNewProvider:
    """
    Google Places API (New) provider: one Text Search call per query.

    The Text Search field mask already returns everything the app shows, so
    there are no per-result Place Details calls.
    """

    name = "google"
    is_stub = False

    SEARCH_TEXT_URL = "https://places.googleapis.com/v1/places:searchText"

    # Only the fields the app uses. Rating, phone, and website are the
    # reason this is billed as Text Search Enterprise.
    FIELD_MASK = ",".join(
        [
            "places.id",
            "places.displayName",
            "places.formattedAddress",
            "places.location",
            "places.rating",
            "places.userRatingCount",
            "places.googleMapsUri",
            "places.websiteUri",
            "places.nationalPhoneNumber",
            "places.businessStatus",
            "places.primaryTypeDisplayName",
            "places.types",
        ]
    )

    def __init__(
        self,
        api_key: str,
        timeout_s: float = 8.0,
        transport: Optional[httpx.BaseTransport] = None,
        max_attempts: int = 2,
    ):
        if not api_key:
            raise ValueError("GooglePlacesNewProvider requires a non-empty API key.")
        self._api_key = api_key
        self._timeout = timeout_s
        self._transport = transport
        self._max_attempts = max(1, max_attempts)

    def search(self, q: PartnerDiscoveryQuery) -> List[PartnerCandidate]:
        places = self._search_text(q)

        out: List[PartnerCandidate] = []
        for rank, p in enumerate(places):
            # Closed businesses are never useful recommendations.
            status = p.get("businessStatus")
            if status and status != "OPERATIONAL":
                continue
            out.append(self._to_candidate(p, q, rank))
        return out

    def _search_text(self, q: PartnerDiscoveryQuery) -> List[Dict[str, Any]]:
        body: Dict[str, Any] = {
            "textQuery": q.query,
            "languageCode": q.language_code,
            "regionCode": q.region_code,
            "maxResultCount": 20,
        }

        if q.use_location_bias and q.center_lat is not None and q.center_lng is not None:
            body["locationBias"] = {
                "circle": {
                    "center": {"latitude": q.center_lat, "longitude": q.center_lng},
                    "radius": min(_miles_to_meters(q.radius_miles), _MAX_BIAS_RADIUS_METERS),
                }
            }

        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self._api_key,
            "X-Goog-FieldMask": self.FIELD_MASK,
        }

        with httpx.Client(timeout=self._timeout, transport=self._transport) as client:
            for attempt in range(1, self._max_attempts + 1):
                try:
                    resp = client.post(self.SEARCH_TEXT_URL, headers=headers, json=body)
                except (httpx.TimeoutException, httpx.NetworkError) as exc:
                    logger.error(
                        "Partner discovery upstream failure provider=%s operation=%s attempt=%s/%s error=%s",
                        "google_places",
                        "searchText",
                        attempt,
                        self._max_attempts,
                        type(exc).__name__,
                    )
                    if attempt < self._max_attempts:
                        time.sleep(0.4 * attempt)
                        continue
                    raise PartnerDiscoveryUnavailable("upstream_unreachable") from exc

                if resp.status_code == 200:
                    try:
                        data = resp.json()
                    except ValueError as exc:
                        raise PartnerDiscoveryUnavailable("upstream_bad_response") from exc
                    return data.get("places", []) or []

                # Content-free diagnostics only: no request body, no query text,
                # no coordinates, no response body, no API key.
                logger.error(
                    "Partner discovery upstream error provider=%s operation=%s attempt=%s/%s status=%s",
                    "google_places",
                    "searchText",
                    attempt,
                    self._max_attempts,
                    resp.status_code,
                )

                # Retry only transient server-side failures. 4xx (including 429
                # quota exhaustion and 403 key problems) will not improve on retry.
                if 500 <= resp.status_code <= 599 and attempt < self._max_attempts:
                    time.sleep(0.4 * attempt)
                    continue

                if resp.status_code == 429:
                    raise PartnerDiscoveryUnavailable("upstream_quota")
                if resp.status_code in (401, 403):
                    raise PartnerDiscoveryUnavailable("upstream_auth")
                raise PartnerDiscoveryUnavailable(f"upstream_status_{resp.status_code}")

        raise PartnerDiscoveryUnavailable("upstream_unreachable")

    # B2: refresh a saved provider by its place ID. Only the fields the app
    # shows for a saved choice, all Place Details Pro (no phone, website,
    # rating, or reviews, which would raise the request to Enterprise).
    DETAILS_URL = "https://places.googleapis.com/v1/places/{place_id}"
    DETAILS_FIELD_MASK = "id,displayName,formattedAddress,googleMapsUri,businessStatus"

    def details(self, place_id: str) -> Optional[Dict[str, Any]]:
        """
        Place Details for one saved place ID. Returns None when Google no longer
        knows the place (404). Raises PartnerDiscoveryUnavailable otherwise.
        Nothing is cached.
        """
        headers = {"X-Goog-Api-Key": self._api_key, "X-Goog-FieldMask": self.DETAILS_FIELD_MASK}
        url = self.DETAILS_URL.format(place_id=place_id)
        with httpx.Client(timeout=self._timeout, transport=self._transport) as client:
            try:
                resp = client.get(url, headers=headers)
            except (httpx.TimeoutException, httpx.NetworkError) as exc:
                logger.error("Place details upstream failure provider=google_places error=%s", type(exc).__name__)
                raise PartnerDiscoveryUnavailable("upstream_unreachable") from exc
        if resp.status_code == 200:
            try:
                pl = resp.json()
            except ValueError as exc:
                raise PartnerDiscoveryUnavailable("upstream_bad_response") from exc
            name_obj = pl.get("displayName") or {}
            return {
                "placeId": pl.get("id") or place_id,
                "name": name_obj.get("text") if isinstance(name_obj, dict) else None,
                "address": pl.get("formattedAddress"),
                "googleMapsUri": pl.get("googleMapsUri"),
                "businessStatus": pl.get("businessStatus"),
            }
        if resp.status_code == 404:
            return None
        logger.error("Place details upstream error provider=google_places status=%s", resp.status_code)
        if resp.status_code == 429:
            raise PartnerDiscoveryUnavailable("upstream_quota")
        if resp.status_code in (401, 403):
            raise PartnerDiscoveryUnavailable("upstream_auth")
        raise PartnerDiscoveryUnavailable(f"upstream_status_{resp.status_code}")

    def _to_candidate(self, pl: Dict[str, Any], q: PartnerDiscoveryQuery, rank: int) -> PartnerCandidate:
        place_id = pl.get("id") or "unknown"
        name_obj = pl.get("displayName") or {}
        name = (name_obj.get("text") if isinstance(name_obj, dict) else None) or "(unknown)"
        type_obj = pl.get("primaryTypeDisplayName") or {}
        primary_type = type_obj.get("text") if isinstance(type_obj, dict) else None
        types = [t for t in (pl.get("types") or []) if isinstance(t, str)]
        address = pl.get("formattedAddress") or ""

        # Distance only when both ends are real coordinates. Never invented.
        dist_mi: Optional[float] = None
        loc = pl.get("location") or {}
        lat2 = _safe_float(loc.get("latitude"))
        lng2 = _safe_float(loc.get("longitude"))
        if q.center_lat is not None and q.center_lng is not None and lat2 is not None and lng2 is not None:
            dist_mi = float(round(_haversine_miles(q.center_lat, q.center_lng, lat2, lng2), 2))

        rating = _safe_float(pl.get("rating"))
        user_ratings_total = _safe_int(pl.get("userRatingCount"))

        website = pl.get("websiteUri") or pl.get("googleMapsUri")
        phone = pl.get("nationalPhoneNumber")

        # Evidence text comes only from Google's data for this place. The
        # searched-for partner type is NOT injected, so trust gates reflect
        # what the business actually is.
        type_words = " ".join(t.replace("_", " ") for t in types)
        website_snippet = f"{name}. {primary_type or ''}. {type_words}".strip()
        place_details = f"Address: {address or 'unknown'}"

        if rating is None:
            reviews_snippet = ""
        elif user_ratings_total:
            reviews_snippet = f"Google rating {rating:.1f}/5 ({user_ratings_total} ratings)"
        else:
            reviews_snippet = f"Google rating {rating:.1f}/5"

        return {
            "partnerId": f"gplaces:{place_id}",
            "name": name,
            "partnerType": q.partner_type,
            "contact": {
                "phone": phone,
                "website": website,
                "email": None,
                # The full Google address is authoritative. The searched city is
                # not copied here, since the business may be in a neighboring town.
                "address": address,
                "city": None,
                "region": None,
            },
            "distanceMiles": dist_mi,
            "rating": rating,
            "userRatingsTotal": user_ratings_total,
            "providerRank": rank,
            # Kept apart for intent results: the business's own site, its Google
            # Maps listing, and the storable place ID. (contact.website keeps the
            # legacy "site, else Maps listing" fallback for older app versions.)
            "placeId": place_id,
            "websiteUri": pl.get("websiteUri"),
            "googleMapsUri": pl.get("googleMapsUri"),
            "sources": {
                "website_snippet": website_snippet,
                "place_details": place_details,
                "reviews_snippet": reviews_snippet,
            },
        }
