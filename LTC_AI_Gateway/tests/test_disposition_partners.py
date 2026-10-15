"""Tests for Local Help partner discovery (provider selection, Places parsing,
location handling, limits, honest failure states, and curated luxury results).

Run from LTC_AI_Gateway/:
    .venv/bin/python -m unittest discover -s tests -v

Google is never called: Places HTTP traffic goes to an httpx.MockTransport.
"""

from __future__ import annotations

import json
import os
import unittest
from unittest import mock

# Pin the environment BEFORE importing the app (main.py calls load_dotenv(),
# which does not override variables that are already set).
os.environ.setdefault("GEMINI_API_KEY", "test-dummy-key")
os.environ["LTC_DISABLE_ALL_AI"] = "false"
os.environ["PARTNER_DISCOVERY_PROVIDER"] = "google"
os.environ["GOOGLE_PLACES_API_KEY"] = "test-places-key"

import httpx  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
from app.core import config as ltc_config  # noqa: E402
from app.core.rate_limiter import rate_limiter  # noqa: E402
from app.routes import analyze_item_photo as route  # noqa: E402
from app.services.partner_discovery import factory  # noqa: E402
from app.services.partner_discovery.providers import (  # noqa: E402
    GooglePlacesNewProvider,
    PartnerDiscoveryQuery,
    StubPartnerDiscoveryProvider,
)

BOISE = (43.6150, -116.2023)
DENVER = (39.7392, -104.9903)
SEARCH_URL = "/ai/disposition/partners/search"


def _place(pid, name, lat, lng, *, primary="Store", types=("store",), status="OPERATIONAL",
           rating=4.6, count=120, website="https://example.org/real", phone="(208) 555-1234",
           address="123 Real St, Boise, ID 83702, USA"):
    # NOTE: values here are test fixtures fed through a mocked transport; they
    # only exercise parsing and are never returned by production code paths.
    return {
        "id": pid,
        "displayName": {"text": name, "languageCode": "en"},
        "formattedAddress": address,
        "location": {"latitude": lat, "longitude": lng},
        "rating": rating,
        "userRatingCount": count,
        "googleMapsUri": f"https://maps.google.com/?cid={pid}",
        "websiteUri": website,
        "nationalPhoneNumber": phone,
        "businessStatus": status,
        "primaryTypeDisplayName": {"text": primary, "languageCode": "en"},
        "types": list(types),
    }


class _FakePlaces:
    """Records Text Search requests and serves canned responses."""

    def __init__(self, places_by_keyword=None, status_code=200, default=None):
        self.requests: list[dict] = []
        self.places_by_keyword = places_by_keyword or {}
        self.status_code = status_code
        self.default = default or []

    def handler(self, request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content.decode())
        self.requests.append({
            "url": str(request.url),
            "body": body,
            "fieldMask": request.headers.get("X-Goog-FieldMask"),
            "hasKey": bool(request.headers.get("X-Goog-Api-Key")),
        })
        if self.status_code != 200:
            return httpx.Response(self.status_code, json={"error": {"status": "ERR"}})
        q = body.get("textQuery", "").lower()
        for kw, places in self.places_by_keyword.items():
            if kw in q:
                return httpx.Response(200, json={"places": places})
        return httpx.Response(200, json={"places": self.default})


def _request(category="Furniture", *, value_band="MED", bulky=True, goal="balanced", path="B",
             city="Boise", region="ID", radius=25, coords=BOISE):
    loc = {"city": city, "region": region, "countryCode": "US", "radiusMiles": radius}
    if coords is not None:
        loc["latitude"], loc["longitude"] = coords
    return {
        "schemaVersion": 1,
        "scope": "item",
        "chosenPath": path,
        "scenario": {"category": category, "valueBand": value_band, "bulky": bulky, "goal": goal},
        "location": loc,
        "hints": {"keywords": ["Test"], "notes": "test"},
    }


class _RouteTestBase(unittest.TestCase):
    def setUp(self):
        rate_limiter._daily.clear()
        rate_limiter._store.clear()
        route._DISPOSITION_CACHE.clear()
        self.client = TestClient(main.app)
        self.fake = _FakePlaces()
        self._patches = [
            mock.patch.object(
                factory,
                "GooglePlacesNewProvider",
                lambda api_key: GooglePlacesNewProvider(
                    api_key, transport=httpx.MockTransport(self.fake.handler), max_attempts=1
                ),
            ),
            mock.patch.dict(os.environ, {"PARTNER_DISCOVERY_PROVIDER": "google",
                                         "GOOGLE_PLACES_API_KEY": "test-places-key"}),
        ]
        for p in self._patches:
            p.start()

    def tearDown(self):
        for p in reversed(self._patches):
            p.stop()

    def post(self, body, device="test-device"):
        return self.client.post(SEARCH_URL, json=body, headers={"X-LTC-Device-ID": device})


# ---------------------------------------------------------------------------
# Provider selection
# ---------------------------------------------------------------------------

class ProviderSelectionTests(unittest.TestCase):
    def _get(self, env):
        with mock.patch.dict(os.environ, env, clear=False):
            for k in ("PARTNER_DISCOVERY_PROVIDER", "GOOGLE_PLACES_API_KEY", "K_SERVICE"):
                if k not in env:
                    os.environ.pop(k, None)
            return factory.get_partner_discovery_provider(stub_fn=route._stub_places_search)

    def test_unset_provider_defaults_to_google_not_stub(self):
        p = self._get({"GOOGLE_PLACES_API_KEY": "k"})
        self.assertIsInstance(p, GooglePlacesNewProvider)
        self.assertFalse(p.is_stub)

    def test_google_without_key_is_a_config_error(self):
        with self.assertRaises(factory.PartnerDiscoveryConfigError):
            self._get({"PARTNER_DISCOVERY_PROVIDER": "google"})

    def test_unset_everything_is_a_config_error_not_stub(self):
        with self.assertRaises(factory.PartnerDiscoveryConfigError):
            self._get({})

    def test_stub_refused_on_cloud_run(self):
        with self.assertRaises(factory.PartnerDiscoveryConfigError):
            self._get({"PARTNER_DISCOVERY_PROVIDER": "stub", "K_SERVICE": "ltc-ai-gateway"})

    def test_stub_allowed_locally_when_explicit(self):
        p = self._get({"PARTNER_DISCOVERY_PROVIDER": "stub"})
        self.assertIsInstance(p, StubPartnerDiscoveryProvider)

    def test_unknown_provider_is_a_config_error(self):
        with self.assertRaises(factory.PartnerDiscoveryConfigError):
            self._get({"PARTNER_DISCOVERY_PROVIDER": "yelp", "GOOGLE_PLACES_API_KEY": "k"})


# ---------------------------------------------------------------------------
# Google Places (New) provider parsing
# ---------------------------------------------------------------------------

class GoogleProviderParsingTests(unittest.TestCase):
    def _provider(self, fake):
        return GooglePlacesNewProvider("k", transport=httpx.MockTransport(fake.handler), max_attempts=1)

    def test_parses_places_and_computes_real_distance(self):
        fake = _FakePlaces(default=[_place("p1", "Ricochet Home Consignment", 43.6766, -116.2810)])
        q = PartnerDiscoveryQuery(query="Boise ID furniture consignment", city="Boise", region="ID",
                                  radius_miles=25, partner_type="consignment",
                                  center_lat=BOISE[0], center_lng=BOISE[1])
        [c] = self._provider(fake).search(q)
        self.assertEqual(c["partnerId"], "gplaces:p1")
        self.assertEqual(c["name"], "Ricochet Home Consignment")
        self.assertEqual(c["contact"]["address"], "123 Real St, Boise, ID 83702, USA")
        self.assertEqual(c["contact"]["phone"], "(208) 555-1234")
        self.assertEqual(c["rating"], 4.6)
        self.assertEqual(c["userRatingsTotal"], 120)
        self.assertAlmostEqual(c["distanceMiles"], 5.75, delta=0.3)
        # Evidence comes from Google data, not from the searched partner type.
        self.assertIn("Ricochet Home Consignment", c["sources"]["website_snippet"])

    def test_one_text_search_call_no_place_details(self):
        fake = _FakePlaces(default=[_place(f"p{i}", f"Shop {i}", 43.6, -116.2) for i in range(12)])
        q = PartnerDiscoveryQuery(query="x", city="Boise", region="ID", radius_miles=25,
                                  partner_type="consignment", center_lat=BOISE[0], center_lng=BOISE[1])
        self._provider(fake).search(q)
        self.assertEqual(len(fake.requests), 1)
        self.assertIn("places:searchText", fake.requests[0]["url"])
        self.assertTrue(fake.requests[0]["hasKey"])
        mask = fake.requests[0]["fieldMask"]
        self.assertNotIn("reviews", mask)
        self.assertNotIn("photos", mask)

    def test_no_coordinates_means_no_distance_and_no_bias(self):
        fake = _FakePlaces(default=[_place("p1", "Shop", 43.6, -116.2)])
        q = PartnerDiscoveryQuery(query="x", city="Boise", region="ID", radius_miles=25,
                                  partner_type="consignment")
        [c] = self._provider(fake).search(q)
        self.assertIsNone(c["distanceMiles"])
        self.assertNotIn("locationBias", fake.requests[0]["body"])

    def test_bias_radius_is_clamped_to_places_limit(self):
        fake = _FakePlaces(default=[])
        q = PartnerDiscoveryQuery(query="x", city="Boise", region="ID", radius_miles=100,
                                  partner_type="consignment", center_lat=BOISE[0], center_lng=BOISE[1])
        self._provider(fake).search(q)
        self.assertLessEqual(fake.requests[0]["body"]["locationBias"]["circle"]["radius"], 50_000.0)

    def test_closed_businesses_are_dropped(self):
        fake = _FakePlaces(default=[
            _place("open", "Open Shop", 43.6, -116.2),
            _place("closed", "Closed Shop", 43.6, -116.2, status="CLOSED_PERMANENTLY"),
        ])
        q = PartnerDiscoveryQuery(query="x", city="Boise", region="ID", radius_miles=25, partner_type="consignment")
        names = [c["name"] for c in self._provider(fake).search(q)]
        self.assertEqual(names, ["Open Shop"])


# ---------------------------------------------------------------------------
# Route behavior
# ---------------------------------------------------------------------------

class LocalHelpRouteTests(_RouteTestBase):
    def test_furniture_returns_real_places_with_status_ok(self):
        self.fake.places_by_keyword = {
            "consignment": [_place(f"c{i}", f"Boise Consignment {i}", 43.62, -116.21) for i in range(6)],
            "estate": [_place(f"e{i}", f"Estate Sale Co {i}", 43.60, -116.20) for i in range(6)],
        }
        r = self.post(_request("Furniture"))
        self.assertEqual(r.status_code, 200, r.text)
        data = r.json()
        self.assertEqual(data["scenarioId"], "furniture_bulky_med_balanced")
        self.assertEqual(data["localDiscoveryStatus"], "ok")
        self.assertIsNone(data.get("notice"))
        ids = [x["partnerId"] for x in data["results"]]
        self.assertTrue(ids and all(i.startswith("gplaces:") for i in ids))
        self.assertTrue(all(x["distanceMiles"] is not None for x in data["results"]))
        # Enough results from the first query of each type: 2 calls total.
        self.assertEqual(len(self.fake.requests), 2)

    def test_coordinates_from_request_are_sent_to_google(self):
        self.fake.default = []
        self.post(_request("Other", coords=DENVER, city="Denver", region="CO"))
        bias = self.fake.requests[0]["body"]["locationBias"]["circle"]["center"]
        self.assertEqual((bias["latitude"], bias["longitude"]), DENVER)
        self.assertTrue(self.fake.requests[0]["body"]["textQuery"].startswith("Denver CO"))

    def test_manual_city_without_coordinates_searches_by_text_and_invents_no_distance(self):
        self.fake.default = [_place("x1", "Denver Consignment", 39.74, -104.99)]
        r = self.post(_request("Other", coords=None, city="Denver", region="CO"))
        data = r.json()
        self.assertNotIn("locationBias", self.fake.requests[0]["body"])
        self.assertTrue(self.fake.requests[0]["body"]["textQuery"].startswith("Denver CO"))
        self.assertTrue(data["results"])
        self.assertTrue(all(x["distanceMiles"] is None for x in data["results"]))

    def test_coordinates_far_from_searched_city_do_not_hide_results_or_invent_distance(self):
        # App 1.1 always sends Boise coordinates, even when the user types another city.
        self.fake.default = [_place(f"d{i}", f"Denver Consignment {i}", 39.74, -104.99) for i in range(3)]
        data = self.post(_request("Other", coords=BOISE, city="Denver", region="CO")).json()
        self.assertTrue(data["results"])
        self.assertTrue(all(x["distanceMiles"] is None for x in data["results"]))

    def test_half_coordinate_is_ignored(self):
        body = _request("Other")
        del body["location"]["longitude"]
        self.fake.default = []
        self.post(body)
        self.assertNotIn("locationBias", self.fake.requests[0]["body"])

    def test_far_results_are_filtered_by_radius(self):
        near = [_place(f"n{i}", f"Near Consignment {i}", 43.62, -116.21) for i in range(6)]
        far = [_place("far", "Far Consignment", 47.6, -122.3)]  # Seattle
        self.fake.default = near + far
        data = self.post(_request("Other")).json()
        self.assertNotIn("gplaces:far", [x["partnerId"] for x in data["results"]])

    def test_empty_places_response_is_honest_no_results(self):
        self.fake.default = []
        data = self.post(_request("Furniture")).json()
        self.assertEqual(data["results"], [])
        self.assertEqual(data["localDiscoveryStatus"], "no_results")
        self.assertTrue(data["notice"])

    def test_upstream_error_is_unavailable_never_stub(self):
        self.fake.status_code = 500
        r = self.post(_request("Furniture"))
        self.assertEqual(r.status_code, 200)
        data = r.json()
        self.assertEqual(data["results"], [])
        self.assertEqual(data["localDiscoveryStatus"], "unavailable")
        self.assertIn("unavailable", data["notice"])

    def test_upstream_quota_is_reported_as_limited(self):
        self.fake.status_code = 429
        data = self.post(_request("Furniture")).json()
        self.assertEqual(data["localDiscoveryStatus"], "limited")

    def test_unconfirmed_businesses_outside_top_matches_are_dropped(self):
        places = [_place(f"g{i}", f"Generic Furniture Store {i}", 43.62, -116.21) for i in range(8)]
        places.append(_place("c1", "Again Consignment", 43.62, -116.21))
        self.fake.default = places
        ids = [x["partnerId"] for x in self.post(_request("Other")).json()["results"]]
        self.assertIn("gplaces:c1", ids)          # confirmed by name, kept despite rank 8
        self.assertIn("gplaces:g0", ids)          # Google's top match, kept as "likely"
        self.assertNotIn("gplaces:g7", ids)       # unconfirmed and low-ranked, dropped

    def test_exclude_keywords_drop_wrong_kind_of_business(self):
        self.fake.places_by_keyword = {
            "rug": [
                _place("r1", "Persian Rug Gallery", 43.62, -116.21),
                _place("r2", "Fine Rug Cleaning Co", 43.62, -116.21),
                _place("r3", "Cost Less Carpet", 43.62, -116.21, primary="Flooring store", types=("flooring_store",)),
            ],
        }
        ids = [x["partnerId"] for x in self.post(_request("Rug")).json()["results"]]
        self.assertIn("gplaces:r1", ids)
        self.assertNotIn("gplaces:r2", ids)
        self.assertNotIn("gplaces:r3", ids)

    def test_same_business_appears_once_across_partner_types(self):
        shared = _place("shared", "Thrift and Consignment", 43.62, -116.21)
        self.fake.default = [shared]
        ids = [x["partnerId"] for x in self.post(_request("Other")).json()["results"]]
        self.assertEqual(ids.count("gplaces:shared"), 1)


class CostAndSafetyControlTests(_RouteTestBase):
    def test_kill_switch_makes_no_places_calls(self):
        with mock.patch.object(ltc_config, "DISABLE_PLACES", True):
            data = self.post(_request("Furniture")).json()
        self.assertEqual(self.fake.requests, [])
        self.assertEqual(data["localDiscoveryStatus"], "disabled")
        self.assertEqual(data["results"], [])

    def test_daily_places_budget_is_enforced(self):
        self.fake.default = []
        with mock.patch.object(ltc_config, "PLACES_PER_DAY_LIMIT", 1):
            data = self.post(_request("Furniture")).json()
        self.assertEqual(len(self.fake.requests), 1)
        self.assertEqual(data["localDiscoveryStatus"], "limited")

    def test_per_device_search_limit_is_enforced(self):
        self.fake.default = []
        with mock.patch.object(ltc_config, "PLACES_SEARCHES_PER_DEVICE_DAY_LIMIT", 1):
            self.post(_request("Other"), device="dev-a")
            calls = len(self.fake.requests)
            data = self.post(_request("Furniture"), device="dev-a").json()
            self.assertEqual(len(self.fake.requests), calls)
            self.assertEqual(data["localDiscoveryStatus"], "limited")
            self.post(_request("Furniture"), device="dev-b")
            self.assertGreater(len(self.fake.requests), calls)

    def test_queries_per_type_are_capped(self):
        self.fake.default = []  # never "enough", so the loop would keep going
        self.post(_request("Furniture"))
        # 2 partner types x LTC_PLACES_MAX_QUERIES_PER_TYPE (2)
        self.assertEqual(len(self.fake.requests), 4)

    def test_repeat_search_uses_short_cache(self):
        self.fake.default = [_place(f"c{i}", f"Consignment {i}", 43.62, -116.21) for i in range(6)]
        self.post(_request("Other"))
        n = len(self.fake.requests)
        self.post(_request("Other"))
        self.assertEqual(len(self.fake.requests), n)


class ProductionStubGuardTests(_RouteTestBase):
    def test_cloud_run_with_stub_configured_returns_no_fake_businesses(self):
        with mock.patch.dict(os.environ, {"K_SERVICE": "ltc-ai-gateway", "PARTNER_DISCOVERY_PROVIDER": "stub"}):
            data = self.post(_request("Furniture")).json()
        self.assertEqual(data["results"], [])
        self.assertEqual(data["localDiscoveryStatus"], "unavailable")
        blob = json.dumps(data)
        for fake_marker in ("Heritage Consignment", "555-01", "example.com", "stub:"):
            self.assertNotIn(fake_marker, blob)

    def test_cloud_run_without_places_key_is_unavailable(self):
        with mock.patch.dict(os.environ, {"K_SERVICE": "ltc-ai-gateway"}):
            os.environ.pop("GOOGLE_PLACES_API_KEY", None)
            os.environ.pop("PARTNER_DISCOVERY_PROVIDER", None)
            data = self.post(_request("Furniture")).json()
        self.assertEqual(data["localDiscoveryStatus"], "unavailable")
        self.assertEqual(data["results"], [])

    def test_stub_ids_are_stripped_on_cloud_run_even_if_a_provider_returns_them(self):
        fake_stub = StubPartnerDiscoveryProvider(route._stub_places_search)
        with mock.patch.dict(os.environ, {"K_SERVICE": "ltc-ai-gateway"}), \
                mock.patch.object(factory, "get_partner_discovery_provider", lambda stub_fn=None: fake_stub):
            data = self.post(_request("Furniture")).json()
        self.assertFalse(any(x["partnerId"].startswith("stub:") for x in data["results"]))


class CategoryMatchingTests(_RouteTestBase):
    def _scenario(self, **kw):
        # iOS only marks furniture/appliance/rug/electronics items as bulky.
        kw.setdefault("bulky", False)
        self.fake.default = []
        return self.post(_request(**kw)).json()

    def test_category_routing(self):
        cases = {
            ("Furniture", "MED", "A"): "furniture_bulky_med_balanced",
            ("Dining Room", "HIGH", "B"): "furniture_bulky_med_balanced",
            ("Rug", "MED", "B"): "rug_any",
            ("Rug Collection", "HIGH", "A"): "rug_any",
            ("China & Crystal", "LOW", "C"): "china_crystal_any",
            ("China/Dinnerware", "MED", "B"): "china_crystal_any",
            ("Crystal/Stemware", "MED", "B"): "china_crystal_any",
            ("Collectibles", "MED", "A"): "collectibles_cards_toys_balanced",
            ("Jewelry", "HIGH", "A"): "jewelry_luxury_high_value",
            ("Luxury Personal Items", "MED", "B"): "jewelry_luxury_high_value",
            ("Jewelry", "LOW", "B"): "default_any",
            ("Decor", "MED", "B"): "default_any",
            ("Furniture", "MED", "donate"): "donate_path",
        }
        for (cat, band, path), expected in cases.items():
            with self.subTest(category=cat, band=band, path=path):
                data = self._scenario(category=cat, value_band=band, path=path)
                self.assertEqual(data["scenarioId"], expected)

    def test_rug_and_china_partner_types(self):
        self.assertEqual(self._scenario(category="Rug")["partnerTypes"], ["rug_dealer", "consignment"])
        self.assertEqual(self._scenario(category="China & Crystal")["partnerTypes"], ["antique_dealer", "consignment"])
        self.assertEqual(self._scenario(category="Collectibles")["partnerTypes"], ["dealer", "auction"])
        self.assertEqual(self._scenario(category="Jewelry", value_band="HIGH")["partnerTypes"], ["estate_jeweler", "auction"])


class CuratedLuxuryTests(_RouteTestBase):
    def test_luxury_clothing_returns_curated_hubs_without_places(self):
        data = self.post(_request("Clothing", value_band="HIGH", bulky=False, path="A")).json()
        self.assertEqual(data["scenarioId"], "clothing_luxury_med_high_value")
        self.assertEqual(sorted(x["name"] for x in data["results"]),
                         ["Grailed (Menswear)", "The RealReal", "Vestiaire Collective"])
        self.assertTrue(all(x["trust"]["claimLevel"] == "curated" for x in data["results"]))
        self.assertEqual(self.fake.requests, [])
        self.assertEqual(data["localDiscoveryStatus"], "not_applicable")

    def test_set_luxury_block_goal_maximize_price_reaches_curated_hubs(self):
        # iOS Set luxury block sends goal "maximizePrice" (camelCase).
        data = self.post(_request("clothing", value_band="HIGH", bulky=False, goal="maximizePrice", path="B")).json()
        self.assertEqual(data["scenarioId"], "clothing_luxury_med_high_value")
        self.assertTrue(data["results"])

    def test_curated_hubs_survive_places_outage(self):
        with mock.patch.dict(os.environ, {"K_SERVICE": "ltc-ai-gateway"}):
            os.environ.pop("GOOGLE_PLACES_API_KEY", None)
            data = self.post(_request("Clothing", value_band="HIGH", bulky=False, path="A")).json()
        self.assertEqual(len(data["results"]), 3)

    def test_missing_chosen_path_is_accepted(self):
        body = _request("Other")
        del body["chosenPath"]
        self.fake.default = []
        self.assertEqual(self.post(body).status_code, 200)


if __name__ == "__main__":
    unittest.main()
