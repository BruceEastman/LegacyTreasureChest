"""Focused tests for item-analysis valuation prompts, value policy, and rate limiting.

Run from LTC_AI_Gateway/:
    .venv/bin/python -m unittest discover -s tests -v

Gemini is never called: the route's Gemini function is stubbed per test, and
the low-level HTTP helper is replaced with one that fails loudly.
"""

from __future__ import annotations

import base64
import json
import os
import unittest
from unittest import mock

# Pin the environment BEFORE importing the app. main.py calls load_dotenv(),
# which does not override variables that are already set.
os.environ["GEMINI_API_KEY"] = "test-dummy-key"
os.environ["LTC_DISABLE_ALL_AI"] = "false"
os.environ["LTC_DISABLE_GEMINI"] = "false"
os.environ["LTC_ANALYZE_PER_MINUTE_LIMIT"] = "10"
os.environ["LTC_AI_PER_MINUTE_LIMIT"] = "60"
os.environ["LTC_AI_PER_DAY_LIMIT"] = "200"

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
from app.ai.prompts import item_analysis as prompts  # noqa: E402
from app.core import config  # noqa: E402
from app.core.rate_limiter import InMemoryRateLimiter  # noqa: E402
from app.models import ItemAIHints  # noqa: E402
from app.routes import analyze_item_photo as route  # noqa: E402
from app.services import gemini_client  # noqa: E402

TINY_JPEG_B64 = base64.b64encode(b"\xff\xd8\xff\xd9").decode()

# Fields the shipping iOS app decodes (AIModels.swift). Non-optional in Swift:
REQUIRED_ITEM_KEYS = {"title", "description", "category"}  # "description" maps to Swift `summary`
REQUIRED_VALUE_HINT_KEYS = {"currencyCode"}
OPTIONAL_VALUE_HINT_NUMBERS = ("valueLow", "estimatedValue", "valueHigh", "confidenceScore")


async def _no_network(*_args, **_kwargs):
    raise AssertionError("Tests must not call Gemini over the network.")


def _gemini_returning(*responses: str):
    """Async stub that returns the given raw JSON strings in order."""
    queue = list(responses)

    async def _stub(*, prompt: str, image_base64: str) -> str:
        return queue.pop(0)

    return _stub


def _analysis_json(value_hints) -> str:
    obj = {
        "title": "Gold-tone wristwatch",
        "description": "A wristwatch with a gold-tone case and leather strap.",
        "category": "Luxury Personal Items",
    }
    if value_hints is not ...:
        obj["valueHints"] = value_hints
    return json.dumps(obj)


class ValuationPromptTests(unittest.TestCase):
    REQUIRED_PHRASES = (
        "CURRENT SECONDARY-MARKET RESALE",
        "typical private seller",
        "conservative",
        "range",
        "original retail",
        "replacement cost",
        "insurance value",
        "appraisal value",
        "Do not claim that specific",
    )

    def _assert_basis(self, prompt: str) -> None:
        for phrase in self.REQUIRED_PHRASES:
            self.assertIn(phrase.lower(), prompt.lower(), f"missing: {phrase}")

    def test_photo_prompt_states_resale_basis(self):
        self._assert_basis(prompts.build_item_analysis_prompt(None))

    def test_text_prompt_states_resale_basis(self):
        self._assert_basis(prompts.build_item_analysis_text_prompt("Watch", "Gold-tone watch", "Jewelry"))

    def test_repair_prompt_inherits_basis(self):
        original = prompts.build_item_analysis_prompt(None)
        repair = prompts._build_item_analysis_repair_prompt(
            original_prompt=original, raw_json="{}", validation_error="x"
        )
        self._assert_basis(repair)

    def test_prompts_allow_not_estimated_and_forbid_category_ranges(self):
        for prompt in (prompts.build_item_analysis_prompt(None),
                       prompts.build_item_analysis_text_prompt("t", "d", "c")):
            lowered = prompt.lower()
            self.assertIn("never substitute a generic or typical range for the category", lowered)
            self.assertIn("null", lowered)
            self.assertNotIn("do not return null for all value fields", lowered)
            self.assertNotIn('set "valuehints" to null', lowered)

    def test_prompts_keep_existing_contract(self):
        hints = ItemAIHints(
            userWrittenTitle="Omega Seamaster",
            userWrittenDescription="Reference number on case back",
            knownCategory="Luxury Personal Items",
        )
        photo = prompts.build_item_analysis_prompt(hints)
        self.assertIn("CATEGORY RULES (STRICT)", photo)
        self.assertIn("CRITICAL VALUE RULES", photo)
        self.assertIn("Omega Seamaster", photo)
        self.assertIn("Reference number on case back", photo)
        text = prompts.build_item_analysis_text_prompt("t", "d", "c")
        self.assertIn("Return JSON that matches this schema EXACTLY", text)


class ValuePolicyRouteTests(unittest.TestCase):
    """Exercise /ai/analyze-item-photo end to end with a stubbed Gemini."""

    @classmethod
    def setUpClass(cls):
        cls._net_patch = mock.patch.object(gemini_client, "_post_gemini", _no_network)
        cls._net_patch.start()
        cls.client = TestClient(main.app)

    @classmethod
    def tearDownClass(cls):
        cls._net_patch.stop()

    def _post(self, *gemini_responses: str, device: str):
        with mock.patch.object(route, "call_gemini_for_item_analysis", _gemini_returning(*gemini_responses)):
            return self.client.post(
                "/ai/analyze-item-photo",
                json={"imageJpegBase64": TINY_JPEG_B64},
                headers={"X-LTC-Device-ID": device},
            )

    def _assert_ios_compatible(self, body: dict) -> None:
        self.assertTrue(REQUIRED_ITEM_KEYS.issubset(body), body)
        for key in REQUIRED_ITEM_KEYS:
            self.assertIsInstance(body[key], str)
        vh = body.get("valueHints")
        if vh is not None:
            self.assertTrue(REQUIRED_VALUE_HINT_KEYS.issubset(vh), vh)
            self.assertIsInstance(vh["currencyCode"], str)
            for key in OPTIONAL_VALUE_HINT_NUMBERS:
                self.assertTrue(vh.get(key) is None or isinstance(vh[key], (int, float)), (key, vh.get(key)))
            md = vh.get("missingDetails")
            self.assertTrue(md is None or isinstance(md, list))

    def test_valid_range_is_returned_unchanged(self):
        r = self._post(
            _analysis_json({
                "valueLow": 120, "estimatedValue": 180, "valueHigh": 260,
                "currencyCode": "USD", "confidenceScore": 0.6,
                "aiNotes": "Conservative secondary-market resale estimate.",
                "missingDetails": ["Reference number"],
            }),
            device="valid-range",
        )
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        vh = body["valueHints"]
        self.assertEqual((vh["valueLow"], vh["estimatedValue"], vh["valueHigh"]), (120, 180, 260))
        self.assertEqual(vh["confidenceScore"], 0.6)
        self.assertEqual(vh["missingDetails"], ["Reference number"])
        self._assert_ios_compatible(body)

    def test_single_estimate_is_widened_to_range(self):
        r = self._post(
            _analysis_json({"estimatedValue": 100, "currencyCode": "USD", "confidenceScore": 0.5}),
            device="single-estimate",
        )
        self.assertEqual(r.status_code, 200, r.text)
        vh = r.json()["valueHints"]
        self.assertEqual((vh["valueLow"], vh["estimatedValue"], vh["valueHigh"]), (70.0, 100, 130.0))
        self._assert_ios_compatible(r.json())

    def test_partial_range_fills_estimate_from_bounds(self):
        r = self._post(
            _analysis_json({"valueLow": 40, "valueHigh": 60, "currencyCode": "USD"}),
            device="partial-range",
        )
        self.assertEqual(r.status_code, 200, r.text)
        vh = r.json()["valueHints"]
        self.assertEqual(vh["estimatedValue"], 50.0)
        self._assert_ios_compatible(r.json())

    def test_inverted_range_is_swapped(self):
        r = self._post(
            _analysis_json({"valueLow": 300, "estimatedValue": 200, "valueHigh": 100, "currencyCode": "USD"}),
            device="inverted-range",
        )
        self.assertEqual(r.status_code, 200, r.text)
        vh = r.json()["valueHints"]
        self.assertLessEqual(vh["valueLow"], vh["valueHigh"])
        self._assert_ios_compatible(r.json())

    def test_missing_currency_defaults_to_usd(self):
        r = self._post(
            _analysis_json({"valueLow": 10, "estimatedValue": 15, "valueHigh": 20, "currencyCode": ""}),
            device="no-currency",
        )
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["valueHints"]["currencyCode"], "USD")

    def test_malformed_json_after_repair_returns_502(self):
        r = self._post("not json at all", "still not json", device="malformed")
        self.assertEqual(r.status_code, 502, r.text)

    def _assert_not_estimated(self, body: dict) -> dict:
        vh = body["valueHints"]
        self.assertIsNone(vh["valueLow"])
        self.assertIsNone(vh["estimatedValue"])
        self.assertIsNone(vh["valueHigh"])
        self.assertLessEqual(vh["confidenceScore"], route._NOT_ESTIMATED_MAX_CONFIDENCE)
        self.assertTrue(vh["missingDetails"])
        self.assertEqual(vh["currencyCode"], "USD")
        self._assert_ios_compatible(body)
        return vh

    def test_missing_value_hints_are_not_estimated(self):
        r = self._post(_analysis_json(...), device="no-value-hints")
        self.assertEqual(r.status_code, 200, r.text)
        vh = self._assert_not_estimated(r.json())
        self.assertIn("not estimated", vh["aiNotes"].lower())

    def test_all_null_values_get_no_category_placeholder(self):
        # Every category, including those that previously had placeholder ranges.
        for category in ("Jewelry", "Luxury Personal Items", "Rug", "Furniture", "Other"):
            with self.subTest(category=category):
                obj = json.loads(_analysis_json({
                    "valueLow": None, "estimatedValue": None, "valueHigh": None,
                    "currencyCode": "USD", "confidenceScore": 0.9,
                }))
                obj["category"] = category
                r = self._post(json.dumps(obj), device=f"null-values-{category}")
                self.assertEqual(r.status_code, 200, r.text)
                self._assert_not_estimated(r.json())

    def test_ai_explanation_is_preserved_when_not_estimated(self):
        note = "Cannot tell whether this is gold or gold-tone from the photo."
        r = self._post(
            _analysis_json({"valueLow": None, "estimatedValue": None, "valueHigh": None,
                            "currencyCode": "USD", "aiNotes": note,
                            "missingDetails": ["Case-back markings"]}),
            device="null-with-note",
        )
        self.assertEqual(r.status_code, 200, r.text)
        vh = self._assert_not_estimated(r.json())
        self.assertEqual(vh["aiNotes"], note)
        self.assertEqual(vh["missingDetails"], ["Case-back markings"])

    def test_broad_low_confidence_range_is_preserved(self):
        r = self._post(
            _analysis_json({"valueLow": 20, "estimatedValue": 150, "valueHigh": 900,
                            "currencyCode": "USD", "confidenceScore": 0.2}),
            device="broad-range",
        )
        self.assertEqual(r.status_code, 200, r.text)
        vh = r.json()["valueHints"]
        self.assertEqual((vh["valueLow"], vh["estimatedValue"], vh["valueHigh"]), (20, 150, 900))
        self.assertEqual(vh["confidenceScore"], 0.2)

    def test_explicit_zero_estimate_is_kept(self):
        r = self._post(
            _analysis_json({"valueLow": 0, "estimatedValue": 0, "valueHigh": 0, "currencyCode": "USD"}),
            device="explicit-zero",
        )
        self.assertEqual(r.status_code, 200, r.text)
        vh = r.json()["valueHints"]
        self.assertEqual((vh["valueLow"], vh["estimatedValue"], vh["valueHigh"]), (0, 0, 0))

    def test_category_placeholder_table_is_gone(self):
        self.assertFalse(hasattr(route, "_CATEGORY_FALLBACKS"))
        self.assertFalse(hasattr(route, "_fallback_for_category"))

    def test_text_only_missing_value_is_not_estimated(self):
        async def _text_stub(*, prompt: str) -> str:
            return _analysis_json(None)

        with mock.patch.object(route, "call_gemini_for_item_text_analysis", _text_stub):
            r = self.client.post(
                "/ai/analyze-item-text",
                json={"title": "Watch", "description": "Gold-tone watch", "category": "Luxury Personal Items"},
                headers={"X-LTC-Device-ID": "text-null"},
            )
        self.assertEqual(r.status_code, 200, r.text)
        self._assert_not_estimated(r.json())


class DispositionValueBandTests(unittest.TestCase):
    """An unknown value must not be routed as a known low value."""

    @classmethod
    def setUpClass(cls):
        matrix = route._load_disposition_matrix()
        scenarios = matrix.get("scenarios", matrix if isinstance(matrix, list) else [])
        cls.when = {s["id"]: s.get("when", {}) for s in scenarios}

    def _matches(self, scenario_id: str, category: str, band):
        from app.models_disposition import DispositionPartnersSearchRequest, DispositionScenarioDTO
        bulky = category == "Furniture"
        req = DispositionPartnersSearchRequest.model_construct(
            chosenPath="B",
            scenario=DispositionScenarioDTO(category=category, valueBand=band, bulky=bulky, goal="balanced"),
        )
        return route._scenario_matches(self.when[scenario_id], req)

    def test_unknown_band_matches_luxury_and_furniture_scenarios(self):
        self.assertTrue(self._matches("jewelry_luxury_high_value", "Luxury Personal Items", "UNKNOWN"))
        self.assertTrue(self._matches("jewelry_luxury_high_value", "Jewelry", None))
        self.assertTrue(self._matches("furniture_bulky_med_balanced", "Furniture", "UNKNOWN"))

    def test_known_low_band_keeps_existing_behavior(self):
        self.assertFalse(self._matches("jewelry_luxury_high_value", "Jewelry", "LOW"))
        self.assertFalse(self._matches("furniture_bulky_med_balanced", "Furniture", "LOW"))
        self.assertTrue(self._matches("jewelry_luxury_high_value", "Jewelry", "HIGH"))

    def test_unknown_band_does_not_bypass_category(self):
        self.assertFalse(self._matches("jewelry_luxury_high_value", "Furniture", "UNKNOWN"))


class RateLimiterTests(unittest.TestCase):
    def test_limit_blocks_after_n_and_rejections_are_not_counted(self):
        limiter = InMemoryRateLimiter()
        kwargs = dict(device_id="d1", scope="analyze-item-photo", limit=10, window_seconds=60)
        results = [limiter.check(**kwargs)[0] for _ in range(10)]
        self.assertTrue(all(results))
        allowed, retry = limiter.check(**kwargs)
        self.assertFalse(allowed)
        self.assertGreaterEqual(retry, 1)
        # A rejected request does not consume a slot.
        self.assertEqual(limiter._store[("d1", "analyze-item-photo")][0], 10)

    def test_window_reset_allows_retry(self):
        limiter = InMemoryRateLimiter()
        kwargs = dict(device_id="d2", scope="s", limit=2, window_seconds=60)
        with mock.patch.object(limiter, "_now", return_value=1000.0):
            limiter.check(**kwargs)
            limiter.check(**kwargs)
            self.assertFalse(limiter.check(**kwargs)[0])
        with mock.patch.object(limiter, "_now", return_value=1061.0):
            self.assertTrue(limiter.check(**kwargs)[0])

    def test_devices_are_isolated(self):
        limiter = InMemoryRateLimiter()
        for _ in range(3):
            limiter.check(device_id="a", scope="s", limit=3, window_seconds=60)
        self.assertFalse(limiter.check(device_id="a", scope="s", limit=3, window_seconds=60)[0])
        self.assertTrue(limiter.check(device_id="b", scope="s", limit=3, window_seconds=60)[0])

    def test_configured_limits(self):
        self.assertEqual(config.ANALYZE_PER_MINUTE_LIMIT, 10)
        self.assertEqual(config.AI_PER_MINUTE_LIMIT, 60)
        self.assertEqual(config.AI_PER_DAY_LIMIT, 200)


class RateLimitMiddlewareTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._net_patch = mock.patch.object(gemini_client, "_post_gemini", _no_network)
        cls._net_patch.start()
        cls.client = TestClient(main.app)

    @classmethod
    def tearDownClass(cls):
        cls._net_patch.stop()

    def _batch(self, n: int, device: str):
        ok = _analysis_json({"valueLow": 1, "estimatedValue": 2, "valueHigh": 3, "currencyCode": "USD"})
        with mock.patch.object(route, "call_gemini_for_item_analysis", _gemini_returning(*([ok] * n))):
            return [
                self.client.post(
                    "/ai/analyze-item-photo",
                    json={"imageJpegBase64": TINY_JPEG_B64},
                    headers={"X-LTC-Device-ID": device},
                ).status_code
                for _ in range(n)
            ]

    def test_twenty_photo_batch_hits_default_limit(self):
        codes = self._batch(20, device="batch-default")
        self.assertEqual(codes[:10], [200] * 10)
        self.assertEqual(codes[10:], [429] * 10)

    def test_twenty_photo_batch_fits_under_25(self):
        from app.middleware import request_context
        with mock.patch.object(request_context, "ANALYZE_PER_MINUTE_LIMIT", 25):
            codes = self._batch(20, device="batch-25")
        self.assertEqual(codes, [200] * 20)


if __name__ == "__main__":
    unittest.main()
