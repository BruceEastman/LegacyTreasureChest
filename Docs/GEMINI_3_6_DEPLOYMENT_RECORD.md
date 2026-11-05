# Gemini 3.6 Flash Migration: Deployment Record

This file links each production revision to the exact Git commit and container image it runs, so the repository can be reconciled after deployment. Plan: `Docs/GEMINI_3_6_MIGRATION_PLAN.md`.

Service `ltc-ai-gateway`, region `us-west1`, project `legacy-treasure-chest`.

## Revisions

| Revision | Tag | Git commit (branch) | Image digest | GEMINI_MODEL | Status |
|---|---|---|---|---|---|
| `ltc-ai-gateway-00018-kws` | (none) | `36cd4c2` (`main`) | `sha256:3bf5d06c4394…bed2f1` | `gemini-2.5-flash` | Previous production. Kept as rollback. |
| `ltc-ai-gateway-00019-foc` | `stage1` | `be7d8e9` (`gemini-3-6-migration`) | `sha256:4fc69d2d1800…a55d52` | `gemini-2.5-flash` | Stage 1. 100% of traffic from 00:16 to 01:07 UTC on 2026-11-04. Kept as rollback. |
| `ltc-ai-gateway-00021-hof` | `stage2` | `be7d8e9` (same image as Stage 1) | `sha256:4fc69d2d1800…a55d52` | `gemini-3.6-flash` | Stage 2. 100% of traffic from 01:07 to about 02:30 UTC on 2026-11-04. **Immediate rollback.** |
| `ltc-ai-gateway-00023-vim` | `titlefix` | `716ca7f` (`photo-title-alias`, merged as `2bf55cb`) | `sha256:89479189c2c9…0c65f3a9` | `gemini-3.6-flash` | Photo title fix. 100% of traffic from about 02:30 to 20:35 UTC on 2026-11-04. Kept as rollback. |
| `ltc-ai-gateway-00025-rif` | `brieflog` | `92d732f` (`brief-latency-instrumentation`) | `sha256:b549510a6401…ed46624a` | `gemini-3.6-flash` | Brief timing instrumentation. 100% of traffic from about 20:35 to 20:51 UTC on 2026-11-04. **Immediate rollback.** |
| `ltc-ai-gateway-00027-mod` | `brieffix` | `8b8fb7a` (`brief-latency-instrumentation`, merged as `f7b20e3`) | `sha256:db02f13d57c5…b3dcf36` | `gemini-3.6-flash` | **Brief 8,192 output limit, no identical retry after MAX_TOKENS. 100% of traffic since about 20:51 UTC on 2026-11-04. Verified in real use.** |

Revision numbers 00020, 00022, 00024 and 00026 were never created: Cloud Run numbers revisions by service generation, and the traffic changes used those generations.

Image repository: `us-west1-docker.pkg.dev/legacy-treasure-chest/cloud-run-source-deploy/ltc-ai-gateway`.

## Stage 1 (2026-11-04 UTC)

1. **Tests:** 181 of 181 automated tests pass at `be7d8e9`.
2. **Local validation (`ai_eval` harness):**
   - runs `migration_rc1` (code at `f120d80`) and `migration_rc2_audio` (code at `be7d8e9`, clean tree)
   - 0 failures, audio summaries complete
3. **Deploy:** run from a clean worktree of `be7d8e9`:
   ```
   gcloud run deploy ltc-ai-gateway --source . --region us-west1 --project legacy-treasure-chest --no-traffic --tag stage1
   ```
4. **Configuration check:** compared with `00018`, the revision configuration is identical except for the image. That covers the env vars and rate limits, the secret references (`latest`), timeout 300 s, concurrency 20, 1 CPU and 512 Mi.
5. **Tagged URL smoke test** with synthetic, non-private inputs: health, photo (rendered product icon), text, Brief, Plan and audio. All returned HTTP 200, with model `gemini-2.5-flash` and a complete 228-character audio summary. No warnings or errors in the revision logs.
6. **Traffic:**
   ```
   gcloud run services update-traffic ltc-ai-gateway --region us-west1 --project legacy-treasure-chest --to-tags stage1=100
   ```
   Confirmed that the app's base URL is served by `00019-foc`.
7. **iPhone verification by Bruce:** passed on 2026-11-04. All workflows worked, and responses seemed faster and better than before.

## Stage 2 (2026-11-04 UTC)

Configuration-only: a new revision from the Stage 1 image, with no rebuild and no traffic at first:
```
gcloud run services update ltc-ai-gateway --region us-west1 --project legacy-treasure-chest \
  --update-env-vars GEMINI_MODEL=gemini-3.6-flash --no-traffic --tag stage2
```
Results:
1. **Configuration check:** compared with `00019-foc`, the only difference is `GEMINI_MODEL`. The image digest is identical.
2. **Tagged-URL smoke test** (synthetic inputs):
   - all 6 requests returned HTTP 200
   - every response reports `gemini-3.6-flash`
   - the audio summary is complete (234 characters)
   - the Brief took 20.5 s, under the 35 s iOS timeout
   - no warnings or errors in the revision logs
3. **Traffic:** `--to-tags stage2=100` at 01:07 UTC, and the app's base URL returns HTTP 200.
4. **iPhone verification by Bruce:** passed on 2026-11-04 (Improve with AI, Brief and Plan).

## Photo title fix (2026-11-04 UTC)

Gemini 3.6 Flash often names the photo title field `itemName` or `name`, which used to trigger a second (repair) Gemini call of about 4.6 s. The shared item-analysis normalizer now uses that value as the title when the title is missing or blank. No change to prompts, valuation, model or API contract.

1. **Tests:** 206 of 206 pass at `716ca7f`.
2. **Harness run `titlefix_rc1`** (18 private photo cases, `gemini-3.6-flash`):
   - 0 repairs, down from 10 to 12 in earlier runs
   - median 9.7 s (was 10.9 to 11.7 s), slowest 11.4 s (was 15 to 17 s)
   - no check failures
3. **Deploy** from a clean worktree at `716ca7f`:
   ```
   gcloud run deploy ltc-ai-gateway --source . --region us-west1 --project legacy-treasure-chest --no-traffic --tag titlefix
   ```
4. **Configuration check:** compared with `00021-hof`, only the image and build metadata differ.
5. **Tagged-URL smoke test** (synthetic inputs):
   - all 6 requests (health, photo, text, Brief, Plan, audio) returned HTTP 200
   - every response reports `gemini-3.6-flash`
   - no warnings or errors in the revision logs
6. **Traffic:** `--to-tags titlefix=100`. The app's base URL returns HTTP 200, with no errors after the switch.
7. **iPhone verification by Bruce:** passed on 2026-11-04 (Improve with AI on multiple items).
8. **Git:** merged into `main` as `2bf55cb`.

## Liquidation Brief instrumentation (2026-11-04 UTC)

On 2026-11-04 two Briefs took about 55 s on the iPhone. In each, the first Gemini reply could not be parsed as JSON (after about 20 s). The gateway resent the identical request, the iPhone timed out at 35 s and resent the Brief, and the resend succeeded in 18 to 19 s. Production did not log Gemini's finish reason or token use, so the cause could not be confirmed.

1. **Change (`92d732f`):** the Brief route logs one `gemini.attempt` line per Gemini call and one `liquidation_brief.result` line per request, plus `liquidation_brief.repair` for a schema repair.
   - Fields: request id, item/set scope, phase, attempt, latency, HTTP status, finishReason, prompt/output/thinking tokens, reply length, text part count and, for an unparseable reply, a content-free structure summary.
   - No prompt, model text, item details or API key is logged.
   - Request behavior was unchanged. Other endpoints do not log these lines.
2. **Tests:** 206 existing pass, plus 10 new instrumentation tests.
3. **Deploy** from a clean worktree at `92d732f`: `gcloud run deploy ltc-ai-gateway --source . --region us-west1 --project legacy-treasure-chest --no-traffic --tag brieflog`.
4. **Configuration check:** compared with `00023-vim`, only the image and the deploy operation id differ.
5. **Tagged-URL verification:** one synthetic Brief.
   - HTTP 200 in 16.9 s, a sound Brief.
   - Log lines present with all fields, no content.
   - finishReason STOP. Output 1,064 + thinking 2,232 = 3,296 of 4,096 tokens (80%).
6. **Traffic:** `--to-tags brieflog=100`. The base URL returned HTTP 200.
7. **Observation (Bruce's iPhone, 20:38 to 20:42 UTC):** 3 Briefs (1 Set, 2 items), all first-pass valid JSON with finishReason STOP.
   - 13.8 to 18.5 s each.
   - Output plus thinking used 68 to 80% of the 4,096 cap.
   - Gemini time is about 5.0 to 5.7 ms per generated token. At that rate, the failed attempts of earlier that day (19.6 to 21.9 s) imply about 3,400 to 4,400 generated tokens, which is consistent with reaching the 4,096 cap (not logged, so not confirmed).

## Liquidation Brief output-limit correction (2026-11-04 UTC)

Approved by Bruce on the timing evidence above, without a logged MAX_TOKENS failure. The instrumentation stays on to confirm the effect.

1. **Change:** Brief only.
   - The Gemini output limit for the Brief goes from 4,096 to 8,192 tokens. Thinking tokens count toward the limit. A Brief that fits today is unaffected.
   - When Gemini reports finishReason MAX_TOKENS and the reply does not parse, the gateway no longer resends the identical request (about 20 s wasted). It fails at once.
   - Every other failure still gets one retry.
   - Unchanged: prompt, model, thinking settings, schema repair, and every other endpoint (Plan, photo, text, audio still at 4,096 with their existing retry).
2. **Tests:** 218 of 218 pass, including tests that the Brief alone uses 8,192 and skips the identical retry after MAX_TOKENS, and that a Plan still retries.
3. **Deploy** from a clean worktree at `8b8fb7a` with `--no-traffic --tag brieffix`, giving revision `00027-mod`.
4. **Configuration check:** compared with `00025-rif`, only the image differs.
5. **Tagged-URL verification:** the same synthetic Brief as for `00025-rif`.
   - HTTP 200 in 15.1 s, against 16.9 s on `00025-rif`.
   - Same recommendation, same four approaches and nearly identical net proceeds.
   - Log line: maxOutputTokens 8192, finishReason STOP, output 1,062 + thinking 1,617 = 2,679 tokens (33% of the new limit).
   - No warnings or errors, and no content in the logs.
6. **Traffic:** `--to-tags brieffix=100` at about 20:51 UTC. The base URL returned HTTP 200.
7. **Production verification (Bruce's iPhone, 00:35 to 00:59 UTC on 2026-11-05):** a varied set of items and Sets, text-only items and several categories.
   - 11 Briefs (1 Set, 10 items): all HTTP 200, finishReason STOP, valid JSON on the first pass. No retries and no schema repairs. No MAX_TOKENS or malformed replies.
   - Gemini time 14.8 to 22.4 s per Brief, all well inside the iOS 35 s timeout. The first request took 23.1 s end to end because the instance was starting up.
   - **Two valid Briefs exceeded the former 4,096-token limit:** 4,294 and 4,209 tokens (output plus thinking), at 22.4 and 20.5 s. Under the old limit both would have been cut off at the same point as the failures of 2026-11-04. This confirms the cause (Briefs reaching the output limit) and the fix. 2 of 11 also matches the earlier failure rate of roughly 1 in 5.
   - Also in the same window: 10 Plans (10.4 to 14.7 s), 9 photo analyses (9.5 to 14.1 s) and 1 text analysis (9.6 s). All returned HTTP 200.
   - Query: `resource.labels.revision_name="ltc-ai-gateway-00027-mod" AND textPayload:"gemini.attempt"`.
8. **Status:** resolved and closed on 2026-11-05.
   - The diagnostic logging stays on, with no content logged.
   - `00025-rif` stays at 0% as the immediate rollback.

### Deferred: iOS Brief timeout and resend (future app release)

Not part of this correction, and no iOS code was changed.
- **Current behavior:** the app waits 35 s for a Brief, then resends the same request.
- **Proposed change:** a 60 s Brief timeout, and no automatic resend after a timeout.
- **Why:**
  - The slowest verified Brief (22.4 s) leaves about 13 s of margin. At about 5 ms per generated token, a Brief of about 6,500 tokens would reach 35 s.
  - A resend after a timeout duplicates a Gemini call that may still succeed.

## Rollback

```
gcloud run services update-traffic ltc-ai-gateway --region us-west1 --project legacy-treasure-chest --to-revisions=<REVISION>=100
```
- Brief output-limit correction problem: `00025-rif` (instrumentation only, 4,096 limit, identical retry).
- Brief instrumentation problem: `00023-vim` (photo title fix, no Brief logging).
- Photo title fix problem: `00021-hof` (Stage 2, `gemini-3.6-flash` without the fix).
- Before 2026-12-01: `00019-foc` (Stage 1) or `00018-kws` (previous production).
- From 2026-12-01: both of those run `gemini-3.5-flash-lite`, because Google redirects `gemini-2.5-flash`. That is not a return to 2.5 Flash. Prefer `00019-foc`, which has the audio fix.

## Git reconciliation

- `gemini-3-6-migration` and `ai-eval-harness` were merged into `main` on 2026-11-04 (`121092c`, `67c2691`; docs `ecd3296`).
- `photo-title-alias` was merged into `main` as `2bf55cb`. At that point, `LTC_AI_Gateway` on `main` matched production revision `00023-vim` (commit `716ca7f`).
- `brief-latency-instrumentation` was merged into `main` as `f7b20e3` on 2026-11-05. `LTC_AI_Gateway` on `main` matches production revision `00027-mod` (commit `8b8fb7a`). 218 of 218 tests pass on the merged `main`.
