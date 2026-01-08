# app/services/partner_discovery/providers.py
from __future__ import annotations

import math
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Protocol

import httpx

PartnerCandidate = Dict[str, Any]


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


class PartnerDiscoveryProvider(Protocol):
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
    Thin wrapper so the stub stays intact and selectable.
    """

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
    Google Places API (New) provider.
    """

    SEARCH_TEXT_URL = "https://places.googleapis.com/v1/places:searchText"
    PLACE_DETAILS_URL_TMPL = "https://places.googleapis.com/v1/places/{place_id}"

    def __init__(self, api_key: str, timeout_s: float = 8.0):
        if not api_key:
            raise ValueError("GooglePlacesNewProvider requires a non-empty API key.")
        self._api_key = api_key
        self._timeout = timeout_s

    def search(self, q: PartnerDiscoveryQuery) -> List[PartnerCandidate]:
        places = self._search_text(q)

        enriched: List[PartnerCandidate] = []
        for p in places[:12]:
            place_id = p.get("_google_place_id")
            if place_id:
                details = self._place_details(place_id)
                if details:
                    p = self._merge_details(p, details)
            enriched.append(self._to_candidate(p, q))

        return enriched

    def _headers(self, field_mask: str) -> Dict[str, str]:
        return {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self._api_key,
            "X-Goog-FieldMask": field_mask,
        }

    def _search_text(self, q: PartnerDiscoveryQuery) -> List[Dict[str, Any]]:
        body: Dict[str, Any] = {
            "textQuery": q.query,
            "languageCode": q.language_code,
            "regionCode": q.region_code,
            "maxResultCount": 20,
        }

        if q.center_lat is not None and q.center_lng is not None:
            body["locationBias"] = {
                "circle": {
                    "center": {"latitude": q.center_lat, "longitude": q.center_lng},
                    "radius": _miles_to_meters(q.radius_miles),
                }
            }

        field_mask = ",".join(
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
                "places.internationalPhoneNumber",
            ]
        )

        headers = dict(self._headers(field_mask))  # fresh dict per call (avoids shared mutation bugs)

        # Intermittent 400s and other transient failures happen in practice.
        # We'll retry a few times with small backoff. If it keeps failing, we raise.
        last_exc: Optional[Exception] = None
        max_attempts = 3

        with httpx.Client(timeout=self._timeout) as client:
            for attempt in range(1, max_attempts + 1):
                try:
                    resp = client.post(self.SEARCH_TEXT_URL, headers=headers, json=body)

                    if resp.status_code >= 400:
                        # IMPORTANT: log the outgoing inputs so we can reproduce the 400
                        print("\n=== GOOGLE PLACES ERROR DEBUG ===")
                        print("Attempt:", attempt, "/", max_attempts)
                        print("Status:", resp.status_code)
                        print("FieldMask:", headers.get("X-Goog-FieldMask"))
                        # If you include your API key in headers, do NOT print it.
                        # print("ApiKey:", headers.get("X-Goog-Api-Key"))  # <-- leave commented
                        print("RequestBody:", body)
                        print("ResponseText:", resp.text)
                        print("=== END GOOGLE PLACES ERROR DEBUG ===\n")

                    # Retry on common transient classes.
                    # - 429: rate limited
                    # - 5xx: server errors
                    # - 408: timeout
                    # - Some intermittent 400s are transient; we retry once or twice.
                    if resp.status_code in (408, 429) or 500 <= resp.status_code <= 599 or resp.status_code == 400:
                        if attempt < max_attempts:
                            time.sleep(0.4 * attempt)
                            continue

                    resp.raise_for_status()
                    data = resp.json()
                    break  # success

                except (httpx.TimeoutException, httpx.NetworkError, httpx.HTTPStatusError) as exc:
                    last_exc = exc
                    if attempt < max_attempts:
                        time.sleep(0.4 * attempt)
                        continue
                    raise
            else:
                # Should never happen due to break/raise above, but keep as guardrail.
                if last_exc:
                    raise last_exc
                raise httpx.HTTPError("Google Places searchText failed without exception detail.")

        raw_places = data.get("places", []) or []
        normalized: List[Dict[str, Any]] = []

        for pl in raw_places:
            place_id = pl.get("id")
            name_obj = pl.get("displayName") or {}
            display_name = name_obj.get("text") if isinstance(name_obj, dict) else None

            normalized.append(
                {
                    "_google_place_id": place_id,
                    "name": display_name or "(unknown)",
                    "formattedAddress": pl.get("formattedAddress"),
                    "location": pl.get("location"),
                    "rating": pl.get("rating"),
                    "userRatingCount": pl.get("userRatingCount"),
                    "googleMapsUri": pl.get("googleMapsUri"),
                    "websiteUri": pl.get("websiteUri"),
                    "nationalPhoneNumber": pl.get("nationalPhoneNumber"),
                    "internationalPhoneNumber": pl.get("internationalPhoneNumber"),
                }
            )

        return normalized

    def _place_details(self, place_id: str) -> Optional[Dict[str, Any]]:
        url = self.PLACE_DETAILS_URL_TMPL.format(place_id=place_id)

        field_mask = ",".join(
            [
                "id",
                "displayName",
                "formattedAddress",
                "location",
                "rating",
                "userRatingCount",
                "googleMapsUri",
                "websiteUri",
                "nationalPhoneNumber",
                "internationalPhoneNumber",
            ]
        )

        try:
            with httpx.Client(timeout=self._timeout) as client:
                resp = client.get(url, headers=self._headers(field_mask))
                resp.raise_for_status()
                return resp.json()
        except Exception:
            return None

    def _merge_details(self, base: Dict[str, Any], details: Dict[str, Any]) -> Dict[str, Any]:
        name_obj = details.get("displayName") or {}
        display_name = name_obj.get("text") if isinstance(name_obj, dict) else None

        merged = dict(base)
        merged["name"] = display_name or merged.get("name")
        merged["formattedAddress"] = details.get("formattedAddress") or merged.get("formattedAddress")
        merged["location"] = details.get("location") or merged.get("location")
        merged["rating"] = details.get("rating") if details.get("rating") is not None else merged.get("rating")
        merged["userRatingCount"] = details.get("userRatingCount") or merged.get("userRatingCount")
        merged["googleMapsUri"] = details.get("googleMapsUri") or merged.get("googleMapsUri")
        merged["websiteUri"] = details.get("websiteUri") or merged.get("websiteUri")
        merged["nationalPhoneNumber"] = details.get("nationalPhoneNumber") or merged.get("nationalPhoneNumber")
        merged["internationalPhoneNumber"] = details.get("internationalPhoneNumber") or merged.get(
            "internationalPhoneNumber"
        )
        return merged

    def _to_candidate(self, pl: Dict[str, Any], q: PartnerDiscoveryQuery) -> PartnerCandidate:
        place_id = pl.get("_google_place_id") or "unknown"
        partner_id = f"gplaces:{place_id}"

        dist_mi = float(q.radius_miles)
        loc = pl.get("location") or {}
        lat2 = _safe_float(loc.get("latitude"))
        lng2 = _safe_float(loc.get("longitude"))

        if q.center_lat is not None and q.center_lng is not None and lat2 is not None and lng2 is not None:
            dist_mi = float(round(_haversine_miles(q.center_lat, q.center_lng, lat2, lng2), 2))

        rating = _safe_float(pl.get("rating"))

        # Google calls it userRatingCount; your app wants userRatingsTotal (fine).
        user_ratings_total = _safe_int(pl.get("userRatingCount"))

        if isinstance(user_ratings_total, int) and user_ratings_total > 0:
            urc_txt = f"{user_ratings_total} ratings"
        else:
            urc_txt = "ratings"

        website = pl.get("websiteUri") or pl.get("googleMapsUri")
        phone = pl.get("nationalPhoneNumber") or pl.get("internationalPhoneNumber")

        website_snippet = (
            f"{pl.get('name')} — {q.partner_type.replace('_', ' ')}. {pl.get('formattedAddress') or ''}".strip()
        )
        place_details = (
            f"Address: {pl.get('formattedAddress') or 'unknown'}; "
            f"Phone: {phone or 'unknown'}; "
            f"Website: {website or 'unknown'}"
        )

        if rating is None:
            reviews_snippet = "Google rating unavailable"
        else:
            reviews_snippet = f"Google rating {rating:.1f}/5 ({urc_txt})"

        contact = {
            "phone": phone,
            "website": website,
            "email": None,
            "address": pl.get("formattedAddress") or "",
            "city": q.city,
            "region": q.region,
        }

        return {
            "partnerId": partner_id,
            "name": pl.get("name"),
            "partnerType": q.partner_type,
            "contact": contact,
            "distanceMiles": float(dist_mi),
            "rating": float(rating) if rating is not None else None,
            "userRatingsTotal": int(user_ratings_total) if isinstance(user_ratings_total, int) else None,
            "sources": {
                "website_snippet": website_snippet,
                "place_details": place_details,
                "reviews_snippet": reviews_snippet,
            },
        }
