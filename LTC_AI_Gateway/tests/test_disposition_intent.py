"""B1 tests: Search Intent validation, specialty query construction, ranking
and evidence against realistic competing businesses, geographic scopes, the
curated directory, honest failures, privacy, and legacy compatibility.

Run from LTC_AI_Gateway/:
    .venv/bin/python -m unittest discover -s tests -v

Google is never called: Places HTTP traffic goes to an httpx.MockTransport.
"""

from __future__ import annotations

import copy
import json
import os
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

try:
    from test_disposition_partners import BOISE, DENVER, SEARCH_URL, _RouteTestBase, _place, _request
except ImportError:  # run as tests.test_disposition_intent
    from tests.test_disposition_partners import BOISE, DENVER, SEARCH_URL, _RouteTestBase, _place, _request

from app.core import config as ltc_config  # noqa: E402
from app.services.partner_discovery import directory as directory_mod  # noqa: E402
from app.services.partner_discovery import intent as intent_mod  # noqa: E402

GOLDEN = Path(__file__).parent / "fixtures" / "legacy_luxury_hubs.golden.json"
B1_RESULT_KEYS = {"source", "placeId", "directoryId", "googleMapsUri", "serviceEvidence", "evidenceSource",
                  "relevance", "geoScope", "areaMatch", "serviceArea", "intakeModel", "verifiedAt",
                  "acceptanceStatus", "attribution"}


def _intent(strategy="consignment", phrase="film camera", terms=(), scope="local", value_band=None):
    return SimpleNamespace(strategy=strategy, phrase=phrase, detailTerms=list(terms), geoScope=scope,
                           valueBand=value_band)


def _norm(strategy="consignment", phrase="film camera", terms=(), scope="local", city="Boise", region="ID"):
    return intent_mod.validate_intent(_intent(strategy, phrase, terms, scope), city=city, region=region,
                                      country_code="US")


def _queries(**kw):
    return [q.text for q in intent_mod.build_queries(_norm(**kw))]


def _intent_request(strategy="consignment", phrase="film camera", terms=(), scope="local", *,
                    city="Boise", region="ID", coords=BOISE, radius=25):
    body = _request("Electronics", city=city, region=region, coords=coords, radius=radius)
    # What B2 will send: no item name, notes, keywords, or value.
    body.pop("hints", None)
    body["scenario"] = {"category": "", "valueBand": "UNKNOWN", "bulky": False, "goal": "balanced"}
    body["searchIntent"] = {"schemaVersion": 1, "strategy": strategy, "phrase": phrase,
                            "detailTerms": list(terms), "geoScope": scope}
    return body


# ---------------------------------------------------------------------------
# Query construction (category-independent, strategy-controlled)
# ---------------------------------------------------------------------------

class QueryConstructionTests(unittest.TestCase):

    def test_1_leica_camera_consignment(self):
        q = _queries(phrase="film camera", terms=("Leica", "M3"))
        self.assertEqual(q, ["film camera consignment in Boise, Idaho",
                             "film camera specialist dealer in Boise, Idaho"])
        self.assertFalse(any("Leica" in x for x in q))  # brand ranks, it does not narrow

    def test_2_same_camera_quick_sale_override(self):
        q = _queries(strategy="quickSale", phrase="film camera", terms=("Leica",))
        self.assertEqual(q, ["used film camera buyer in Boise, Idaho", "film camera dealer in Boise, Idaho"])
        self.assertFalse(any("consign" in x for x in q))

    def test_3_luxury_handbag_national_makes_no_places_queries(self):
        self.assertEqual(_queries(phrase="designer handbag", scope="national"), [])

    def test_4_vintage_guitar_regional_maximize_price(self):
        q = _queries(strategy="maximizePrice", phrase="vintage electric guitar", scope="regional", region="CO")
        self.assertEqual(q, ["vintage electric guitar specialist dealer in Colorado",
                             "vintage electric guitar auction house in Colorado"])

    def test_5_art_regional_consignment(self):
        q = _queries(phrase="oil painting", scope="regional", region="Idaho")
        self.assertEqual(q, ["oil painting consignment in Idaho", "oil painting specialist dealer in Idaho"])

    def test_6_furniture_local_quick_sale(self):
        q = _queries(strategy="quickSale", phrase="dining table", city="Denver", region="CO")
        self.assertEqual(q[0], "used dining table buyer in Denver, Colorado")
        self.assertEqual(_queries(strategy="quickSale", phrase="vintage dresser")[0],
                         "vintage dresser buyer in Boise, Idaho")  # no "used vintage"

    def test_7_household_goods_donation(self):
        self.assertEqual(_queries(strategy="donation", phrase="household goods"),
                         ["household goods donation center in Boise, Idaho",
                          "charity that accepts household goods in Boise, Idaho"])

    def test_8_unfamiliar_equipment_category(self):
        q = _queries(strategy="maximizePrice", phrase="commercial embroidery machine")
        self.assertEqual(q[0], "commercial embroidery machine specialist dealer in Boise, Idaho")

    def test_9_closet_lot_piles(self):
        self.assertEqual(_queries(phrase="designer clothing", scope="national"), [])
        self.assertEqual(_queries(phrase="women's clothing")[0], "women's clothing consignment in Boise, Idaho")
        self.assertEqual(_queries(strategy="donation", phrase="clothing")[0],
                         "clothing donation center in Boise, Idaho")

    def test_strategy_controls_queries_and_never_exceeds_two(self):
        for strategy in intent_mod.STRATEGIES:
            for scope in ("local", "regional"):
                q = intent_mod.build_queries(_norm(strategy=strategy, scope=scope))
                self.assertLessEqual(len(q), intent_mod.MAX_PLACES_QUERIES)
                self.assertTrue(all("film camera" in x.text for x in q))
        self.assertTrue(all("consign" not in x for x in _queries(strategy="donation")))


# ---------------------------------------------------------------------------
# Validation and privacy (server-side, mirrors the app)
# ---------------------------------------------------------------------------

class IntentValidationTests(unittest.TestCase):

    def _bad(self, **kw):
        args = dict(strategy="consignment", phrase="film camera", terms=(), scope="local")
        args.update(kw)
        city = kw.pop("city", "Boise") if "city" in kw else "Boise"
        with self.assertRaises(intent_mod.IntentValidationError) as cm:
            intent_mod.validate_intent(_intent(args["strategy"], args["phrase"], args["terms"], args["scope"]),
                                       city=city, region=args.get("region", "ID"),
                                       country_code=args.get("country", "US"))
        return str(cm.exception)

    def test_rejects_private_or_malformed_phrases_without_echoing_them(self):
        for phrase in ("call jane@example.com", "see www.mycamera.com", "camera 208-555-1234",
                       "serial SN 123456789", "x" * 61, "one two three four five six seven eight nine",
                       "camera <script>", "", "   "):
            msg = self._bad(phrase=phrase)
            if phrase.strip():
                self.assertNotIn(phrase.strip(), msg)

    def test_accepts_normal_item_wording(self):
        for phrase in ("Leica M3 rangefinder", "women's clothing", "1978 guitar", "Hummel figurines",
                       "50mm f/2 lens", "arts & crafts lamp"):
            self.assertEqual(_norm(phrase=phrase).phrase, phrase)

    def test_detail_terms_are_limited_and_checked(self):
        self.assertEqual(_norm(terms=("Leica", "leica", "M3")).detail_terms, ("Leica", "M3"))
        self._bad(terms=("a", "b", "c", "d", "e"))
        self._bad(terms=("SN 1234567890",))

    def test_strategy_scope_and_location_rules(self):
        self._bad(strategy="needsInfo")
        self._bad(scope="worldwide")
        self._bad(country="CA")
        self._bad(scope="regional", region="Ontario")
        with self.assertRaises(intent_mod.IntentValidationError):
            intent_mod.validate_intent(_intent(), city="", region="ID", country_code="US")
        n = _norm(scope="regional", region="idaho")
        self.assertEqual((n.region_code, n.region_name, n.city), ("ID", "Idaho", ""))
        self.assertEqual(_norm(scope="national").region_code, "")

    def test_value_band_is_optional_and_never_invented(self):
        self.assertIsNone(_norm().value_band)
        n = intent_mod.validate_intent(_intent(value_band="HIGH"), city="Boise", region="ID", country_code="US")
        self.assertEqual(n.value_band, "HIGH")


# ---------------------------------------------------------------------------
# Route: ranking, evidence, scope, directory, failures
# ---------------------------------------------------------------------------

def _camera_market():
    """A realistic mix: specialists, a generic consignment shop, an excluded auction, a far store."""
    return [
        _place("gen", "Treasure Valley Consignment", 43.61, -116.20, primary="Consignment Shop",
               types=("store",)),
        _place("auto", "Valley Auto Auction", 43.60, -116.25, primary="Auto Auction", types=("car_dealer",)),
        _place("spec1", "Boise Camera & Video", 43.62, -116.21, primary="Camera Store",
               types=("camera_store", "electronics_store"), website=None),
        _place("spec2", "Idaho Film Camera Exchange", 43.63, -116.22, primary="Store", types=("store",)),
        _place("far", "Denver Camera Buyers", 39.74, -104.99, primary="Camera Store", types=("camera_store",),
               address="1 Market St, Denver, CO 80202, USA"),
    ]


class IntentRouteTests(_RouteTestBase):

    def _search(self, body, **kw):
        r = self.post(body, **kw)
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def test_specialists_outrank_generic_shops_and_nothing_is_overclaimed(self):
        self.fake.default = _camera_market()
        data = self._search(_intent_request(terms=("Leica",)))
        names = [r["name"] for r in data["results"]]

        self.assertNotIn("Valley Auto Auction", names)                       # excluded kind of business
        self.assertLess(names.index("Boise Camera & Video"), names.index("Treasure Valley Consignment"))
        self.assertLess(names.index("Idaho Film Camera Exchange"), names.index("Treasure Valley Consignment"))
        self.assertEqual(names[-1], "Denver Camera Buyers")                   # outside the area sinks

        by = {r["name"]: r for r in data["results"]}
        cam = by["Boise Camera & Video"]
        self.assertEqual(cam["relevance"], {"level": "specialist", "matchedTerms": ["camera"]})
        self.assertEqual(cam["serviceEvidence"]["consignment"], "not_mentioned")
        self.assertEqual(cam["partnerType"], "business")                     # not a "consignment" badge
        self.assertEqual(cam["acceptanceStatus"], "unknown")
        self.assertIsNone(cam["contact"]["website"])                         # no Maps link posing as a site
        self.assertEqual(cam["googleMapsUri"], "https://maps.google.com/?cid=spec1")
        self.assertEqual(cam["placeId"], "spec1")
        self.assertEqual(cam["source"], "google_places")
        self.assertEqual(cam["attribution"], "google_maps")
        self.assertIn("Confirm they accept your item", cam["whyRecommended"])

        shop = by["Treasure Valley Consignment"]
        self.assertEqual(shop["serviceEvidence"]["consignment"], "mentioned")  # what the listing says
        self.assertEqual(shop["relevance"]["level"], "general")
        self.assertEqual(shop["acceptanceStatus"], "unknown")                  # a name is not acceptance

        far = by["Denver Camera Buyers"]
        self.assertEqual(far["areaMatch"], "outside_area")
        self.assertEqual(far["serviceEvidence"]["buysOutright"], "mentioned")

        self.assertEqual(data["searchScope"], "local")
        self.assertEqual(data["directoryStatus"], "not_applicable")
        self.assertEqual(data["localDiscoveryStatus"], "ok")

    def test_results_without_distance_are_kept(self):
        self.fake.default = [{**_place("nol", "Boise Film Camera Repair & Sales", 0, 0), "location": None}]
        data = self._search(_intent_request())
        self.assertEqual(len(data["results"]), 1)
        self.assertIsNone(data["results"][0]["distanceMiles"])
        self.assertEqual(data["results"][0]["areaMatch"], "in_area")  # address names the city

    def test_second_query_runs_when_first_finds_only_generic_shops(self):
        generic = [_place(f"g{i}", f"Consignment Shop {i}", 43.62, -116.21) for i in range(8)]
        self.fake.places_by_keyword = {"consignment in": generic,
                                       "specialist dealer": [_place("s", "Boise Camera Exchange", 43.62, -116.21)]}
        data = self._search(_intent_request())
        self.assertEqual(len(self.fake.requests), 2)
        self.assertEqual(data["results"][0]["name"], "Boise Camera Exchange")

    def test_stops_after_one_query_when_specialists_suffice_and_never_exceeds_two(self):
        self.fake.default = [_place(f"s{i}", f"Camera Shop {i}", 43.62, -116.21) for i in range(6)]
        self._search(_intent_request())
        self.assertEqual(len(self.fake.requests), 1)

        self.fake.requests.clear()
        self.fake.default = []
        data = self._search(_intent_request())
        self.assertEqual(len(self.fake.requests), 2)
        self.assertEqual(data["localDiscoveryStatus"], "no_results")
        self.assertEqual(data["results"], [])

    def test_local_uses_bias_and_regional_does_not(self):
        self.fake.default = []
        self._search(_intent_request())
        self.assertIn("locationBias", self.fake.requests[0]["body"])
        self.assertEqual(self.fake.requests[0]["body"]["textQuery"], "film camera consignment in Boise, Idaho")

        self.fake.requests.clear()
        self._search(_intent_request(strategy="maximizePrice", phrase="vintage electric guitar",
                                     scope="regional", city="", region="CO", coords=DENVER))
        for req in self.fake.requests:
            self.assertNotIn("locationBias", req["body"])
            self.assertTrue(req["body"]["textQuery"].endswith("in Colorado"))
            self.assertEqual(req["body"]["regionCode"], "US")

    def test_regional_labels_results_outside_the_state(self):
        self.fake.default = [
            _place("co", "Colorado Vintage Guitars", 39.74, -104.99, address="2 Main St, Denver, CO 80202, USA"),
            _place("nm", "Santa Fe Guitar Dealer", 35.69, -105.94, address="3 Plaza, Santa Fe, NM 87501, USA"),
        ]
        data = self._search(_intent_request(strategy="maximizePrice", phrase="vintage guitar",
                                            scope="regional", city="", region="CO", coords=None))
        by = {r["name"]: r for r in data["results"]}
        self.assertEqual(by["Colorado Vintage Guitars"]["areaMatch"], "in_area")
        self.assertEqual(by["Santa Fe Guitar Dealer"]["areaMatch"], "outside_area")
        self.assertIn("outside Colorado", by["Santa Fe Guitar Dealer"]["whyRecommended"])
        self.assertEqual(data["results"][0]["name"], "Colorado Vintage Guitars")

    def test_national_uses_only_the_verified_directory(self):
        data = self._search(_intent_request(phrase="designer handbag", scope="national", city="", coords=None))
        self.assertEqual(self.fake.requests, [])  # zero Places calls
        ids = [r["directoryId"] for r in data["results"]]
        self.assertEqual(set(ids), {"directory:fashionphile", "curated:luxury:therealreal"})
        self.assertNotIn("curated:luxury:vestiaire", ids)  # carried over, not yet verified
        r = data["results"][0]
        self.assertEqual(r["source"], "ltc_directory")
        self.assertTrue(r["verifiedAt"])
        self.assertEqual(r["acceptanceStatus"], "unknown")
        self.assertEqual(data["directoryStatus"], "ok")
        self.assertEqual(data["localDiscoveryStatus"], "not_applicable")

    def test_national_directory_respects_strategy_and_reports_no_match(self):
        cam_consign = self._search(_intent_request(phrase="film camera", scope="national", city="", coords=None))
        self.assertEqual(cam_consign["results"], [])  # camera buyers are not consignors
        self.assertEqual(cam_consign["directoryStatus"], "no_match")
        cam_quick = self._search(_intent_request(strategy="quickSale", phrase="film camera", scope="national",
                                                 city="", coords=None))
        self.assertEqual({r["directoryId"] for r in cam_quick["results"]}, {"directory:keh", "directory:mpb"})
        self.assertTrue(all(r["serviceEvidence"] == {"buysOutright": "offered"} for r in cam_quick["results"]))
        sewing = self._search(_intent_request(strategy="maximizePrice", phrase="embroidery machine",
                                              scope="national", city="", coords=None))
        self.assertEqual((sewing["results"], sewing["directoryStatus"]), ([], "no_match"))
        self.assertEqual(self.fake.requests, [])

    def test_failures_are_honest_and_never_fabricated(self):
        self.fake.status_code = 500
        data = self._search(_intent_request())
        self.assertEqual((data["results"], data["localDiscoveryStatus"]), ([], "unavailable"))

        self.fake.status_code = 429
        data = self._search(_intent_request(), device="d2")
        self.assertEqual(data["localDiscoveryStatus"], "limited")

        self.fake.status_code = 200
        with mock.patch.object(ltc_config, "DISABLE_PLACES", True):
            data = self._search(_intent_request(), device="d3")
        self.assertEqual(data["localDiscoveryStatus"], "disabled")

        with mock.patch.dict(os.environ, {"K_SERVICE": "ltc-ai-gateway", "PARTNER_DISCOVERY_PROVIDER": "stub"}):
            data = self._search(_intent_request(), device="d4")
        self.assertEqual((data["results"], data["localDiscoveryStatus"]), ([], "unavailable"))
        self.assertNotIn("stub:", json.dumps(data))

    def test_existing_limits_still_apply(self):
        self.fake.default = []
        with mock.patch.object(ltc_config, "PLACES_SEARCHES_PER_DEVICE_DAY_LIMIT", 1):
            self._search(_intent_request(), device="lim")
            calls = len(self.fake.requests)
            data = self._search(_intent_request(), device="lim")
        self.assertEqual(len(self.fake.requests), calls)
        self.assertEqual(data["localDiscoveryStatus"], "limited")

        self.fake.requests.clear()
        with mock.patch.object(ltc_config, "PLACES_PER_DAY_LIMIT", 0):
            data = self._search(_intent_request(), device="budget")
        self.assertEqual(self.fake.requests, [])
        self.assertEqual(data["localDiscoveryStatus"], "limited")

    def test_invalid_intent_is_rejected_without_echoing_it(self):
        r = self.post(_intent_request(phrase="call 208-555-1234 for grandma's camera"))
        self.assertEqual(r.status_code, 422)
        self.assertNotIn("208-555-1234", r.text)
        self.assertNotIn("grandma", r.text.lower())
        self.assertEqual(self.fake.requests, [])

    def test_only_the_reviewed_phrase_and_place_reach_google_and_logs(self):
        body = _intent_request(phrase="film camera", terms=("Leica",))
        body["hints"] = {"keywords": ["Grandma Ruth"], "notes": "Grandma Ruth's Leica"}  # ignored for intents
        body["scenario"]["valueBand"] = "HIGH"
        body["itemId"] = "item-123"
        self.fake.default = []
        with self.assertLogs("app.routes.analyze_item_photo", level="INFO") as logs:
            self._search(body)
        sent = json.dumps([r["body"] for r in self.fake.requests])
        for private in ("Grandma", "Ruth", "item-123", "Leica", "HIGH"):
            self.assertNotIn(private, sent)
        logged = "\n".join(logs.output)
        self.assertIn("intent_search strategy=consignment scope=local", logged)
        for private in ("film camera", "Boise", "Leica"):
            self.assertNotIn(private, logged)

    def test_field_mask_is_unchanged(self):
        self.fake.default = []
        self._search(_intent_request())
        mask = self.fake.requests[0]["fieldMask"]
        self.assertNotIn("reviews", mask)
        self.assertNotIn("photos", mask)
        self.assertEqual(mask.count(","), 11)  # the same 12 fields as before B1


class LegacyCompatibilityTests(_RouteTestBase):

    def test_legacy_curated_hubs_match_the_pre_b1_golden_output(self):
        golden = json.loads(GOLDEN.read_text())
        for name, hints in (("no_hints", None), ("brand_hints", {"keywords": ["Chanel", "Hermes", "Gucci", "Prada"],
                                                                 "notes": "x"})):
            body = _request("Clothing", value_band="HIGH", bulky=False, path="A", coords=None)
            body.pop("hints", None)
            if hints:
                body["hints"] = hints
            data = self.post(body, device=f"golden-{name}").json()
            for r in data["results"]:
                for key in B1_RESULT_KEYS:
                    self.assertIsNone(r.pop(key, None))  # new fields are absent (null) on legacy results
            for key in ("scenarioId", "partnerTypes", "results", "localDiscoveryStatus", "notice", "disclaimer"):
                self.assertEqual(data[key], golden[name][key], key)
            self.assertIsNone(data.get("searchScope"))
            self.assertIsNone(data.get("directoryStatus"))

    def test_legacy_places_results_keep_their_shape(self):
        self.fake.default = [_place(f"c{i}", f"Consignment {i}", 43.62, -116.21, website=None) for i in range(6)]
        data = self.post(_request("Other")).json()
        self.assertTrue(data["results"])
        r = data["results"][0]
        # App 1.2's "Website" fallback to the Maps listing is preserved for legacy requests.
        self.assertTrue(r["contact"]["website"].startswith("https://maps.google.com"))
        self.assertIsNone(r.get("source"))
        self.assertEqual(data["scenarioId"], "default_any")


class DirectoryFileTests(unittest.TestCase):

    def test_directory_entries_are_well_formed(self):
        entries = directory_mod.load_directory()
        self.assertGreaterEqual(len(entries), 3)
        for e in entries:
            self.assertTrue(e["website"].startswith("https://"))
            if e.get("intentEligible"):
                self.assertTrue(e["verifiedAt"])
                self.assertTrue(e["verificationSource"])
        ids = {e["id"] for e in entries}
        self.assertTrue({"curated:luxury:therealreal", "curated:luxury:vestiaire", "curated:luxury:grailed"} <= ids)

    def test_matching_is_whole_word_and_strategy_aware(self):
        self.assertEqual(directory_mod.match_directory(strategy="maximizePrice", phrase="lens cap", detail_terms=[])[0]
                         ["entry"]["id"], "directory:keh")
        self.assertEqual(directory_mod.match_directory(strategy="consignment", phrase="glass", detail_terms=[]), [])
        self.assertEqual(directory_mod.match_directory(strategy="donation", phrase="designer handbag",
                                                       detail_terms=[]), [])
        jewelry = directory_mod.match_directory(strategy="maximizePrice", phrase="diamond ring", detail_terms=[])
        self.assertEqual(jewelry[0]["entry"]["id"], "directory:worthy")

    def test_bad_entries_are_rejected(self):
        with self.assertRaises(directory_mod.DirectoryError):
            directory_mod._validate({"id": "x", "name": "X", "website": "http://x", "serviceTypes": ["consignment"],
                                     "strategies": ["consignment"], "matchTerms": ["x"]})
        with self.assertRaises(directory_mod.DirectoryError):
            directory_mod._validate({"id": "x", "name": "X", "website": "https://x", "serviceTypes": ["consignment"],
                                     "strategies": ["consignment"], "matchTerms": ["x"], "intentEligible": True})


if __name__ == "__main__":
    unittest.main()
