"""Gemini 3.6 Flash migration: request settings and truncated-summary handling.

Run from LTC_AI_Gateway:
  PYTHONPATH=. .venv/bin/python -m unittest tests.test_gemini_client_payloads -v

No network: Gemini is stubbed either at the payload boundary (_post_gemini / _post_gemini_text)
or at httpx.AsyncClient.post with canned generateContent responses.
"""
from __future__ import annotations

import asyncio
import base64
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

import httpx  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
from app.services import gemini_client  # noqa: E402

UNSUPPORTED_3X_PARAMS = {"temperature", "topP", "topK"}
TINY_AUDIO_B64 = base64.b64encode(b"\x00\x00\x00\x18ftypM4A ").decode()


def _run(coro):
    return asyncio.run(coro)


def _capture(target_name: str):
    """Patch a low-level poster and return the list that collects each payload sent to it."""
    sent = []

    async def _stub(payload):
        sent.append(payload)
        return '{"ok": true}' if target_name == "_post_gemini" else "Owner notes it."

    return sent, mock.patch.object(gemini_client, target_name, _stub)


def _gemini_response(text: str, finish_reason: str = "STOP") -> dict:
    return {
        "candidates": [{
            "content": {"parts": [{"text": text}], "role": "model"},
            "finishReason": finish_reason,
        }],
        "usageMetadata": {"promptTokenCount": 10, "candidatesTokenCount": 5},
    }


class _FakePost:
    """Replaces httpx.AsyncClient.post; returns queued generateContent bodies and counts calls."""

    def __init__(self, *bodies: dict):
        self.bodies = list(bodies)
        self.calls = 0

    async def __call__(self, url, json=None, **_kw):  # noqa: A002  (patched on the class: no self binding)
        self.calls += 1
        body = self.bodies.pop(0) if len(self.bodies) > 1 else self.bodies[0]
        return httpx.Response(200, json=body, request=httpx.Request("POST", url))


class DefaultModelTests(unittest.TestCase):
    def test_default_model_is_gemini_3_6_flash(self):
        src = open(gemini_client.__file__, encoding="utf-8").read()
        self.assertIn('os.getenv("GEMINI_MODEL", "gemini-3.6-flash")', src)


class PayloadSettingsTests(unittest.TestCase):
    """Every request builder omits parameters that 3.x models ignore and future models reject."""

    def _assert_clean(self, payload: dict, max_tokens: int):
        cfg = payload["generationConfig"]
        self.assertFalse(UNSUPPORTED_3X_PARAMS & set(cfg), cfg)
        self.assertEqual(cfg["maxOutputTokens"], max_tokens)

    def test_item_analysis_photo(self):
        sent, patch = _capture("_post_gemini")
        with patch:
            _run(gemini_client.call_gemini_for_item_analysis(prompt="p", image_base64="AAAA"))
        self._assert_clean(sent[0], 4096)

    def test_item_analysis_text(self):
        sent, patch = _capture("_post_gemini")
        with patch:
            _run(gemini_client.call_gemini_for_item_text_analysis(prompt="p"))
        self._assert_clean(sent[0], 4096)

    def test_liquidation_brief(self):
        sent, patch = _capture("_post_gemini")
        with patch:
            _run(gemini_client.call_gemini_for_liquidation_brief(prompt="p", photo_base64="AAAA"))
        self._assert_clean(sent[0], 4096)

    def test_liquidation_plan(self):
        sent, patch = _capture("_post_gemini")
        with patch:
            _run(gemini_client.call_gemini_for_liquidation_plan(prompt="p"))
        self._assert_clean(sent[0], 4096)

    def test_audio_summary_has_room_for_thinking(self):
        sent, patch = _capture("_post_gemini_text")
        with patch:
            _run(gemini_client.call_gemini_for_audio_summary(prompt="p", audio_base64="AAAA", mime_type="audio/mp4"))
        self._assert_clean(sent[0], 1024)


class TruncatedTextTests(unittest.TestCase):
    """_post_gemini_text must never return a reply that was cut off at the output limit."""

    def test_complete_reply_is_returned(self):
        fake = _FakePost(_gemini_response("Owner notes the quilt was made by Ruth in 1940."))
        with mock.patch.object(httpx.AsyncClient, "post", fake):
            text = _run(gemini_client._post_gemini_text({"contents": []}))
        self.assertEqual(text, "Owner notes the quilt was made by Ruth in 1940.")
        self.assertEqual(fake.calls, 1)

    def test_truncated_reply_is_retried_once_then_rejected(self):
        fake = _FakePost(_gemini_response("The owner notes this quilt was made by their", "MAX_TOKENS"))
        with mock.patch.object(httpx.AsyncClient, "post", fake):
            with self.assertRaises(RuntimeError) as ctx:
                _run(gemini_client._post_gemini_text({"contents": []}))
        self.assertIn("truncated", str(ctx.exception))
        self.assertEqual(fake.calls, 2)

    def test_truncated_then_complete_succeeds_on_retry(self):
        fake = _FakePost(
            _gemini_response("The owner notes this", "MAX_TOKENS"),
            _gemini_response("Owner notes the watch belonged to their father."),
        )
        with mock.patch.object(httpx.AsyncClient, "post", fake):
            text = _run(gemini_client._post_gemini_text({"contents": []}))
        self.assertEqual(text, "Owner notes the watch belonged to their father.")
        self.assertEqual(fake.calls, 2)


class SummarizeAudioRouteTests(unittest.TestCase):
    """The iOS contract is unchanged: 200 {summaryText} on success, existing 5xx envelope on failure."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(main.app)

    def _post(self, fake: _FakePost):
        with mock.patch.object(httpx.AsyncClient, "post", fake):
            return self.client.post(
                "/ai/summarize-audio",
                json={"audioBase64": TINY_AUDIO_B64, "mimeType": "audio/mp4", "itemName": "Quilt"},
                headers={"X-LTC-Device-ID": "test-audio-device"},
            )

    def test_complete_summary_returns_200_with_summary_text_only(self):
        r = self._post(_FakePost(_gemini_response("Owner notes the quilt was made by Ruth in Iowa.")))
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json(), {"summaryText": "Owner notes the quilt was made by Ruth in Iowa."})

    def test_truncated_summary_returns_existing_upstream_error(self):
        r = self._post(_FakePost(_gemini_response("The owner notes this quilt was made by their", "MAX_TOKENS")))
        self.assertEqual(r.status_code, 502, r.text)
        body = r.json()
        self.assertNotIn("summaryText", body)
        self.assertEqual(body.get("message") or body.get("error", {}).get("message"), "Upstream service error.")


if __name__ == "__main__":
    unittest.main()
