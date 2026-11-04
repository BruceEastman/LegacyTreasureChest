# LTC AI regression suite (`ai_eval`)

A small, reusable harness for comparing Gemini models (or prompt and valuation-logic changes)
on the same LTC inputs. It runs the real `LTC_AI_Gateway` routes in-process, so every result
goes through the production prompts, JSON cleaning, normalization, the valuation policy and the
repair logic. It is not part of the Cloud Run image: this folder sits outside
`LTC_AI_Gateway/`, which is the Docker build context.

## Safety

- **No production changes.** Nothing is sent to Cloud Run and nothing in Google Cloud is
  modified. The gateway runs locally, stateless, with Places disabled.
- **Network guard.** Inside the worker, every outbound request is blocked except
  `POST generativelanguage.googleapis.com/.../models/<model>:generateContent`.
- **API key.** Read from Secret Manager (`gemini-api-key`, the one production uses) into
  memory and passed to the worker on stdin. It is never printed or written. The worker scrubs it
  from every record and deletes the run output if the key is found anywhere on disk.
- **Shared quota and billing.** Live runs use the production key, so they draw on the same
  prepaid credits and rate limits as the app.
- **Private data stays local.** `private/`, `results/` and `generated/` are ignored by Git.
  Photos are re-encoded and stripped of EXIF/GPS/XMP before use, and the worker refuses a photo
  that still carries metadata. Raw responses keep only a hash of any image or audio sent.

## Layout

```
harness/            code (commit)
  run_suite.py      manifest, dry run, live or mock runs
  worker.py         runs one model through the gateway and records everything
  checks.py         automated technical and heuristic checks
  report.py         comparison, blind review sheet, sanitized summary
  catalog.py        stable photo ids, prepared copies, thumbnails, contact sheet, CSV seeding
  build_suite.py    items.csv + sales.csv -> generated suite.json + references.json
  prepare_photos.py iPhone photo -> JPEG q85, upright, metadata stripped
  make_synthetic_audio.py   macOS `say` recordings for audio cases
  pricing.json      dated price table used for cost estimates
suites/core_v1/     non-private cases + separate reference facts (commit)
private/            your inventory suite, photos, references (never commit)
generated/          synthetic audio (regenerable, not committed)
results/            raw run output (never commit; back it up)
reports/            sanitized summaries (commit after review)
```

## What a run records (per case, per model)

- **Gemini calls.** Initial, retry and repair calls are told apart. For each call:
  - requested model and the `modelVersion` Google returned
  - HTTP status, `finishReason`, latency
  - token usage, including thinking tokens, and estimated cost
  - the raw response
- **Processing stages, kept separate from the model's answer:**
  - `1_clean_llm_json`: the model's text, then the extracted JSON
  - `2_normalize_*`: the gateway's normalization
  - `3_normalize_category`: the model's category, then the LTC category
  - `4_apply_value_policy`: the value hints before and after LTC's valuation rules
- **Route error detail.** Production hides this from clients as "Upstream service error".
- **Final response** exactly as the iOS app would receive it.
- **Run metadata:** suite versions and hashes, a fingerprint of the prompt and pipeline files,
  and the git commit.

## Workflow

```bash
cd LegacyTreasureChest_App/ai_eval

# 1. Photos: drop originals (any name, HEIC/JPEG) into private/inventory_v1/originals, then
python3 -I harness/catalog.py private/inventory_v1
#    -> stable photo ids (ph-NN), prepared metadata-free copies, contact_sheet.html,
#       and items.csv / sales.csv seeded if missing. Originals are never modified.
#    Edit items.csv (status, identity, supporting photos, ...) and sales.csv (sold/asking prices)
#    in Numbers or Excel, then generate the suite (never edit the generated JSON):
python3 -I harness/build_suite.py private/inventory_v1 [--variants photo,photo_text]

# 2. Synthetic audio (once)
python3 -I harness/make_synthetic_audio.py suites/core_v1/suite.json

# 3. Manifest and cost estimate (no network)
python3 -I harness/run_suite.py --suite suites/core_v1/suite.json --suite private/inventory_v1/suite.json \
    --model gemini-2.5-flash --model gemini-3.5-flash-lite --dry-run

# 4. Live run (asks for confirmation)
python3 -I harness/run_suite.py ... --label baseline

# 5. Report (re-scores with the current reference files; several run dirs can be combined)
python3 -I harness/report.py results/<run-dir> [results/<older-run-dir>]
```

Use `--mock` (with `--mock-scenario normal|repair|invented_category|style_list`) to test the
harness itself without network or cost. `--only` and `--types` limit a run.

To test gateway code from another branch (for example a git worktree), set
`LTC_EVAL_GATEWAY_DIR=/path/to/worktree/LTC_AI_Gateway`. The run metadata records which branch,
commit and directory were tested. `report.py` and `review_page.py` accept `--models` to compare
only some models, and `report.py --blind-types photo,text,brief,plan` leaves audio out of blind review.

## Reading results

- **Automated checks** (`fail` / `warn` / `info`) flag technical problems and things to look
  at: invalid ranges, repairs, timeouts, missing key facts, possibly invented details, and
  wording that implies checked sales data (the gateway has no access to sales data).
- **Sold vs asking.** In `references.json`, only `"type": "sold"` counts as a realized
  outcome. Asking prices, appraisals and offers are shown for context only.
- **Human judgment** goes in `review_sheet.csv`, where models appear as A/B in random order
  per case so no model is favored. Score in priority order: identification, description,
  valuation, speed, guidance. Agreement with an older model is not evidence of correctness.
