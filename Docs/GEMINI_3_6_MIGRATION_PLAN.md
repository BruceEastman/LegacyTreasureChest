# Gemini 3.6 Flash Migration Plan (rev 2)

**Status:** Code prepared and validated locally on branch `gemini-3-6-migration`. No production changes. Each deployment stage needs Bruce's separate authorization.
**Date:** 2026-11-03
**Deadline:** 2026-12-01, when Google routes `gemini-2.5-flash` to `gemini-3.5-flash-lite`.
**Target:** both stages complete before 2026-11-17.
**Decision basis:** blind review on 2026-11-03. 3.6 Flash was preferred on 19 of 21 items over 2.5 Flash, which had been preferred over 3.5 Flash-Lite.

## 1. Changes (branch `gemini-3-6-migration`, from `main` at 36cd4c2)

`LTC_AI_Gateway/app/services/gemini_client.py`:
- Default `GEMINI_MODEL` is now `gemini-3.6-flash`. Cloud Run still sets it explicitly.
- `temperature`, `topP` and `topK` are removed from all four request builders. 3.x models ignore them and future models reject them.
- Audio `maxOutputTokens` is raised from 256 to 1024.
- `_post_gemini_text` (used only by `/ai/summarize-audio`) rejects a reply whose `finishReason` is `MAX_TOKENS`. The existing single retry applies, then the route returns its existing 502. iOS already retries a 502 once, then shows "Create AI Summary Again".
- JSON `maxOutputTokens` stays at 4,096, as directed (see section 3).

`LTC_AI_Gateway/tests/test_gemini_client_payloads.py` (new, 11 tests):
- default model
- no 3.x-unsupported parameters in any request
- output limits (4,096 for JSON, 1,024 for audio)
- complete, truncated, and truncated-then-complete replies
- `/ai/summarize-audio` returns 200 `{summaryText}` and keeps the existing 502 envelope

Unchanged:
- routes, prompts, Pydantic models, rate limits, iOS
- iOS-facing contracts. The only visible difference is that `aiProvider` and `aiModel` read `gemini-3.6-flash`.

## 2. Test and validation results

**Automated tests:** 175 of 175 pass (164 existing and 11 new).

**Harness validation** of the branch code (run `migration_rc1`, 62 live calls, $0.39):

| | 3.6 Flash (Stage 2 config) | 2.5 Flash (Stage 1 config) |
|---|---|---|
| Responses OK | 31 of 31 | 31 of 31 |
| Check failures | 0 | 0 |
| Truncated answers | 0 | 0 |
| Audio summaries complete | 4 of 4 | 4 of 4 (all 4 were cut off before the fix) |
| Typical / slowest response | 10.4 s / 17.8 s | 10.7 s / 15.8 s |
| Photo repair calls | 10 of 18 (12 of 18 before) | 18 of 18 (unchanged) |

- **3.6 Flash:**
  - Titles, categories and value ranges match the approved `flash36` run within normal run-to-run variation. Removing the ignored parameters changed nothing material.
  - The fly rod is now filed as Other, as you specified.
- **2.5 Flash:** without `temperature: 0.2` it uses Google's default sampling.
  - Answers stayed correct but varied more: for example, it did not name Noritake this time, and some value ranges came out lower.
  - This applies only between Stage 1 and Stage 2, so Stage 2 should follow promptly.

## 3. Your specific checks

**Audio summaries and the 320-character limit:**
- All 8 validation summaries were complete, one or two sentences, 187 to 262 characters. None reached the 320-character trim.
- Thinking used 183 to 628 of the 1,024 tokens, which leaves headroom.
- **Remaining risk:** a long, detail-rich story could produce more than 320 characters. The current trim would then cut mid-sentence and add "...".
- **Optional fix (decision 1):** trim back to the last complete sentence within 320 characters, and use the current cut only if no sentence ends in range. That's about 6 lines in the audio route plus a test.

**JSON output limit:**
- No JSON answer was truncated in 125 JSON calls across both 3.6 Flash runs and the 2.5 Flash validation.
- Highest use: Brief 3,205 and Plan 3,063 of 4,096 tokens, about 78%.
- No change is proposed. The harness flags truncation if it appears. If a Brief ever truncates, I'll propose a Brief-only increase with test evidence.

## 4. Reliability and quotas

**Gemini quotas for `legacy-treasure-chest`** (Cloud Quotas, read-only):
- Paid Tier 1 values, no project overrides.
- The tier is shown in AI Studio; a higher tier only raises these limits.

| Limit | gemini-3.6-flash | gemini-2.5-flash (today) |
|---|---|---|
| Requests per minute | 1,000 | 1,000 |
| Input tokens per minute | 2,000,000 | 1,000,000 |
| Requests per day | 10,000 | 10,000 |

**LTC demand, worst case:**
- **Gateway limits per device:** 25 photo analyses per minute, 60 AI requests per minute, 200 AI requests per day.
- **Batch Add:** up to 20 photos, analyzed one at a time.
- **Gemini calls per photo request:**
  - normally 1 or 2 (initial, plus a repair when needed)
  - up to 4 with upstream retries
  - up to 8 if iOS also retries a 502
- **Ceiling for one device at the gateway limit:** about 100 calls and 330,000 input tokens per minute, and 800 calls per day. These are 10x or more below quota.
- **Conclusion:** quotas are not a material risk for LTC's usage.

**Error handling today (unchanged by this migration):**
- Any Gemini HTTP error (429, 503, or 402 when credits run out) raises an error inside the gateway.
- The gateway retries once after 0.4 s, then returns 502 "Upstream service error".
- iOS retries a 502 once with backoff, then shows a calm "unavailable, try again" message.

Gaps found:
1. **Prepaid credits running out (material).** All 3.x models return 402 when the prepaid balance is depleted, so every AI feature fails until it is topped up. We saw this on 2026-11-03.
   - **Smallest corrective action:** no code. Turn on auto-reload or a low-balance alert for the Gemini prepaid credits in AI Studio billing (decision 2).
2. **Too-short retry for 429 and 503 (minor).** A 0.4 s retry rarely clears either, but the iOS retry with backoff partly covers it.
   - Recommendation: later, a 429/503-only backoff of about 2 s. Not in this migration.
3. **Timeout mismatch (minor).** The gateway waits up to 60 s for Gemini while iOS gives up at 35 s and retries, so a hung call can be duplicated. The observed slowest response was 17.8 s.
   - Recommendation: later, align the Gemini timeout to about 30 s. Not in this migration.
4. **Gemini rate limits look generic to users (cosmetic).** A Gemini 429 reaches the user as "unavailable", not "rate limited". No action.

## 5. Deployment

All commands use `--region us-west1 --project legacy-treasure-chest`, abbreviated `$R` below. Today revision `ltc-ai-gateway-00018-kws` serves 100% of traffic, with `GEMINI_MODEL=gemini-2.5-flash`.

**Before Stage 1:**
1. Merge decision: deploy from the committed `gemini-3-6-migration` branch, and confirm `git status --porcelain` is clean in the worktree.
2. Record the current configuration (read-only):
   ```
   gcloud run services describe ltc-ai-gateway $R --format=export > <scratchpad>/pre_stage1.yaml
   ```
   This file holds secret references, not secret values.

**Stage 1: new code, still 2.5 Flash.**
```
cd LTC_AI_Gateway
gcloud run deploy ltc-ai-gateway --source . $R --no-traffic --tag stage1
```
- **Build:** this builds the new container and creates a revision with **no traffic**, reachable only at its tagged URL.
- **Kept as-is:** existing env vars, the secret binding, and the timeout, concurrency, memory and access settings.
- **Verify on the tagged URL** with synthetic, non-private requests (cents):
  - `GET /health`
  - text analysis
  - Brief
  - Plan
  - a synthetic audio summary, which must be complete
- **Confirm the revision's configuration:** `describe` shows the same env and secret settings as before, `GEMINI_MODEL=gemini-2.5-flash`.

Then route traffic, after your go-ahead:
```
gcloud run services update-traffic ltc-ai-gateway $R --to-tags stage1=100
```
- **Verify in production:**
  - you run an iPhone check: Improve with AI on a photo item, a text-only estimate, Brief, Plan, and Create AI Summary on a 20 to 30 second recording
  - I read error logs read-only for the following hour:
    ```
    gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="ltc-ai-gateway" AND severity>=ERROR' --freshness=1h --project legacy-treasure-chest
    ```

**Stage 2: switch to 3.6 Flash** (separate authorization; ideally the same day or the next).
```
gcloud run services update ltc-ai-gateway $R --update-env-vars GEMINI_MODEL=gemini-3.6-flash --no-traffic --tag stage2
```
- Changing an env var creates a **new revision** from the Stage 1 container, with no rebuild. It takes no traffic until routed.
- Verify on the tagged URL as in Stage 1, and confirm `aiModel` and `aiProvider` read `gemini-3.6-flash`.

Then route traffic:
```
gcloud run services update-traffic ltc-ai-gateway $R --to-tags stage2=100
```
- Repeat the iPhone check. The Liquidation section should show `Model: gemini-3.6-flash`.
- Read the logs, and check that AI Studio usage shows `gemini-3.6-flash`.

**After Stage 2:**
- update `Docs/CLOUD_READINESS_PLAN_v1.md` line 214, `Docs/PRODUCTION_ROADMAP.md` line 18, and add a dated `LegacyTreasureChest/README.md` changelog entry
- commit on the branch
- tags `stage1` and `stage2` stay as named rollback points

## 6. Rollback

Traffic is moved between existing revisions with no rebuild, and takes effect in seconds:
```
gcloud run services update-traffic ltc-ai-gateway $R --to-revisions=<REVISION>=100
```

| When | Route traffic to | What actually runs |
|---|---|---|
| Before Dec 1, Stage 2 problem | Stage 1 revision (`--to-tags stage1=100`) | 2.5 Flash with the new code (audio fixed) |
| Before Dec 1, Stage 1 problem | `ltc-ai-gateway-00018-kws` | Exactly today's production |
| On or after Dec 1, any problem | Stage 1 revision or `00018` | **3.5 Flash-Lite**, because Google redirects `gemini-2.5-flash`. This is **not** a return to 2.5 Flash: it is functional but rated lower in the blind review. Stage 1 is preferred over `00018` because it has the audio fix. |
| On or after Dec 1, code problem on 3.6 Flash | Revert on the branch, then build a fixed revision with `GEMINI_MODEL=gemini-3.6-flash` using the Stage 1 and Stage 2 steps | 3.6 Flash with corrected code |

No revisions are deleted. 3.5 Flash-Lite was validated with the earlier code (31 of 31 OK). The new code changes only parameters that 3.x ignores, plus audio handling that Flash-Lite already passed, so no extra Flash-Lite run was made.

## 7. Deferred issues (not part of this migration)

1. **Photo repair calls.** All repairs under 3.6 Flash had one cause: the first answer named the field `itemName` or `name` instead of `title`, because the photo prompt never lists field names.
   - Not a compatibility problem: the repair succeeds every time.
   - Cost: about 5 s per affected photo.
   - Later fix: map `itemName`/`name` to `title` in normalization (code only), or list the fields in the prompt.
2. `/ai/analyze-item-text` has no repair retry and does not coerce a list-valued `style`.
3. The `LTC_DISABLE_GEMINI` kill switch is not wired up.
4. 429/503 backoff and the timeout alignment (section 4, items 2 and 3).
5. Valuation quality:
   - furniture is undervalued when no maker is visible
   - one answer used wording that implies it checked comparable sales
6. LV Alma (inv-02) size is an open identification case.
7. Experiments to run after the migration: photo plus user text, and supporting photos (PE-001).

## Decisions needed

1. **Audio trim:** add the sentence-aware 320-character trim (recommended, about 6 lines plus a test), or leave the trim as is?
2. **Credits:** enable auto-reload or a low-balance alert for Gemini prepaid credits, and confirm the AI Studio tier.
3. **Stage 1:** authorize it, with a date.
4. **Stage 2:** authorize it after Stage 1 is verified.
5. **Branches:** when to push and merge `gemini-3-6-migration` and `ai-eval-harness`.
