"""LTC 1.3 Stage 3: supplementary evidence, source-labeled context and safe
logging for item analysis.

Run from LTC_AI_Gateway/:
    .venv/bin/python -m unittest tests.test_item_analysis_evidence -v

Gemini is never called: the route's Gemini function (or the low-level poster)
is stubbed per test, and the network helper fails loudly. All media is
synthetic bytes with a JPEG signature.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import unittest
import uuid
from unittest import mock

os.environ["GEMINI_API_KEY"] = "test-dummy-key"
os.environ["LTC_DISABLE_ALL_AI"] = "false"
os.environ["LTC_DISABLE_GEMINI"] = "false"
os.environ["LTC_ANALYZE_PER_MINUTE_LIMIT"] = "1000"
os.environ["LTC_AI_PER_MINUTE_LIMIT"] = "1000"
os.environ["LTC_AI_PER_DAY_LIMIT"] = "100000"

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
from app.ai import evidence as ev  # noqa: E402
from app.ai.prompts import item_analysis as prompts  # noqa: E402
from app.models import ItemAIHints  # noqa: E402
from app.routes import analyze_item_photo as route  # noqa: E402
from app.services import gemini_client  # noqa: E402


def _jpeg(tag: str, size: int = 64) -> str:
    raw = b"\xff\xd8\xff\xe0" + tag.encode() + b"\x00" * max(0, size - 4 - len(tag)) + b"\xff\xd9"
    return base64.b64encode(raw).decode()


PRIMARY = _jpeg("primary")
SECRET = "OWNER-NAME-Jane-Q-Example-123 Main St"


def _valid_analysis(**extra) -> str:
    obj = {
        "title": "Counter stool",
        "description": "A wooden counter stool.",
        "category": "Furniture",
        "brand": "Sample Maker Co.",
        "valueHints": {"valueLow": 100, "estimatedValue": 150, "valueHigh": 200, "currencyCode": "USD",
                       "confidenceScore": 0.6, "aiNotes": "n", "missingDetails": []},
    }
    obj.update(extra)
    return json.dumps(obj)


class _Recorder:
    """Stub for route.call_gemini_for_item_analysis that records each call."""

    def __init__(self, *responses: str):
        self.responses = list(responses)
        self.calls: list[dict] = []

    async def __call__(self, **kwargs):
        self.calls.append(kwargs)
        return self.responses.pop(0)


async def _no_network(*_a, **_k):
    raise AssertionError("Tests must not call Gemini over the network.")


def _photo(tag: str) -> dict:
    return {"kind": "photo", "mimeType": "image/jpeg", "dataBase64": _jpeg(tag)}


def _page(page: int, pages: int, doc: int = 1, tag: str = "page") -> dict:
    return {"kind": "documentPage", "mimeType": "image/jpeg", "dataBase64": _jpeg(f"{tag}{page}"),
            "documentIndex": doc, "page": page, "pageCount": pages}


CONTEXT = {
    "quantity": 4,
    "ownerNotes": "Stamp under the seat reads Sample Maker Co.",
    "savedDescription": [
        {"origin": "priorAI", "text": "Cherry counter stool with a cutout back."},
        {"origin": "owner", "text": "Bought new in 2007."},
    ],
    "priorAttributes": {"materials": "cherry", "brand": "Sample Maker Co."},
}


class _RouteCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._net = mock.patch.object(gemini_client, "_post_gemini", _no_network)
        cls._net.start()
        cls.client = TestClient(main.app)

    @classmethod
    def tearDownClass(cls):
        cls._net.stop()

    def post(self, body: dict, recorder: _Recorder, path: str = "/ai/analyze-item-photo"):
        target = "call_gemini_for_item_analysis" if path.endswith("photo") else "call_gemini_for_item_text_analysis"
        with mock.patch.object(route, target, recorder):
            return self.client.post(path, json=body, headers={"X-LTC-Device-ID": f"t-{uuid.uuid4()}"})


# ---------------------------------------------------------------------------
# Compatibility with LTC 1.2 requests
# ---------------------------------------------------------------------------

class LegacyRequestTests(_RouteCase):

    def test_v1_request_uses_unchanged_prompt_and_call(self):
        hints = {"userWrittenTitle": "Stool", "userWrittenDescription": "Old text", "knownCategory": "Furniture"}
        rec = _Recorder(_valid_analysis())
        r = self.post({"imageJpegBase64": PRIMARY, "hints": hints}, rec)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(len(rec.calls), 1)
        # Exactly the 1.2 call: prompt + image_base64, nothing else.
        self.assertEqual(set(rec.calls[0]), {"prompt", "image_base64"})
        self.assertEqual(rec.calls[0]["prompt"], prompts.build_item_analysis_prompt(ItemAIHints(**hints)))
        body = r.json()
        self.assertIsNone(body.get("inputSummary"))
        self.assertEqual(body["brand"], "Sample Maker Co.")

    def test_v1_missing_image_is_a_clear_400(self):
        r = self.post({"hints": {"userWrittenTitle": "x"}}, _Recorder())
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["error"]["code"], "NO_INPUT")

    def test_v1_bad_base64_unchanged(self):
        r = self.post({"imageJpegBase64": "not base64!!"}, _Recorder())
        self.assertEqual(r.status_code, 400)

    def test_v1_gemini_payload_is_single_image(self):
        sent = []

        async def _capture(payload, **kwargs):
            sent.append((payload, kwargs))
            return _valid_analysis()

        with mock.patch.object(gemini_client, "_post_gemini", _capture):
            r = self.client.post("/ai/analyze-item-photo", json={"imageJpegBase64": PRIMARY},
                                 headers={"X-LTC-Device-ID": "t-v1-payload"})
        self.assertEqual(r.status_code, 200, r.text)
        parts = sent[0][0]["contents"][0]["parts"]
        self.assertEqual(len(parts), 2)
        self.assertIn("text", parts[0])
        self.assertEqual(parts[1]["inline_data"]["data"], PRIMARY)
        self.assertEqual(sent[0][0]["generationConfig"]["maxOutputTokens"], 4096)
        self.assertTrue(sent[0][1].get("retry_on_truncation", True))

    def test_v1_text_endpoint_prompt_unchanged(self):
        rec = _Recorder(_valid_analysis())
        r = self.post({"hints": {"userWrittenTitle": "Lamp", "userWrittenDescription": "Brass", "knownCategory": "Decor"}},
                      rec, path="/ai/analyze-item-text")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(rec.calls[0]["prompt"], prompts.build_item_analysis_text_prompt("Lamp", "Brass", "Decor"))
        self.assertIsNone(r.json().get("inputSummary"))


# ---------------------------------------------------------------------------
# 1.3 requests: context, evidence order and labels, processing metadata
# ---------------------------------------------------------------------------

class EvidenceRequestTests(_RouteCase):

    def test_context_only_request_uses_v2_prompt_and_reports_counts(self):
        rec = _Recorder(_valid_analysis(valuationUnit="one stool"))
        r = self.post({"imageJpegBase64": PRIMARY, "hints": {"userWrittenTitle": "Stools"}, "context": CONTEXT}, rec)
        self.assertEqual(r.status_code, 200, r.text)
        call = rec.calls[0]
        self.assertEqual(call["evidence"], [])
        self.assertEqual(call["image_base64"], PRIMARY)
        self.assertFalse(call["retry_on_truncation"])
        prompt = call["prompt"]
        self.assertIn("QUANTITY = 4", prompt)
        self.assertIn("OWNER-PROVIDED NOTES", prompt)
        self.assertIn("EARLIER AI-GENERATED DESCRIPTION", prompt)
        self.assertIn("OWNER-WRITTEN DESCRIPTION", prompt)
        self.assertNotIn("ADDITIONAL EVIDENCE", prompt)
        summary = r.json()["inputSummary"]
        self.assertEqual(summary, {
            "contractVersion": 2, "primaryPhoto": True, "supplementaryPhotos": 0, "documents": 0,
            "documentPages": 0, "quantity": 4, "ownerNotes": True, "savedDescriptionParts": 2,
            "priorAttributes": 2,
        })
        self.assertEqual(r.json()["valuationUnit"], "one stool")

    def test_photos_and_pages_keep_order_and_labels(self):
        rec = _Recorder(_valid_analysis())
        supp = [_photo("p1"), _photo("p2"), _page(1, 3), _page(2, 3), _page(3, 3), _photo("p3")]
        r = self.post({"imageJpegBase64": PRIMARY, "context": CONTEXT, "supplementary": supp}, rec)
        self.assertEqual(r.status_code, 200, r.text)
        labels = [label for label, _ in rec.calls[0]["evidence"]]
        self.assertEqual(labels, [
            "Supplementary photo 1:", "Supplementary photo 2:",
            "Supporting document 1, page 1 of 3:", "Supporting document 1, page 2 of 3:",
            "Supporting document 1, page 3 of 3:", "Supplementary photo 3:",
        ])
        self.assertEqual([d for _, d in rec.calls[0]["evidence"]], [s["dataBase64"] for s in supp])
        prompt = rec.calls[0]["prompt"]
        self.assertIn("The first image after these instructions is the primary photo", prompt)
        self.assertIn("not current resale values", prompt)
        summary = r.json()["inputSummary"]
        self.assertEqual((summary["supplementaryPhotos"], summary["documents"], summary["documentPages"]), (3, 1, 3))

    def test_truncated_document_is_stated_in_prompt(self):
        rec = _Recorder(_valid_analysis())
        supp = [_page(p, 12) for p in range(1, 11)]
        r = self.post({"imageJpegBase64": PRIMARY, "supplementary": supp}, rec)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIn("Only the first 10 of 12 pages of supporting document 1", rec.calls[0]["prompt"])
        self.assertEqual(rec.calls[0]["evidence"][-1][0], "Supporting document 1, page 10 of 12:")

    def test_evidence_without_primary_photo(self):
        rec = _Recorder(_valid_analysis())
        r = self.post({"context": {"quantity": 1}, "supplementary": [_page(1, 1)]}, rec)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIsNone(rec.calls[0]["image_base64"])
        self.assertIn("There is no primary photo of the item.", rec.calls[0]["prompt"])
        self.assertFalse(r.json()["inputSummary"]["primaryPhoto"])

    def test_gemini_parts_order_with_evidence(self):
        sent = []

        async def _capture(payload, **kwargs):
            sent.append(payload)
            return _valid_analysis()

        supp = [_photo("p1"), _page(1, 2), _page(2, 2)]
        with mock.patch.object(gemini_client, "_post_gemini", _capture):
            r = self.client.post("/ai/analyze-item-photo",
                                 json={"imageJpegBase64": PRIMARY, "context": CONTEXT, "supplementary": supp},
                                 headers={"X-LTC-Device-ID": "t-parts"})
        self.assertEqual(r.status_code, 200, r.text)
        parts = sent[0]["contents"][0]["parts"]
        kinds = ["text" if "text" in p else "image" for p in parts]
        self.assertEqual(kinds, ["text", "image", "text", "image", "text", "image", "text", "image"])
        self.assertEqual(parts[1]["inline_data"]["data"], PRIMARY)
        self.assertEqual(parts[2]["text"], "Supplementary photo 1:")
        self.assertEqual(parts[4]["text"], "Supporting document 1, page 1 of 2:")
        for p in parts:
            if "inline_data" in p:
                self.assertEqual(p["inline_data"]["mime_type"], "image/jpeg")

    def test_repair_call_keeps_all_evidence(self):
        bad = json.dumps({"title": "x", "category": "Furniture"})  # missing description
        rec = _Recorder(bad, _valid_analysis())
        supp = [_photo("p1"), _page(1, 1)]
        r = self.post({"imageJpegBase64": PRIMARY, "context": CONTEXT, "supplementary": supp}, rec)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(len(rec.calls), 2)
        self.assertEqual(rec.calls[1]["evidence"], rec.calls[0]["evidence"])
        self.assertEqual(rec.calls[1]["image_base64"], PRIMARY)
        self.assertIn("did not validate".upper(), rec.calls[1]["prompt"].upper())

    def test_model_supplied_input_summary_is_replaced_and_fields_coerced(self):
        rec = _Recorder(_valid_analysis(inputSummary={"supplementaryPhotos": 99}, conflicts="Stamp says oak",
                                        modelNumber=9785, valuationUnit="  one stool  "))
        r = self.post({"imageJpegBase64": PRIMARY, "supplementary": [_photo("p1")]}, rec)
        body = r.json()
        self.assertEqual(body["inputSummary"]["supplementaryPhotos"], 1)
        self.assertEqual(body["conflicts"], ["Stamp says oak"])
        self.assertEqual(body["modelNumber"], "9785")
        self.assertEqual(body["valuationUnit"], "one stool")

    def test_text_endpoint_with_context(self):
        rec = _Recorder(_valid_analysis())
        r = self.post({"hints": {"userWrittenTitle": "Lamp", "knownCategory": "Decor"},
                       "context": {"quantity": 2, "ownerNotes": "Pair of lamps"}}, rec, path="/ai/analyze-item-text")
        self.assertEqual(r.status_code, 200, r.text)
        prompt = rec.calls[0]["prompt"]
        self.assertIn("QUANTITY = 2", prompt)
        self.assertIn("No photo is available", prompt)
        self.assertEqual(r.json()["inputSummary"]["quantity"], 2)


# ---------------------------------------------------------------------------
# Rejections: clear codes, nothing echoed
# ---------------------------------------------------------------------------

class EvidenceRejectionTests(_RouteCase):

    def _reject(self, body: dict, code: str, status: int = 400):
        rec = _Recorder()
        r = self.post(body, rec)
        self.assertEqual(r.status_code, status, r.text)
        self.assertEqual(r.json()["error"]["code"], code)
        self.assertEqual(rec.calls, [], "Gemini must not be called for a rejected request")
        # No evidence data is echoed.
        for item in body.get("supplementary") or []:
            data = item.get("dataBase64")
            if isinstance(data, str) and len(data) > 8:
                self.assertNotIn(data, r.text)
        return r

    def test_too_many_photos(self):
        r = self._reject({"imageJpegBase64": PRIMARY, "supplementary": [_photo(f"p{i}") for i in range(4)]},
                         "EVIDENCE_TOO_MANY_PHOTOS")
        self.assertEqual(r.json()["error"]["details"]["evidenceIndex"], 3)

    def test_too_many_documents(self):
        self._reject({"imageJpegBase64": PRIMARY, "supplementary": [_page(1, 1, doc=1), _page(1, 1, doc=2)]},
                     "EVIDENCE_TOO_MANY_DOCUMENTS")

    def test_too_many_pages(self):
        self._reject({"imageJpegBase64": PRIMARY, "supplementary": [_page(p, 11) for p in range(1, 12)]},
                     "EVIDENCE_TOO_MANY_PAGES")

    def test_pages_out_of_order_or_gaps(self):
        self._reject({"imageJpegBase64": PRIMARY, "supplementary": [_page(2, 3), _page(1, 3)]}, "EVIDENCE_PAGE_ORDER")
        self._reject({"imageJpegBase64": PRIMARY, "supplementary": [_page(1, 3), _page(3, 3)]}, "EVIDENCE_PAGE_ORDER")

    def test_page_details_invalid(self):
        bad = _page(1, 2)
        bad.pop("page")
        self._reject({"imageJpegBase64": PRIMARY, "supplementary": [bad]}, "EVIDENCE_INVALID_PAGE")
        self._reject({"imageJpegBase64": PRIMARY, "supplementary": [_page(3, 2)]}, "EVIDENCE_INVALID_PAGE")
        self._reject({"imageJpegBase64": PRIMARY, "supplementary": [_page(1, 2), _page(2, 3)]},
                     "EVIDENCE_INVALID_PAGE")

    def test_unsupported_kind_and_type(self):
        self._reject({"imageJpegBase64": PRIMARY,
                      "supplementary": [{"kind": "pdf", "mimeType": "image/jpeg", "dataBase64": _jpeg("x")}]},
                     "EVIDENCE_UNSUPPORTED_KIND")
        self._reject({"imageJpegBase64": PRIMARY,
                      "supplementary": [{"kind": "photo", "mimeType": "application/pdf", "dataBase64": _jpeg("x")}]},
                     "EVIDENCE_UNSUPPORTED_TYPE")

    def test_bad_base64_and_non_jpeg(self):
        self._reject({"imageJpegBase64": PRIMARY,
                      "supplementary": [{"kind": "photo", "mimeType": "image/jpeg", "dataBase64": "%%%not-b64%%%"}]},
                     "EVIDENCE_INVALID_BASE64")
        png = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 40).decode()
        self._reject({"imageJpegBase64": PRIMARY,
                      "supplementary": [{"kind": "photo", "mimeType": "image/jpeg", "dataBase64": png}]},
                     "EVIDENCE_INVALID_IMAGE")
        self._reject({"imageJpegBase64": PRIMARY,
                      "supplementary": [{"kind": "photo", "mimeType": "image/jpeg", "dataBase64": ""}]},
                     "EVIDENCE_MISSING_DATA")

    def test_primary_must_be_jpeg_when_evidence_present(self):
        png = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 40).decode()
        self._reject({"imageJpegBase64": png, "supplementary": [_photo("p1")]}, "EVIDENCE_INVALID_IMAGE")

    def test_oversized_item_and_total(self):
        with mock.patch.object(ev, "MAX_EVIDENCE_IMAGE_BYTES", 200):
            self._reject({"imageJpegBase64": PRIMARY,
                          "supplementary": [{"kind": "photo", "mimeType": "image/jpeg",
                                             "dataBase64": _jpeg("big", 500)}]},
                         "EVIDENCE_TOO_LARGE", status=413)
        with mock.patch.object(ev, "MAX_EVIDENCE_TOTAL_BYTES", 300):
            self._reject({"imageJpegBase64": PRIMARY,
                          "supplementary": [{"kind": "photo", "mimeType": "image/jpeg", "dataBase64": _jpeg(f"p{i}", 150)}
                                            for i in range(3)]},
                         "EVIDENCE_TOTAL_TOO_LARGE", status=413)

    def test_no_input_at_all(self):
        self._reject({"context": {"quantity": 1}}, "NO_INPUT")

    def test_invalid_context(self):
        self._reject({"imageJpegBase64": PRIMARY, "context": {"quantity": 0}}, "INVALID_CONTEXT")
        self._reject({"imageJpegBase64": PRIMARY,
                      "context": {"savedDescription": [{"origin": "gemini", "text": "x"}]}}, "INVALID_CONTEXT")
        self._reject({"imageJpegBase64": PRIMARY, "context": {"priorAttributes": {"ownerName": "x"}}},
                     "INVALID_CONTEXT")

    def test_request_size_guard(self):
        with mock.patch("app.middleware.request_context.MAX_ANALYZE_REQUEST_BYTES", 1000):
            r = self.client.post("/ai/analyze-item-photo",
                                 json={"imageJpegBase64": _jpeg("big", 2000)},
                                 headers={"X-LTC-Device-ID": "t-size"})
        self.assertEqual(r.status_code, 413)
        self.assertEqual(r.json()["error"]["code"], "PAYLOAD_TOO_LARGE")

    def test_schema_error_does_not_echo_input(self):
        r = self.client.post("/ai/analyze-item-photo",
                             json={"imageJpegBase64": PRIMARY, "context": {"ownerNotes": {"name": SECRET}}},
                             headers={"X-LTC-Device-ID": "t-422"})
        self.assertEqual(r.status_code, 422)
        self.assertNotIn(SECRET, r.text)


# ---------------------------------------------------------------------------
# Prompt content: provenance, per-unit valuation, privacy
# ---------------------------------------------------------------------------

class PromptV2Tests(unittest.TestCase):

    def _prompt(self, quantity=1, **kw):
        from app.models import ItemAnalysisContext
        return prompts.build_item_analysis_prompt_v2(
            ItemAIHints(userWrittenTitle="Item"), ItemAnalysisContext(quantity=quantity, **kw),
            has_primary=True, has_evidence=False)

    def test_per_unit_rules(self):
        p = self._prompt(quantity=4)
        self.assertIn("QUANTITY = 4", p)
        self.assertIn("for ONE unit, never for the whole quantity", p)
        self.assertIn("value one of the identical units", p)
        self.assertIn("value the complete set", p)
        self.assertIn('"valuationUnit"', p)

    def test_resale_basis_and_value_rules_retained(self):
        p = self._prompt().lower()
        for phrase in ("current secondary-market resale", "conservative", "original retail",
                       "never substitute a generic or typical range for the category"):
            self.assertIn(phrase, p)

    def test_privacy_and_evidence_rules(self):
        p = self._prompt()
        self.assertIn("Do not include personal names", p)
        self.assertIn("lab-report", p)
        self.assertIn("Manufacturer model, reference and pattern numbers are not personal", p)
        self.assertIn("Do not invent components", p)
        self.assertIn("brand, modelNumber", p)

    def test_prior_ai_is_labeled_unverified(self):
        from app.models import SavedDescriptionPart
        p = self._prompt(savedDescription=[SavedDescriptionPart(origin="priorAI", text="Solid cherry.")],
                         priorAttributes={"materials": "cherry"})
        self.assertIn("EARLIER AI-GENERATED DESCRIPTION (accepted by the owner but NOT verified)", p)
        self.assertIn("EARLIER AI-IDENTIFIED DETAILS (NOT verified", p)
        self.assertIn("Do not present earlier AI-generated statements as the owner's facts", p)

    def test_legacy_description_without_labels_is_unverified(self):
        from app.models import ItemAnalysisContext
        p = prompts.build_item_analysis_prompt_v2(
            ItemAIHints(userWrittenDescription="Mixed old text"), ItemAnalysisContext(quantity=1),
            has_primary=True, has_evidence=False)
        self.assertIn("SAVED DESCRIPTION (may mix", p)
        self.assertIn("Mixed old text", p)

    def test_v1_prompts_are_unchanged_by_v2(self):
        # The v1 builder does not contain any 1.3-only wording.
        p = prompts.build_item_analysis_prompt(ItemAIHints(userWrittenTitle="x"))
        for marker in ("QUANTITY =", "OWNER-PROVIDED NOTES", "PRIVACY RULES", "valuationUnit"):
            self.assertNotIn(marker, p)


# ---------------------------------------------------------------------------
# Logging: metadata only, never model text, evidence or item text
# ---------------------------------------------------------------------------

class SafeLoggingTests(_RouteCase):

    def _logs_for(self, body: dict, stub, path="/ai/analyze-item-photo") -> tuple[str, int]:
        target = "call_gemini_for_item_analysis" if path.endswith("photo") else "call_gemini_for_item_text_analysis"
        with self.assertLogs(level=logging.DEBUG) as captured, mock.patch.object(route, target, stub):
            r = self.client.post(path, json=body, headers={"X-LTC-Device-ID": "t-log"})
        return "\n".join(captured.output), r.status_code

    def test_gemini_failure_logs_no_model_text(self):
        async def _fail(**_kw):
            raise RuntimeError(f"Gemini returned non-JSON. raw_text_preview='{SECRET}'")

        for body in ({"imageJpegBase64": PRIMARY},
                     {"imageJpegBase64": PRIMARY, "context": CONTEXT, "supplementary": [_page(1, 1)]}):
            logs, status = self._logs_for(body, _fail)
            self.assertEqual(status, 502)
            self.assertNotIn(SECRET, logs)
            self.assertIn("item_analysis.failed", logs)
            self.assertIn("RuntimeError", logs)

    def test_repair_failure_logs_no_model_text(self):
        bad = json.dumps({"title": SECRET, "category": "Furniture"})
        for body in ({"imageJpegBase64": PRIMARY},
                     {"imageJpegBase64": PRIMARY, "context": CONTEXT, "supplementary": [_photo("p1")]}):
            logs, status = self._logs_for(body, _Recorder(bad, bad))
            self.assertEqual(status, 502)
            self.assertNotIn(SECRET, logs)
            self.assertNotIn("Cherry counter stool", logs)
            self.assertIn('"stage": "repair"', logs)

    def test_logs_never_contain_evidence_or_context_text(self):
        body = {"imageJpegBase64": PRIMARY, "context": dict(CONTEXT, ownerNotes=SECRET),
                "supplementary": [_photo("p1"), _page(1, 1)]}
        logs, status = self._logs_for(body, _Recorder(_valid_analysis()))
        self.assertEqual(status, 200)
        self.assertNotIn(SECRET, logs)
        for item in body["supplementary"]:
            self.assertNotIn(item["dataBase64"], logs)
        self.assertNotIn(PRIMARY, logs)

    def test_text_endpoint_failure_logs_no_model_text(self):
        async def _fail(**_kw):
            raise RuntimeError(f"raw_text_preview='{SECRET}'")

        logs, status = self._logs_for({"hints": {"userWrittenTitle": "x"}, "context": {"quantity": 1}},
                                      _fail, path="/ai/analyze-item-text")
        self.assertEqual(status, 502)
        self.assertNotIn(SECRET, logs)

    def test_unexpected_error_is_logged_without_its_message(self):
        """A bug inside the handler (not a Gemini failure) must not put its
        exception message, which could quote item text, into logs or the body."""
        def _boom(*_a, **_k):
            raise ValueError(f"unexpected {SECRET}")

        client = TestClient(main.app, raise_server_exceptions=False)
        for path, body, target in (
            ("/ai/analyze-item-photo", {"imageJpegBase64": PRIMARY, "context": CONTEXT}, "build_item_analysis_prompt_v2"),
            ("/ai/analyze-item-photo", {"imageJpegBase64": PRIMARY}, "build_item_analysis_prompt"),
            ("/ai/analyze-item-text", {"hints": {"userWrittenTitle": "x"}, "context": {"quantity": 1}},
             "build_item_analysis_text_prompt_v2"),
        ):
            with self.assertLogs(level=logging.DEBUG) as captured, mock.patch.object(route, target, _boom):
                r = client.post(path, json=body, headers={"X-LTC-Device-ID": "t-unexpected"})
            logs = "\n".join(captured.output)
            self.assertEqual(r.status_code, 500)
            self.assertNotIn(SECRET, logs)
            self.assertNotIn(SECRET, r.text)
            self.assertIn('"stage": "unexpected"', logs)
            self.assertIn("ValueError", logs)

    def test_error_body_never_contains_model_text(self):
        async def _fail(**_kw):
            raise RuntimeError(SECRET)

        with mock.patch.object(route, "call_gemini_for_item_analysis", _fail):
            r = self.client.post("/ai/analyze-item-photo", json={"imageJpegBase64": PRIMARY},
                                 headers={"X-LTC-Device-ID": "t-body"})
        self.assertEqual(r.status_code, 502)
        self.assertNotIn(SECRET, r.text)


if __name__ == "__main__":
    unittest.main()
