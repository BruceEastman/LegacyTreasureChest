"""A1 tests: customer-facing approach names in Briefs, and the optional
specialty block (validation, tolerance of bad data, compatibility).

Run from LTC_AI_Gateway/:
    .venv/bin/python -m unittest discover -s tests -v

Gemini is never called: the route's Gemini functions are stubbed per test.
"""

from __future__ import annotations

import json
import os
import unittest
import uuid
from unittest import mock

# Pin the environment BEFORE importing the app (main.py calls load_dotenv(),
# which does not override variables that are already set).
os.environ.setdefault("GEMINI_API_KEY", "test-dummy-key")
os.environ["LTC_DISABLE_ALL_AI"] = "false"
os.environ["LTC_DISABLE_GEMINI"] = "false"

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
from app.models_liquidation import LiquidationBriefDTO, LiquidationBriefRequest  # noqa: E402
from app.routes import analyze_item_photo as route  # noqa: E402
from app.services import gemini_client  # noqa: E402

APPROVED_NAMES = {
    "pathA_maximizePrice": "Maximize Price",
    "pathB_delegateConsign": "Consignment",
    "pathC_quickExit": "Quick Sale",
    "donate": "Donation",
}

# The exact item request shape app 1.2 sends (Swift omits nil optionals).
APP_12_ITEM_REQUEST = {
    "schemaVersion": 1,
    "scope": "item",
    "title": "Leica M3 camera with 50mm lens",
    "description": "Film rangefinder camera. Maker: Leica. Light wear on the top plate.",
    "category": "Electronics",
    "quantity": 1,
    "unitValue": 1800,
    "currencyCode": "USD",
    "valuationLow": 1400,
    "valuationLikely": 1800,
    "valuationHigh": 2200,
    "inputs": {"goal": "balanced"},
}

APP_12_SET_REQUEST = {
    "schemaVersion": 1,
    "scope": "set",
    "title": "Noritake china service",
    "category": "China/Dinnerware",
    "quantity": 68,
    "currencyCode": "USD",
    "setContext": {
        "setName": "Noritake china service",
        "setType": "China/Dinnerware",
        "sellTogetherPreference": "Together",
        "completeness": "Complete",
        "memberSummaries": [
            {"title": "Noritake dinner plate", "category": "China & Crystal", "quantity": 12, "unitValue": 15},
        ],
    },
    "inputs": {"goal": "balanced"},
}


async def _no_network(*_args, **_kwargs):
    raise AssertionError("Tests must not call Gemini over the network.")


def _option(path, **kw):
    opt = {"id": str(uuid.uuid4()), "path": path, "effort": "medium", "risks": []}
    opt.update(kw)
    return opt


def _brief_json(recommended="pathB_delegateConsign", options=None, **kw) -> str:
    obj = {
        "schemaVersion": 1, "scope": "item", "generatedAt": "2026-10-16T00:00:00Z",
        "recommendedPath": recommended, "reasoning": "Specialists know this market.",
        "pathOptions": options if options is not None else [
            _option("pathA_maximizePrice", label="Sell it yourself online"),
            _option("pathB_delegateConsign", label="Specialist camera consignment"),
            _option("pathC_quickExit", label="Sell to a local dealer"),
        ],
        "actionSteps": ["Step one"],
    }
    obj.update(kw)
    return json.dumps(obj)


class _BriefRouteTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._net_patch = mock.patch.object(gemini_client, "_post_gemini", _no_network)
        cls._net_patch.start()
        cls.client = TestClient(main.app)

    @classmethod
    def tearDownClass(cls):
        cls._net_patch.stop()

    def _post_brief(self, request: dict, *gemini_responses: str) -> dict:
        queue = list(gemini_responses)

        async def _stub(*, prompt: str, photo_base64=None) -> str:
            return queue.pop(0)

        with mock.patch.object(route, "call_gemini_for_liquidation_brief", _stub):
            r = self.client.post("/ai/generate-liquidation-brief", json=request,
                                 headers={"X-LTC-Device-ID": f"a1-{uuid.uuid4()}"})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()


class ApproachNameTests(_BriefRouteTestCase):

    def test_fallback_labels_use_approved_names(self):
        options = [{"id": str(uuid.uuid4()), "path": p, "effort": "low", "risks": []} for p in APPROVED_NAMES]
        body = self._post_brief(APP_12_ITEM_REQUEST, _brief_json("pathA_maximizePrice", options))
        labels = {o["path"]: o["label"] for o in body["pathOptions"]}
        self.assertEqual(labels, APPROVED_NAMES)

    def test_fallback_label_table_covers_every_path(self):
        self.assertEqual(
            route._APPROACH_NAMES,
            {**APPROVED_NAMES, "needsInfo": "More Information Needed"},
        )

    def test_raw_identifiers_are_replaced_in_customer_text_only(self):
        options = [
            _option("pathA_maximizePrice", label="Path A — Maximize Price",
                    risks=["Slower than pathC_quickExit"]),
            _option("pathB_delegateConsign", label="PathB_DelegateConsign",
                    logisticsNotes="Path B usually means mail-in."),
            _option("pathC_quickExit", label="Quick local sale"),
        ]
        raw = _brief_json(
            "pathB_delegateConsign", options,
            reasoning="pathB_delegateConsign fits better than Path A here; needsInfo is not required.",
            missingDetails=["Shutter test (affects path_c_quick_exit pricing)"],
        )
        body = self._post_brief(APP_12_ITEM_REQUEST, raw)

        # Program identifiers are untouched.
        self.assertEqual(body["recommendedPath"], "pathB_delegateConsign")
        self.assertEqual([o["path"] for o in body["pathOptions"]],
                         ["pathA_maximizePrice", "pathB_delegateConsign", "pathC_quickExit"])

        self.assertEqual(
            body["reasoning"],
            "Consignment fits better than Maximize Price here; More Information Needed is not required.",
        )
        self.assertEqual(body["pathOptions"][0]["label"], "Maximize Price")
        self.assertEqual(body["pathOptions"][0]["risks"], ["Slower than Quick Sale"])
        self.assertEqual(body["pathOptions"][1]["label"], "Consignment")
        self.assertEqual(body["pathOptions"][1]["logisticsNotes"], "Consignment usually means mail-in.")
        self.assertEqual(body["missingDetails"], ["Shutter test (affects Quick Sale pricing)"])

    def test_ordinary_prose_about_paths_is_untouched(self):
        text = "There is a path a buyer could take, and the pathway is clear."
        self.assertEqual(route._customer_text(text), text)

    def test_recommendation_matches_its_option(self):
        body = self._post_brief(APP_12_ITEM_REQUEST, _brief_json("pathB_delegateConsign"))
        recommended = [o for o in body["pathOptions"] if o["path"] == body["recommendedPath"]]
        self.assertEqual(len(recommended), 1)
        self.assertEqual(recommended[0]["label"], "Specialist camera consignment")

    def test_prompt_asks_for_customer_names_and_specialty(self):
        prompt = route._build_liquidation_brief_prompt(LiquidationBriefRequest.model_validate(APP_12_ITEM_REQUEST))
        self.assertIn("never write an identifier", prompt)
        self.assertIn("Maximize Price, Consignment, Quick Sale, or Donation", prompt)
        self.assertIn('SPECIALTY (optional "specialty" object', prompt)
        self.assertIn("Never include business names", prompt)


class SpecialtyBlockTests(_BriefRouteTestCase):

    def test_well_formed_specialty_survives_validation(self):
        specialty = {"itemKind": "film camera", "detailTerms": ["rangefinder", "50mm lens"],
                     "brand": "Leica", "model": "M3", "isSpecialistItem": True}
        body = self._post_brief(APP_12_ITEM_REQUEST, _brief_json(specialty=specialty))
        self.assertEqual(body["specialty"], specialty)

    def test_missing_specialty_is_null_and_brief_is_valid(self):
        body = self._post_brief(APP_12_ITEM_REQUEST, _brief_json())
        self.assertIsNone(body["specialty"])
        self.assertEqual(body["recommendedPath"], "pathB_delegateConsign")

    def test_malformed_specialty_is_dropped_not_fatal(self):
        for bad in ("film camera", ["film camera"], 42, {"itemKind": 7, "detailTerms": "x" * 0},
                    {"itemKind": "  ", "brand": None}, {}):
            with self.subTest(bad=bad):
                body = self._post_brief(APP_12_ITEM_REQUEST, _brief_json(specialty=bad))
                self.assertIsNone(body["specialty"])
                self.assertEqual(len(body["pathOptions"]), 3)

    def test_brand_and_model_must_appear_in_item_text(self):
        specialty = {"itemKind": "film camera", "brand": "Nikon", "model": "M3", "isSpecialistItem": True}
        body = self._post_brief(APP_12_ITEM_REQUEST, _brief_json(specialty=specialty))
        self.assertIsNone(body["specialty"]["brand"])  # "Nikon" is not in the item text
        self.assertEqual(body["specialty"]["model"], "M3")

    def test_terms_are_trimmed_deduplicated_and_capped(self):
        specialty = {"itemKind": "  film   camera ", "isSpecialistItem": "yes",
                     "detailTerms": ["rangefinder", "Rangefinder", "", None, "chrome", "50mm", "1950s", "extra"]}
        body = self._post_brief(APP_12_ITEM_REQUEST, _brief_json(specialty=specialty))
        self.assertEqual(body["specialty"]["itemKind"], "film camera")
        self.assertEqual(body["specialty"]["detailTerms"], ["rangefinder", "chrome", "50mm", "1950s"])
        self.assertTrue(body["specialty"]["isSpecialistItem"])

    def test_single_term_string_becomes_a_list(self):
        body = self._post_brief(APP_12_ITEM_REQUEST,
                                _brief_json(specialty={"itemKind": "film camera", "detailTerms": "rangefinder"}))
        self.assertEqual(body["specialty"]["detailTerms"], ["rangefinder"])
        self.assertFalse(body["specialty"]["isSpecialistItem"])

    def test_set_specialty_can_use_member_text(self):
        specialty = {"itemKind": "china dinnerware", "brand": "Noritake", "isSpecialistItem": True}
        body = self._post_brief(APP_12_SET_REQUEST, _brief_json(specialty=specialty, scope="set"))
        self.assertEqual(body["specialty"]["brand"], "Noritake")


class CompatibilityTests(_BriefRouteTestCase):

    def test_app_12_set_request_still_valid(self):
        body = self._post_brief(APP_12_SET_REQUEST, _brief_json(scope="set"))
        self.assertEqual(body["scope"], "set")

    def test_legacy_brief_without_specialty_validates(self):
        legacy = json.loads(_brief_json())
        legacy.pop("specialty", None)
        dto = LiquidationBriefDTO.model_validate(legacy)
        self.assertIsNone(dto.specialty)

    def _post_plan(self, brief: dict) -> int:
        async def _stub(*, prompt: str) -> str:
            return json.dumps({"schemaVersion": 1, "createdAt": "2026-10-16T00:00:00Z",
                               "items": [{"order": 1, "text": "Do the thing"}]})

        request = {"schemaVersion": 1, "scope": "item", "chosenPath": "pathB_delegateConsign",
                   "brief": brief, "title": "Leica M3", "category": "Electronics"}
        with mock.patch.object(route, "call_gemini_for_liquidation_plan", _stub):
            r = self.client.post("/ai/generate-liquidation-plan", json=request,
                                 headers={"X-LTC-Device-ID": f"a1-{uuid.uuid4()}"})
        return r.status_code

    def test_plan_request_accepts_brief_with_and_without_specialty(self):
        legacy = json.loads(_brief_json())
        self.assertEqual(self._post_plan(legacy), 200)

        with_specialty = dict(legacy, specialty={"itemKind": "film camera", "detailTerms": [],
                                                 "brand": None, "model": None, "isSpecialistItem": True})
        self.assertEqual(self._post_plan(with_specialty), 200)


if __name__ == "__main__":
    unittest.main()
