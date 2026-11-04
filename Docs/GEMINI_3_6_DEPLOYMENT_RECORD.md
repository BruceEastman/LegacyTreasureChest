# Gemini 3.6 Flash Migration: Deployment Record

This file links each production revision to the exact Git commit and container image it runs, so the repository can be reconciled after deployment. Plan: `Docs/GEMINI_3_6_MIGRATION_PLAN.md`.

Service `ltc-ai-gateway`, region `us-west1`, project `legacy-treasure-chest`.

## Revisions

| Revision | Tag | Git commit (branch) | Image digest | GEMINI_MODEL | Status |
|---|---|---|---|---|---|
| `ltc-ai-gateway-00018-kws` | (none) | `36cd4c2` (`main`) | `sha256:3bf5d06c4394…bed2f1` | `gemini-2.5-flash` | Previous production. Kept as rollback. |
| `ltc-ai-gateway-00019-foc` | `stage1` | `be7d8e9` (`gemini-3-6-migration`) | `sha256:4fc69d2d1800…a55d52` | `gemini-2.5-flash` | Stage 1. 100% of traffic from 00:16 to 01:07 UTC on 2026-11-04. Kept as rollback. |
| `ltc-ai-gateway-00021-hof` | `stage2` | `be7d8e9` (same image as Stage 1) | `sha256:4fc69d2d1800…a55d52` | `gemini-3.6-flash` | **Stage 2. 100% of traffic since 2026-11-04 01:07 UTC.** |

Revision number 00020 was never created: Cloud Run numbers revisions by service generation, and the Stage 1 traffic change used generation 20.

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
4. **iPhone verification by Bruce:** pending.

## Rollback

```
gcloud run services update-traffic ltc-ai-gateway --region us-west1 --project legacy-treasure-chest --to-revisions=<REVISION>=100
```
- Before 2026-12-01: `00019-foc` (Stage 1) or `00018-kws` (previous production).
- From 2026-12-01: both of those run `gemini-3.5-flash-lite`, because Google redirects `gemini-2.5-flash`. That is not a return to 2.5 Flash. Prefer `00019-foc`, which has the audio fix.

## Reconciling Git after deployment

- `main` is still at `36cd4c2`; production runs `be7d8e9` from `gemini-3-6-migration`.
- After Stage 2 is verified, merge `gemini-3-6-migration` into `main` (with your approval), so `main` matches production.
- `ai-eval-harness` is independent (`ai_eval/` and docs only, no gateway code) and can be merged separately.
