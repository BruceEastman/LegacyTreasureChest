"""Item analysis: "itemName" / "name" accepted as the title without a repair call.

Run from LTC_AI_Gateway/:
    .venv/bin/python -m unittest tests.test_item_title_alias -v

Gemini is never called: the route's Gemini functions are stubbed and count their calls.
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
from app.ai.normalization.item_analysis import _normalize_item_analysis_json  # noqa: E402
from app.routes import analyze_item_photo as route  # noqa: E402
from app.services import gemini_client  # noqa: E402

TINY_JPEG_B64 = base64.b64encode(b"\xff\xd8\xff\xd9").decode()
BASE = {
    "description": "A carved wooden four-poster bed frame.",
    "category": "Furniture",
    "valueHints": {"valueLow": 150, "estimatedValue": 300, "valueHigh": 600, "currencyCode": "USD"},
}


def _answer(**fields) -> str:
    obj = dict(BASE)
    for key, value in fields.items():
        if value is ...:
            obj.pop(key, None)
        else:
            obj[key] = value
    return json.dumps(obj)


async def _no_network(*_args, **_kwargs):
    raise AssertionError("Tests must not call Gemini over the network.")


class _Gemini:
    """Stub for call_gemini_for_item_analysis / ..._text_analysis: returns answers in order, counts calls."""

    def __init__(self, *answers: str):
        self.answers = list(answers)
        self.prompts = []

    async def __call__(self, *, prompt: str, image_base64: str | None = None) -> str:
        self.prompts.append(prompt)
        return self.answers.pop(0)


def _title(raw: str):
    return json.loads(_normalize_item_analysis_json(raw)).get("title")


class TitleAliasNormalizerTests(unittest.TestCase):
    def test_valid_title_is_left_byte_for_byte(self):
        raw = _answer(title="Four-Poster Bed")
        self.assertEqual(_normalize_item_analysis_json(raw), raw)

    def test_item_name_fills_missing_title(self):
        self.assertEqual(_title(_answer(itemName="Carved Four-Poster Bed")), "Carved Four-Poster Bed")

    def test_name_fills_missing_title(self):
        self.assertEqual(_title(_answer(name="Carved Four-Poster Bed")), "Carved Four-Poster Bed")

    def test_alias_whitespace_is_trimmed(self):
        self.assertEqual(_title(_answer(itemName="  Bar Stool \n")), "Bar Stool")

    def test_valid_title_wins_over_conflicting_aliases(self):
        self.assertEqual(_title(_answer(title="Four-Poster Bed", itemName="Sleigh Bed", name="Crib")), "Four-Poster Bed")

    def test_null_or_blank_title_is_filled(self):
        self.assertEqual(_title(_answer(title=None, itemName="Bar Stool")), "Bar Stool")
        self.assertEqual(_title(_answer(title="  ", name="Bar Stool")), "Bar Stool")

    def test_matching_aliases_are_accepted(self):
        self.assertEqual(_title(_answer(itemName="Bar Stool", name=" Bar Stool ")), "Bar Stool")

    def test_conflicting_aliases_are_not_guessed(self):
        self.assertNotIn("title", json.loads(_normalize_item_analysis_json(_answer(itemName="Bar Stool", name="Stool"))))

    def test_empty_or_invalid_aliases_are_not_used(self):
        for alias in ("", "   ", None, 42, ["Bar Stool"], {"text": "Bar Stool"}):
            with self.subTest(alias=alias):
                raw = _answer(itemName=alias)
                self.assertEqual(_normalize_item_analysis_json(raw), raw)

    def test_non_string_title_is_not_replaced(self):
        raw = _answer(title=["Bar Stool"], itemName="Bar Stool")
        self.assertEqual(_normalize_item_analysis_json(raw), raw)

    def test_only_top_level_keys_are_used(self):
        raw = _answer(valueHints={"name": "Bar Stool", "currencyCode": "USD"})
        self.assertEqual(_normalize_item_analysis_json(raw), raw)

    def test_unparseable_or_non_object_json_is_unchanged(self):
        for raw in ("not json", "[1, 2]", '"Bar Stool"', ""):
            with self.subTest(raw=raw):
                self.assertEqual(_normalize_item_analysis_json(raw), raw)

    def test_existing_item_title_and_summary_mapping_still_apply(self):
        raw = json.dumps({"itemTitle": "Bar Stool", "summary": "A stool.", "category": "Furniture"})
        obj = json.loads(_normalize_item_analysis_json(raw))
        self.assertEqual((obj["title"], obj["description"]), ("Bar Stool", "A stool."))


class PhotoRouteRepairCallTests(unittest.TestCase):
    """/ai/analyze-item-photo: Gemini call counts with and without a usable title."""

    @classmethod
    def setUpClass(cls):
        cls._net_patch = mock.patch.object(gemini_client, "_post_gemini", _no_network)
        cls._net_patch.start()
        cls.client = TestClient(main.app)

    @classmethod
    def tearDownClass(cls):
        cls._net_patch.stop()

    def _post(self, gemini: _Gemini, device: str):
        with mock.patch.object(route, "call_gemini_for_item_analysis", gemini):
            return self.client.post(
                "/ai/analyze-item-photo",
                json={"imageJpegBase64": TINY_JPEG_B64},
                headers={"X-LTC-Device-ID": device},
            )

    def _assert_one_call_with_title(self, first: str, expected: str, device: str):
        gemini = _Gemini(first)
        r = self._post(gemini, device)
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body["title"], expected)
        self.assertEqual(len(gemini.prompts), 1)
        # The response shape is unchanged: aliases never reach the app.
        self.assertNotIn("itemName", body)
        self.assertNotIn("name", body)

    def test_valid_title_needs_one_call(self):
        self._assert_one_call_with_title(_answer(title="Four-Poster Bed"), "Four-Poster Bed", "alias-title")

    def test_item_name_needs_one_call(self):
        self._assert_one_call_with_title(_answer(itemName="Carved Four-Poster Bed"), "Carved Four-Poster Bed", "alias-itemname")

    def test_name_needs_one_call(self):
        self._assert_one_call_with_title(_answer(name="Carved Four-Poster Bed"), "Carved Four-Poster Bed", "alias-name")

    def test_title_wins_over_conflicting_alias(self):
        self._assert_one_call_with_title(_answer(title="Four-Poster Bed", itemName="Sleigh Bed"), "Four-Poster Bed", "alias-conflict")

    def _assert_repaired(self, first: str, device: str):
        gemini = _Gemini(first, _answer(title="Repaired Bed"))
        r = self._post(gemini, device)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["title"], "Repaired Bed")
        self.assertEqual(len(gemini.prompts), 2)
        self.assertIn("title", gemini.prompts[1])  # the repair prompt carries the validation error

    def test_no_title_or_alias_still_repairs(self):
        self._assert_repaired(_answer(), "alias-none")

    def test_blank_alias_still_repairs(self):
        self._assert_repaired(_answer(itemName="   "), "alias-blank")

    def test_conflicting_aliases_still_repair(self):
        self._assert_repaired(_answer(itemName="Sleigh Bed", name="Crib"), "alias-ambiguous")

    def test_other_missing_field_still_repairs(self):
        self._assert_repaired(_answer(itemName="Carved Bed", description=...), "alias-nodesc")

    def test_malformed_twice_still_returns_502(self):
        gemini = _Gemini("not json", "still not json")
        r = self._post(gemini, "alias-malformed")
        self.assertEqual(r.status_code, 502, r.text)
        self.assertEqual(len(gemini.prompts), 2)

    def test_alias_with_bad_repair_still_returns_502(self):
        gemini = _Gemini(_answer(itemName="Carved Bed", category=...), _answer(name="Still no category", category=...))
        r = self._post(gemini, "alias-badrepair")
        self.assertEqual(r.status_code, 502, r.text)
        self.assertEqual(len(gemini.prompts), 2)


class TextRouteTitleTests(unittest.TestCase):
    """/ai/analyze-item-text shares the normalizer; it has no repair call."""

    @classmethod
    def setUpClass(cls):
        cls._net_patch = mock.patch.object(gemini_client, "_post_gemini", _no_network)
        cls._net_patch.start()
        cls.client = TestClient(main.app)

    @classmethod
    def tearDownClass(cls):
        cls._net_patch.stop()

    def _post(self, answer: str, device: str):
        gemini = _Gemini(answer)
        with mock.patch.object(route, "call_gemini_for_item_text_analysis", gemini):
            r = self.client.post(
                "/ai/analyze-item-text",
                json={"title": "Bed", "description": "Carved wood", "category": "Furniture"},
                headers={"X-LTC-Device-ID": device},
            )
        self.assertEqual(len(gemini.prompts), 1)
        return r

    def test_item_name_is_accepted(self):
        r = self._post(_answer(itemName="Carved Four-Poster Bed"), "text-alias")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["title"], "Carved Four-Poster Bed")

    def test_missing_title_without_alias_still_fails(self):
        r = self._post(_answer(), "text-none")
        self.assertEqual(r.status_code, 502, r.text)


if __name__ == "__main__":
    unittest.main()
