# Refactor Status — analyze_item_photo.py (Extract-only)

**Status:** IN PROGRESS (paused for UI improvements)  
**Approach:** Extract-only, one phase per commit, no behavior changes, no endpoint changes.  
**Validation:** python compileall + uvicorn startup after each phase.

## Completed Phases (Committed)

### Phase 1 — Pure helpers (time + JSON parsing)
- Extracted `_now_iso_z`, `_utcnow`, `_parse_llm_json_obj`, `_unwrap_singleton_wrapper`
- New module: `app/ai/util/time_json.py`
- `analyze_item_photo.py` updated to import helpers
- Commit: "Refactor: extract time/json helper utilities (Phase 1)"

### Phase 2 — Prompts + experts (prompt helpers only)
- Extracted item analysis prompt builders:
  - `build_item_analysis_prompt`
  - `build_item_analysis_text_prompt`
  - `_build_item_analysis_repair_prompt`
  - (internal) `_format_hints`
- New module: `app/ai/prompts/item_analysis.py`
- `analyze_item_photo.py` updated to import prompt helpers
- Commit: "Refactor: extract item analysis prompt helpers (Phase 2)"

### Phase 3 — Normalization / repair (normalizer only)
- Extracted `_normalize_item_analysis_json`
- New module: `app/ai/normalization/item_analysis.py`
- `analyze_item_photo.py` updated to import normalizer
- Commit: "Refactor: extract item analysis normalization helper (Phase 3)"

## Deferred Phases (Not Started)

### Phase 4 — Disposition Engine extraction
- Extract Disposition Engine scenario/evaluation/presentation helpers out of `analyze_item_photo.py`
- Target structure under `app/services/disposition_engine/`

## Operational Notes
- Start backend from `LTC_AI_Gateway` using:
  `python3 -m uvicorn main:app --reload --host 0.0.0.0 --port 8000`
- VS Code import squiggles may require `python.analysis.extraPaths = ["." ]` in `.vscode/settings.json`


### Summary

* This outline is perfect: it clearly shows **four big responsibilities living in one file** (prompts, normalization/repair, disposition matrix selection, and partner ranking/trust).
* The fastest, safest refactor is to split along those seams while keeping **route handlers as thin orchestration** in the current file (or a routes module).
* We can do this **without changing behavior** by moving pure functions first, then switching imports.

Your function list already *proves* the file is becoming the “AI brain” of the app—exactly what you described. 

---

## What your top-level structure tells us (the real seams)

From the names alone, the file contains these subsystems:

### 1) Prompt assembly (high churn)

* `build_item_analysis_prompt`
* `build_item_analysis_text_prompt`
* `_build_liquidation_brief_prompt` / `_build_liquidation_plan_prompt`
* repair prompts: `_build_*_repair_prompt`

✅ These will evolve constantly as you add nuance.

### 2) Normalization + schema repair (trust layer)

* `_normalize_item_analysis_json`
* `_normalize_liquidation_brief_obj`
* `_normalize_liquidation_plan_obj`
* parsing/unwrapping: `_parse_llm_json_obj`, `_unwrap_singleton_wrapper`
* value policy / defaults: `_apply_value_policy`, `_fallback_for_category`, `_missing_details_for_category`
* enum normalization: `_normalize_path_value`, `_normalize_effort_value`

✅ This is “contract enforcement” and should be isolated and tested.

### 3) Disposition matrix selection (scenario logic)

* `_load_disposition_matrix`
* `_scenario_matches`, `_pick_scenario`
* `_norm` (likely normalization helper)

✅ This will expand as you add categories and set/batch scenarios. 

### 4) Partner discovery ranking + trust evaluation (engine logic)

* caching: `_cache_get`, `_cache_set`, `_mk_cache_key`
* trust gates: `_negated`, `_eval_gate_keyword_any`, `_evaluate_trust`, `_apply_required_gates`
* scoring: `_relevance_score`, `_distance_score`, `_review_score`
* explainability: `_summarize_reasons`, `_build_questions`
* `_rank_candidates`
* `_stub_places_search` (and presumably a real Places call elsewhere)

✅ This is basically a small engine. It should not be tangled with prompt text.

---

## My recommendation: refactor now, but “extract-only”

You’re not refactoring because it’s big—you’re refactoring because **prompt nuance + scenario coverage** are your product, and you don’t want a god-file slowing iteration.

Also, your README already calls out that Disposition Engine scenario coverage is the next major expansion area, which will amplify this growth pressure. 

---

## Target module layout (minimal, AI-first)

Here’s a structure that maps *exactly* to your function list:

```
app/
  ai/
    prompts/
      item_analysis.py              # build_item_analysis_prompt, build_item_analysis_text_prompt, _format_hints
      liquidation.py                # _build_liquidation_*_prompt + repair prompts
    normalization/
      json_tools.py                 # _parse_llm_json_obj, _unwrap_singleton_wrapper
      item_analysis.py              # _normalize_item_analysis_json, _apply_value_policy, category fallbacks
      liquidation.py                # _normalize_liquidation_brief_obj/_plan_obj, normalize enums
    util/
      time.py                       # _now_iso_z, _utcnow, _utcnow
  services/
    disposition_engine/
      matrix.py                     # _load_disposition_matrix, _scenario_matches, _pick_scenario, _norm
      trust.py                      # _negated, _eval_gate_keyword_any, _evaluate_trust, _apply_required_gates
      scoring.py                    # _relevance_score, _distance_score, _review_score, _rank_candidates
      explain.py                    # _summarize_reasons, _build_questions
      cache.py                      # _cache_get/_set/_mk_cache_key
      providers/
        stub.py                     # _stub_places_search
        google_places.py            # (your real places search wrapper)
  routes/
    analyze_item_photo.py           # endpoints only (or keep file name, just thin)
```

This keeps your conceptual “single gateway” but stops it from being a single file.

---

## Extraction order (how we do this safely)

To avoid breaking anything, we move in the order of **least coupling**:

### Phase 1 — pure helpers first (almost zero risk)

1. `ai/util/time.py`: `_now_iso_z`, `_utcnow`
2. `ai/normalization/json_tools.py`: `_parse_llm_json_obj`, `_unwrap_singleton_wrapper`

✅ No behavioral change, minimal import ripple.

### Phase 2 — prompts (still low risk)

3. `ai/prompts/item_analysis.py`: `_format_hints`, `build_item_analysis_prompt`, `build_item_analysis_text_prompt`
4. `ai/prompts/liquidation.py`: `_build_liquidation_*_prompt` + `_build_*_repair_prompt`

✅ Prompts are just strings; moving them is safe.

### Phase 3 — normalization (moderate risk, huge payoff)

5. `ai/normalization/item_analysis.py`: `_normalize_item_analysis_json`, category fallbacks, `_apply_value_policy`
6. `ai/normalization/liquidation.py`: `_normalize_*_obj`, `_normalize_path_value`, `_normalize_effort_value`

✅ This is where you’ll benefit most long term.

### Phase 4 — disposition engine (contained subsystem)

7. `services/disposition_engine/*`: matrix + trust + scoring + explain + cache + providers

✅ This is your fastest-growing capability.  

---

## Guardrails so we don’t “refactor into chaos”

1. **No behavior changes** during extraction

* same function signatures
* same default values
* same return shapes

2. **Central import surface**

* In `routes/analyze_item_photo.py`, imports look like:

  * `from app.ai.prompts.item_analysis import build_item_analysis_prompt`
  * etc.

3. **Smoke tests after each phase**

* run your existing curl calls (item analysis, liquidation brief/plan, disposition search). 

---

## One question (next logical step)

Do you want to keep the **file name** `app/routes/analyze_item_photo.py` as the “one entrypoint,” but make it thin (recommended), **or** also rename it to something like `ai_gateway_routes.py` once it’s clean?

Either choice works; it only affects how you navigate the repo.

### What to incorporate from this feedback

You should incorporate **all three** of these ideas, with one small nuance on the disposition folder depth:

1. **Keep `analyze_item_photo.py` name through Phase 4** ✅
2. **Add `app/ai/experts/` for category expert prompt blocks** ✅
3. **Structure Disposition Engine by responsibility** ✅ (scenario / evaluation / presentation), but keep it *lightweight* initially.

This is fully consistent with your “single gateway” philosophy and your capability spine (Disposition + Sets are the value layers).  

---

## Review of the feedback: what’s strong and why

### 1) Keep the entrypoint filename

**Agree.** During extraction refactors, filenames are landmarks. Renaming mid-flight adds noise and makes diffs harder to review. Rename only when the file is clearly “routes only.”
**Incorporate:** Rename only after Phase 4, in its own commit.

### 2) Add `ai/experts/` (this is the big “IP” callout)

**Strongly agree.** Your experts are going to evolve quickly, and they’re conceptually different from “prompt assembly.” Experts are *content*, prompt assembly is *logic*. Separating those gives you:

* safer edits (tuning content won’t touch logic)
* cleaner diffs (text changes are contained)
* easier reuse (experts can be used for item, set, batch prompts later)

**Incorporate:** yes. Make each expert file “constants only” as suggested.

### 3) Disposition Engine subfolders now vs later

**Agree with the intention**, but I’d apply one nuance:

* If you’re confident you’ll expand Disposition rapidly (you are), the subfolder split prevents another refactor in 2 months.
* But don’t over-architect it: keep it to **three subpackages max** initially.

**Incorporate:** yes, but keep it minimal:

* `scenario/` (matrix + matching)
* `evaluation/` (trust + scoring + ranking)
* `presentation/` (whyRecommended + questionsToAsk builders)

This lines up cleanly with what you already describe as “scenario coverage” + “why/questions” outputs. 

---

## One thing I’d add to their plan (worth adopting)

### Add a “public surface” module to stabilize imports

Right now your function names are mostly `_private_*`. Once you extract, you’ll want stable imports and fewer callsites changing.

Add a thin `__init__.py` (or a `facade.py`) that exports the functions the routes call.

Example:

* `app/ai/prompts/__init__.py` exports:

  * `build_item_analysis_prompt`
  * `build_liquidation_brief_prompt`
* `app/ai/normalization/__init__.py` exports:

  * `normalize_item_analysis_json`
  * `normalize_liquidation_brief_obj`

This reduces churn as you continue refactoring and makes the gateway file stay readable.

---

## Small corrections to the feedback (important)

### They propose new implementations (“now_iso_z” etc.)

Be careful: **don’t rewrite** helpers during Phase 1.
Instead: *move your existing implementations verbatim* so behavior stays identical. (Even time formatting differences can cascade into fingerprints, logs, or DTO expectations.)

So: the “generate new file code” idea is fine, but only if it’s a **copy/paste of your exact current functions**, not a rewrite.

### They mention “Time investment: 12–15 hours”

Maybe, but time estimates aren’t useful here. The right unit is: **one phase per commit with smoke tests**.

---

## Updated plan incorporating the best ideas

### Adopt these changes to our target layout

Add:

```
app/ai/experts/
  jewelry.py
  rugs.py
  art.py
  furniture.py
  china_crystal.py
  luxury_personal.py
```

Refine Disposition Engine:

```
app/services/disposition_engine/
  scenario/
    matrix.py
    matcher.py
  evaluation/
    trust.py
    scoring.py
    ranker.py
  presentation/
    explain.py
    questions.py
  providers/
    google_places.py
    stub.py
  cache.py
```

Keep `app/routes/analyze_item_photo.py` name until the end.

---

## What I recommend you do next (one step)

Let’s start **Phase 1 (pure helpers)** exactly as the feedback suggests, but with “copy verbatim” guardrails.

To do that cleanly, paste **only these four function bodies** from your current `analyze_item_photo.py`:

* `_now_iso_z()`
* `_utcnow()` (and/or `_utcnow()` vs `_utcnow`—you have both `_utcnow()` and `_utcnow` listed; we’ll preserve exactly)
* `_parse_llm_json_obj()`
* `_unwrap_singleton_wrapper()`

Then I’ll generate the **complete new files** (ready to drop in), plus the minimal import edits needed in `analyze_item_photo.py`, and the exact curl smoke tests to run after the commit.
