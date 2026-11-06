"""Error paths log metadata only and never return exception text (LTC 1.3 privacy review).

Run from LTC_AI_Gateway:
  PYTHONPATH=. .venv/bin/python -m unittest tests.test_error_logging_privacy -v

No network: Gemini is simulated at httpx.AsyncClient.post (so the real _post_gemini /
_post_gemini_text error messages, which quote upstream bodies and model text, are produced)
or at the route's call_gemini_* function. Every failure carries private markers: item text,
owner notes, model output and an API-key-like string. The tests check every log record
(message and any attached traceback) and every response body for those markers.
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
os.environ["LTC_AI_PER_MINUTE_LIMIT"] = "500"
os.environ["LTC_AI_PER_DAY_LIMIT"] = "5000"

import httpx  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
from app.routes import analyze_item_photo as route  # noqa: E402

PRIVATE_ITEM = "Grandma Pz-Okafor's ruby brooch"
PRIVATE_NOTES = "Kept in the safe at 41 Hidden Lane; Qx-private-note"
MODEL_TEXT = "Mx-model-output says the owner is Pz-Okafor at 41 Hidden Lane"
KEYLIKE = "AIzaSyQq-fake-key-material-1234567890"
MARKERS = ["Pz-Okafor", "Hidden Lane", "Qx-private-note", "Mx-model-output", KEYLIKE, "test-dummy-key"]
AUDIO_B64 = base64.b64encode(b"\x00\x00\x00\x18ftypM4A ").decode()

BRIEF_REQUEST = {
    "schemaVersion": 1, "scope": "item", "title": PRIVATE_ITEM, "description": PRIVATE_NOTES,
    "category": "Jewelry", "quantity": 1, "unitValue": 900, "currencyCode": "USD",
    "inputs": {"goal": "balanced"},
}


def _gemini_ok(text: str, finish: str = "STOP") -> dict:
    return {"candidates": [{"content": {"parts": [{"text": text}], "role": "model"}, "finishReason": finish}],
            "usageMetadata": {"promptTokenCount": 10, "candidatesTokenCount": 5}}


class _Upstream:
    """httpx.AsyncClient.post replacement returning queued (status, body) pairs."""

    def __init__(self, *responses):
        self.responses = list(responses)
        self.calls = 0

    async def __call__(self, url, json=None, **_kw):  # noqa: A002
        self.calls += 1
        status, body = self.responses.pop(0) if len(self.responses) > 1 else self.responses[0]
        req = httpx.Request("POST", url)
        if isinstance(body, str):
            return httpx.Response(status, text=body, request=req)
        return httpx.Response(status, json=body, request=req)


def _upstream_error_body() -> dict:
    # What a Gemini 4xx/5xx body could echo: our prompt (item text, notes) and a key.
    return {"error": {"code": 400, "message": f"bad request for '{PRIVATE_ITEM}' ({PRIVATE_NOTES}) key={KEYLIKE}"}}


class _PrivacyCase(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        # raise_server_exceptions=True: an exception escaping to Starlette would fail the test.
        cls.client = TestClient(main.app, raise_server_exceptions=True)

    def _post(self, path: str, body: dict, *, upstream=None, patches=()):
        ctx = [mock.patch.object(httpx.AsyncClient, "post", upstream)] if upstream else []
        ctx += list(patches)
        with self.assertLogs(level=logging.DEBUG) as captured:
            for c in ctx:
                c.start()
            try:
                r = self.client.post(path, json=body, headers={"X-LTC-Device-ID": f"privacy-{uuid.uuid4()}"})
            finally:
                for c in reversed(ctx):
                    c.stop()
        return r, captured.records

    def assertClean(self, r, records, *, status: int, event: str | None = None, stage: str | None = None):
        self.assertEqual(r.status_code, status, r.text)
        for marker in MARKERS:
            self.assertNotIn(marker, r.text, f"response leaks {marker!r}")
        self.assertEqual(r.json()["error"]["message"],
                         "Upstream service error." if status != 500 else "Internal server error.")
        for rec in records:
            self.assertIsNone(rec.exc_info, f"traceback logged by {rec.name}: {rec.getMessage()[:120]}")
            text = rec.getMessage()
            for marker in MARKERS:
                self.assertNotIn(marker, text, f"log line leaks {marker!r}: {text[:160]}")
            self.assertNotIn("Traceback", text)
            self.assertNotIn("raw_text_preview", text)
        if event:
            events = [json.loads(rec.getMessage()) for rec in records
                      if rec.getMessage().startswith("{") and f'"event": "{event}"' in rec.getMessage()]
            self.assertTrue(events, f"no {event} line")
            self.assertTrue(all(isinstance(e.get("errorType"), str) for e in events))
            if stage:
                self.assertIn(stage, [e.get("stage") for e in events])
        return records


class AudioSummaryErrorTests(_PrivacyCase):

    def _audio(self, upstream):
        return self._post("/ai/summarize-audio",
                          {"audioBase64": AUDIO_B64, "mimeType": "audio/mp4", "itemName": PRIVATE_ITEM,
                           "additionalContext": PRIVATE_NOTES}, upstream=upstream)

    def test_upstream_error_body_with_private_text_is_not_logged_or_returned(self):
        up = _Upstream((400, _upstream_error_body()))
        r, records = self._audio(up)
        self.assertClean(r, records, status=502, event="audio_summary.failed", stage="gemini")
        self.assertEqual(up.calls, 2)                       # the existing single retry is unchanged

    def test_missing_text_and_truncation_stay_metadata_only(self):
        r, records = self._audio(_Upstream((200, {"candidates": [{"finishReason": "SAFETY"}], "note": MODEL_TEXT})))
        self.assertClean(r, records, status=502, event="audio_summary.failed")
        r, records = self._audio(_Upstream((200, _gemini_ok(MODEL_TEXT + " and then", "MAX_TOKENS"))))
        self.assertClean(r, records, status=502, event="audio_summary.failed")

    def test_success_is_unchanged(self):
        r, _ = self._audio(_Upstream((200, _gemini_ok("Owner notes the brooch was a wedding gift."))))
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json(), {"summaryText": "Owner notes the brooch was a wedding gift."})


class LiquidationBriefErrorTests(_PrivacyCase):

    def _brief(self, upstream=None, patches=()):
        return self._post("/ai/generate-liquidation-brief", BRIEF_REQUEST, upstream=upstream, patches=patches)

    def test_upstream_error_is_metadata_only(self):
        r, records = self._brief(_Upstream((500, _upstream_error_body())))
        self.assertClean(r, records, status=502, event="liquidation_brief.failed", stage="gemini")

    def test_non_json_model_output_preview_is_not_logged(self):
        # _post_gemini raises "...raw_text_preview='<model text>'" after its retry.
        r, records = self._brief(_Upstream((200, _gemini_ok(f"Sorry, {MODEL_TEXT}, {PRIVATE_NOTES}"))))
        self.assertClean(r, records, status=502, event="liquidation_brief.failed", stage="gemini")

    def test_failed_schema_repair_does_not_log_validation_text(self):
        # A pydantic ValidationError quotes the offending values (model output, item text).
        bad = mock.patch.object(route, "_normalize_liquidation_brief_obj",
                                side_effect=lambda raw_json, request: {"schemaVersion": "x", "reasoning": MODEL_TEXT,
                                                                       "pathOptions": PRIVATE_NOTES})
        r, records = self._brief(_Upstream((200, _gemini_ok("{}"))), patches=[bad])
        self.assertClean(r, records, status=502, event="liquidation_brief.failed", stage="repair")

    def test_unexpected_normalization_error_is_metadata_only(self):
        boom = mock.patch.object(route, "_normalize_liquidation_brief_obj",
                                 side_effect=KeyError(f"{PRIVATE_ITEM} {MODEL_TEXT}"))
        r, records = self._brief(_Upstream((200, _gemini_ok("{}"))), patches=[boom])
        self.assertClean(r, records, status=502, event="liquidation_brief.failed", stage="validation")


class LiquidationPlanErrorTests(_PrivacyCase):

    def _plan(self, stub_outputs=None, raises=None):
        from tests.test_liquidation_plan_v2 import V1_REQUEST
        queue = list(stub_outputs or [])

        async def stub(*, prompt: str) -> str:
            if raises:
                raise raises
            return queue.pop(0)
        return self._post("/ai/generate-liquidation-plan", V1_REQUEST,
                          patches=[mock.patch.object(route, "call_gemini_for_liquidation_plan", stub)])

    def test_gemini_error_text_is_not_returned_or_logged(self):
        r, records = self._plan(raises=RuntimeError(f"Gemini error 400: {PRIVATE_NOTES} raw_text_preview='{MODEL_TEXT}'"))
        self.assertClean(r, records, status=502, event="liquidation_plan.failed", stage="gemini")

    def test_unrepairable_output_is_metadata_only(self):
        r, records = self._plan([f"not json {MODEL_TEXT}", json.dumps({"items": [{"text": "   "}], "focus": MODEL_TEXT})])
        self.assertClean(r, records, status=502, event="liquidation_plan.failed", stage="repair")


class UnhandledErrorTests(_PrivacyCase):

    def test_any_unhandled_route_error_logs_type_only(self):
        # An exception no route handles (here in prompt building) must not reach Starlette,
        # which would log its traceback and message.
        boom = mock.patch.object(route, "_build_liquidation_brief_prompt",
                                 side_effect=ValueError(f"cannot format {PRIVATE_ITEM}: {PRIVATE_NOTES}"))
        r, records = self._post("/ai/generate-liquidation-brief", BRIEF_REQUEST, patches=[boom])
        self.assertClean(r, records, status=500, event="request.unhandled")
        line = next(json.loads(x.getMessage()) for x in records if '"request.unhandled"' in x.getMessage())
        self.assertEqual((line["errorType"], line["path"]), ("ValueError", "/ai/generate-liquidation-brief"))
        self.assertTrue(r.headers.get("X-Request-ID"))


class SourceAuditTests(unittest.TestCase):
    """The route module must not reintroduce content-bearing logging or details."""

    def test_no_exception_logging_or_raw_details_in_ai_routes(self):
        with open(route.__file__, encoding="utf-8") as fh:
            src = fh.read()
        self.assertNotIn("logger.exception", src)
        self.assertNotIn("exc_info", src)
        self.assertNotIn('detail=str(exc)) from exc\n', src.replace("status_code=422, detail=str(exc)) from exc\n", ""))
        self.assertNotIn("JSON from Gemini: {", src)


if __name__ == "__main__":
    unittest.main()
