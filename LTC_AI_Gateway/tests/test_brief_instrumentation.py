"""Liquidation Brief latency instrumentation: per-attempt Gemini logs and one result line.

Run from LTC_AI_Gateway:
  PYTHONPATH=. .venv/bin/python -m unittest tests.test_brief_instrumentation -v

No network: httpx.AsyncClient.post is replaced with canned generateContent responses, so the
real _post_gemini (retry logic included) runs. Checks that the logs carry timing, token and
finish-reason metadata, correlate by request id, distinguish item from set Briefs and repair
from initial calls, and never contain prompts, model text, item details or the API key.
"""
from __future__ import annotations

import json
import os
import unittest
import uuid
from unittest import mock

os.environ.setdefault("GEMINI_API_KEY", "test-dummy-key")
os.environ["LTC_DISABLE_ALL_AI"] = "false"
os.environ["LTC_DISABLE_GEMINI"] = "false"

import httpx  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
from app.services import gemini_client  # noqa: E402

SECRET_TITLE = "Grandmother's Zz-unique-marker pendant"
SECRET_DESC = "Kept in the hall closet; Qq-private-detail"
MODEL_TEXT_MARKER = "Mm-model-reasoning-marker"

ITEM_REQUEST = {
    "schemaVersion": 1, "scope": "item", "title": SECRET_TITLE, "description": SECRET_DESC,
    "category": "Jewelry", "quantity": 1, "unitValue": 900, "currencyCode": "USD",
    "valuationLow": 700, "valuationLikely": 900, "valuationHigh": 1100, "inputs": {"goal": "balanced"},
}
SET_REQUEST = {
    "schemaVersion": 1, "scope": "set", "title": SECRET_TITLE, "category": "China/Dinnerware",
    "quantity": 40, "currencyCode": "USD", "inputs": {"goal": "balanced"},
}


def _option(path, label):
    return {"id": str(uuid.uuid4()), "path": path, "label": label, "effort": "medium", "risks": []}


def _brief_text() -> str:
    return json.dumps({
        "schemaVersion": 1, "scope": "item", "generatedAt": "2026-11-04T00:00:00Z",
        "recommendedPath": "pathB_delegateConsign", "reasoning": MODEL_TEXT_MARKER,
        "pathOptions": [_option("pathA_maximizePrice", "Sell it yourself"),
                        _option("pathB_delegateConsign", "Consign it"),
                        _option("pathC_quickExit", "Quick sale")],
        "actionSteps": ["Step one"],
    })


def _resp(text: str, finish="STOP", thinking=1500, out=900, prompt=1100) -> dict:
    return {
        "candidates": [{"content": {"parts": [{"text": text}], "role": "model"}, "finishReason": finish}],
        "usageMetadata": {"promptTokenCount": prompt, "candidatesTokenCount": out,
                          "thoughtsTokenCount": thinking, "totalTokenCount": prompt + out + thinking},
        "modelVersion": "gemini-3.6-flash",
    }


class _FakePost:
    def __init__(self, *bodies):
        self.bodies = list(bodies)
        self.calls = 0

    async def __call__(self, url, json=None, **kw):  # noqa: A002
        self.calls += 1
        body = self.bodies.pop(0) if len(self.bodies) > 1 else self.bodies[0]
        return httpx.Response(200, json=body, request=httpx.Request("POST", url))


class BriefInstrumentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(main.app)

    def _post(self, request: dict, *bodies):
        fake = _FakePost(*bodies)
        rid = f"test-{uuid.uuid4()}"
        with mock.patch.object(httpx.AsyncClient, "post", fake), \
                self.assertLogs(level="INFO") as logs:
            r = self.client.post("/ai/generate-liquidation-brief", json=request,
                                 headers={"X-Request-ID": rid, "X-LTC-Device-ID": f"dev-{uuid.uuid4()}"})
        events = []
        for line in logs.output:
            msg = line.split(":", 2)[-1]
            try:
                obj = json.loads(msg)
            except ValueError:
                continue
            if isinstance(obj, dict) and obj.get("event") in ("gemini.attempt", "liquidation_brief.result",
                                                              "liquidation_brief.repair"):
                events.append(obj)
        return r, rid, events, logs.output, fake

    def _of(self, events, name):
        return [e for e in events if e["event"] == name]

    def test_clean_item_brief_logs_one_attempt_and_result(self):
        r, rid, events, _, fake = self._post(ITEM_REQUEST, _resp(_brief_text()))
        self.assertEqual(r.status_code, 200, r.text)
        attempts = self._of(events, "gemini.attempt")
        self.assertEqual(len(attempts), 1)
        a = attempts[0]
        self.assertEqual((a["requestId"], a["operation"], a["scope"], a["phase"], a["attempt"]),
                         (rid, "liquidation_brief", "item", "initial", 1))
        self.assertEqual((a["finishReason"], a["promptTokens"], a["outputTokens"], a["thinkingTokens"], a["totalTokens"]),
                         ("STOP", 1100, 900, 1500, 3500))
        self.assertEqual((a["httpStatus"], a["jsonValid"], a["outcome"], a["willRetry"], a["maxOutputTokens"]),
                         (200, True, "ok", False, 8192))
        self.assertIsInstance(a["latencyMs"], int)
        self.assertGreater(a["responseChars"], 0)
        res = self._of(events, "liquidation_brief.result")
        self.assertEqual(len(res), 1)
        self.assertEqual((res[0]["requestId"], res[0]["scope"], res[0]["outcome"], res[0]["httpStatus"],
                          res[0]["repairAttempted"], res[0]["hasPhoto"]), (rid, "item", "ok", 200, False, False))
        self.assertIsInstance(res[0]["totalMs"], int)

    def test_truncated_answer_is_not_resent_identically(self):
        cut = _brief_text()[:300]  # JSON cut off mid-object, as at the output limit
        r, rid, events, _, fake = self._post(ITEM_REQUEST, _resp(cut, "MAX_TOKENS", thinking=7400, out=792))
        self.assertEqual(r.status_code, 502)
        self.assertEqual(fake.calls, 1)  # correction: no identical retry after MAX_TOKENS
        attempts = self._of(events, "gemini.attempt")
        self.assertEqual([(a["attempt"], a["finishReason"], a["outcome"], a["jsonValid"], a["willRetry"], a["maxOutputTokens"])
                          for a in attempts], [(1, "MAX_TOKENS", "invalid_json", False, False, 8192)])
        self.assertEqual(attempts[0]["textParts"], 1)
        self.assertTrue(attempts[0]["jsonOpenBrackets"] > 0 or attempts[0]["jsonEndsInString"])
        res = self._of(events, "liquidation_brief.result")[0]
        self.assertEqual((res["outcome"], res["httpStatus"], res["requestId"]), ("error", 502, rid))

    def test_malformed_but_complete_answer_still_gets_one_retry(self):
        malformed = '{"schemaVersion": 1, "pathOptions": [],}'
        r, _, events, _, fake = self._post(ITEM_REQUEST, _resp(malformed), _resp(_brief_text()))
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(fake.calls, 2)  # unchanged: a non-truncation failure is retried once
        self.assertEqual([a["willRetry"] for a in self._of(events, "gemini.attempt")], [True, False])

    def test_complete_but_malformed_json_is_distinguished_from_cut_off(self):
        malformed = '{"schemaVersion": 1, "reasoning": "x", "pathOptions": [],}'  # trailing comma, all closed
        r, _, events, _, _ = self._post(ITEM_REQUEST, _resp(malformed), _resp(malformed))
        self.assertEqual(r.status_code, 502)
        a = self._of(events, "gemini.attempt")[0]
        self.assertEqual((a["outcome"], a["finishReason"], a["jsonOpenBrackets"], a["jsonEndsInString"]),
                         ("invalid_json", "STOP", 0, False))
        self.assertLess(a["jsonErrorPos"], 1.0)

    def test_schema_repair_is_logged_as_repair_phase(self):
        wrong_schema = json.dumps({"reasoning": MODEL_TEXT_MARKER})  # valid JSON, fails the DTO
        r, rid, events, _, fake = self._post(ITEM_REQUEST, _resp(wrong_schema), _resp(_brief_text()))
        self.assertEqual(r.status_code, 200, r.text)
        attempts = self._of(events, "gemini.attempt")
        self.assertEqual([(a["phase"], a["outcome"]) for a in attempts], [("initial", "ok"), ("repair", "ok")])
        rep = self._of(events, "liquidation_brief.repair")
        self.assertEqual(len(rep), 1)
        self.assertEqual((rep[0]["requestId"], rep[0]["reason"]), (rid, "schema_validation"))
        self.assertTrue(self._of(events, "liquidation_brief.result")[0]["repairAttempted"])

    def test_set_brief_scope_is_recorded(self):
        r, rid, events, _, _ = self._post(SET_REQUEST, _resp(_brief_text()))
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual({e["scope"] for e in events}, {"set"})

    def test_logs_never_contain_prompt_model_text_item_details_or_key(self):
        _, _, _, out1, _ = self._post(ITEM_REQUEST, _resp(_brief_text()))
        _, _, _, out2, _ = self._post(ITEM_REQUEST, _resp(_brief_text()[:300], "MAX_TOKENS"))
        new_lines = [l for l in out1 + out2 if "gemini.attempt" in l or "liquidation_brief." in l]
        self.assertTrue(new_lines)
        blob = "\n".join(new_lines)
        for secret in (SECRET_TITLE, "Zz-unique-marker", "Qq-private-detail", MODEL_TEXT_MARKER,
                       gemini_client.GEMINI_API_KEY, "pathOptions", "You are"):
            self.assertNotIn(secret, blob)

    def test_context_is_cleared_after_the_request(self):
        self._post(ITEM_REQUEST, _resp(_brief_text()))
        self.assertIsNone(gemini_client.GEMINI_LOG_CONTEXT.get())


class OtherEndpointsUnchangedTests(unittest.TestCase):
    """Plan and other routes do not set the context, so they emit no gemini.attempt lines."""

    def test_plan_still_retries_identically_after_truncation(self):
        import asyncio
        fake = _FakePost(_resp('{"items": [', "MAX_TOKENS"), _resp('{"ok": true}'))
        with mock.patch.object(httpx.AsyncClient, "post", fake):
            out = asyncio.run(gemini_client.call_gemini_for_liquidation_plan(prompt="p"))
        self.assertEqual(fake.calls, 2)  # default behavior kept for every non-Brief caller
        self.assertIn("ok", out)

    def test_plan_route_emits_no_attempt_logs(self):
        plan = json.dumps({"schemaVersion": 2, "createdAt": "2026-11-04T00:00:00Z",
                           "items": [{"order": 1, "text": "Clean it"}, {"order": 2, "text": "List it"},
                                     {"order": 3, "text": "Sell it"}]})
        req = {"schemaVersion": 1, "scope": "item", "chosenPath": "pathC_quickExit", "title": "Lamp",
               "category": "Decor", "brief": json.loads(_brief_text())}
        client = TestClient(main.app)
        fake = _FakePost(_resp(plan))
        with mock.patch.object(httpx.AsyncClient, "post", fake), self.assertLogs(level="INFO") as logs:
            r = client.post("/ai/generate-liquidation-plan", json=req, headers={"X-LTC-Device-ID": f"p-{uuid.uuid4()}"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(fake.calls, 1)  # the Plan really called (stubbed) Gemini
        self.assertFalse([l for l in logs.output if "gemini.attempt" in l or "liquidation_brief." in l])

    def test_post_gemini_without_context_logs_no_attempts(self):
        import asyncio
        with mock.patch.object(httpx.AsyncClient, "post", _FakePost(_resp('{"ok": true}'))), \
                self.assertLogs(level="DEBUG") as logs:
            gemini_client.logger.debug("sentinel")
            asyncio.run(gemini_client._post_gemini({"contents": []}))
        self.assertFalse([l for l in logs.output if "gemini.attempt" in l])

    def test_transport_error_is_logged_and_still_raised(self):
        import asyncio

        async def boom(*a, **k):
            raise httpx.ConnectTimeout("timed out")

        token = gemini_client.GEMINI_LOG_CONTEXT.set({"requestId": "r1", "operation": "liquidation_brief",
                                                      "scope": "item", "phase": "initial"})
        try:
            with mock.patch.object(httpx.AsyncClient, "post", boom), self.assertLogs(level="INFO") as logs:
                with self.assertRaises(httpx.ConnectTimeout):
                    asyncio.run(gemini_client._post_gemini({"contents": []}))
        finally:
            gemini_client.GEMINI_LOG_CONTEXT.reset(token)
        line = [l for l in logs.output if "gemini.attempt" in l]
        self.assertEqual(len(line), 1)
        self.assertIn('"outcome": "transport_error"', line[0])


if __name__ == "__main__":
    unittest.main()
