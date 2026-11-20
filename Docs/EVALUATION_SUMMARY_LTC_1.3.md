# LTC 1.3 Evaluation Summary: Supplementary Evidence for Improve with AI

Status: closed. LTC 1.3 (build 11) shipped on the App Store in November 2026 from release commit `99134e4`.
Model under test: `gemini-3.6-flash` through the production LTC AI Gateway code path.

This is the durable record of how LTC 1.3's supplementary evidence feature was evaluated and what was decided.
Private photographs, document contents, ground truth and request payloads stay outside this repository (see
"Retained evidence and tooling").

## 1. Hypothesis

Improve with AI would identify, describe and value items better if the owner could attach a few extra photos (maker
marks, stamps, labels) and one document (an appraisal, receipt or certificate) to the analysis, alongside the main
photo. Before shipping, the release also had to show that this could be done:

- without exposing personal identifiers from documents,
- without inventing makers or dates,
- without confusing purchase or replacement prices with resale value,
- and without mixing up whether a value is for one unit or for a group.

## 2. Approach

Three rounds, each one run per case. Every difference is a single observation, not a measured effect.

| Round | Date | Cases | Gemini calls | Cost |
|---|---|---|---|---|
| PE-001 evidence pilot (A/B design, real owner items) | 2026-11-04 | 13 analyses, 6 items | 13 | $0.090 |
| 1.3 live evaluation (16-case matrix, app's real request and review code) | 2026-11-06 | 16 | 16 | $0.142 |
| Addendum A1 (maker stamp photo added to the quantity-4 case) | 2026-11-06 | 1 | 1 | $0.008 |
| Stage 5B regression (after prompt and app fixes) | 2026-11-06 | 4 | 4 | $0.038 |

**PE-001** compared condition A (new item, main photo only) with condition B (Improve with AI from the accepted item,
plus one piece of evidence). One jewelry case also had an M condition, where the historical appraisal amount was
masked to test anchoring. Valuations were checked against independent sale benchmarks that were never sent to the
model.

**The 1.3 live evaluation** used an opt-in bridge test that runs the app's real Improve with AI pipeline in the
simulator. It prepares requests with the shipping app code and replays the gateway responses through the app's review
rules, so the scores reflect what the app would show and save. The 16 cases covered:

- **Request format:** 1.2 versus 1.3 for the same photo.
- **Resolution:** a lower-resolution copy of the same photo.
- **Evidence:** a maker-mark photo, an irrelevant photo attached by mistake, and multipage synthetic appraisals,
  including one where the maker appears only past the 10-page limit.
- **Valuation units:** a quantity-4 item and its exact repeat, plus a quantity-1 entry that is a complete
  10-setting service.
- **Owner text:** an owner naming a maker that contradicts the mark, and an unsupported owner date claim.
- **Documents and calibration:** a synthetic receipt full of personal identifiers, a sparse text-only item, and the
  largest request possible with the available inputs (1 photo plus 10 pages, about 2.6 MB).

Ground truth was sealed (SHA-256 recorded) before the live run.

Automated gates:
- **G1:** privacy
- **G2:** no unsupported maker or date
- **G3:** resale, not replacement
- **G4:** valuation unit
- **G5:** pipeline health
- **G6:** conflicts reported
- **G7:** evidence helps
- **G9:** confidence calibration
- **G8:** blind human review

## 3. Principal findings

### Identification

- Evidence photos fixed identification. In PE-001, maker marks, backstamps and stamps gave the correct maker for
  stools, china (maker, pattern name and number), nightstands and a pendant. A two-page appraisal and lab report gave
  full gemstone and metal details.
- In the 1.3 evaluation, the mark gave the correct maker in all three mark cases, including the case where the owner
  named a different maker. In that case the model reported the conflict instead of adopting the owner's claim.
- No case invented a maker:
  - the irrelevant-photo control,
  - the truncated 12-page document (the maker on page 11 never appeared, because only 10 pages are sent),
  - the receipt (the retailer was not given as the maker),
  - the sparse text-only item.
- Addendum A1: adding the stamp photo to the quantity-4 item produced the correct maker and edition. Without it, both
  the original run and its repeat named no maker.

### Descriptions and privacy

- G1 privacy passed. No personal identifier from the synthetic receipt or appraisals appeared in a proposed name,
  description or details field.
- One failure, G2, came from case E12: the owner's unsupported "made in 1890" claim was saved as the item's era. This
  was fixed in Stage 5B. After the fix, E12 returned "late 19th to mid 20th century" and the receipt case returned
  "circa 2000s" instead of an exact year.
- PE-001 showed the model can invent components that aren't in the photo (for example, extra plates in a china set)
  and can list materials it also calls unknown. Results are therefore presented as suggestions the owner reviews, not
  facts.

### Valuations

- Evidence moved estimates in a sensible direction but did not make them accurate:
  - **Stools (sold as a set):** the estimate midpoint rose from 11% of the sale price without the stamp to 23% with
    it. The high end was 33%.
  - **Bed:** the estimate rose from 0.35x to 0.59x of a contextual sale benchmark once the manufacturer was known.
  - In both benchmarked cases, every estimate stayed below the realized price.
- Value confidence rose with evidence; in A1 it went from 0.35 to 0.80. Stage 5B lowered A1 to 0.70, because
  identification confidence and value confidence are now defined separately.
- Purchase and replacement figures were not treated as resale. G3 passed, and the receipt case's estimate differed
  from the purchase price.
- Jewelry anchoring diagnostic (PE-001): the answer that could see the historical appraisal amount was lower than the
  answer with that amount masked. That is no sign of upward anchoring, but one run each can't separate anchoring from
  run-to-run variation.

### Valuation unit and quantity

- PE-001 found the valuation unit was unstable before 1.3. For the same item, one stage valued one unit and the next
  valued the pair, while the app multiplies the AI value by quantity.
- With the 1.3 request (quantity and owner context sent explicitly), all 15 non-1.2 cases returned a classifiable
  per-unit basis, and the exact-repeat case matched. The quantity-1 complete service was valued as the whole service.
  The old 1.2-format request produced an ambiguous unit (G4 still passed, because the app does not preselect an
  ambiguous estimate).

### Technical behavior

- **Reliability:** all 16 live cases returned HTTP 200 on the first pass, with no retries or repairs. Latency was
  7.7 to 11.5 s per analysis, well within the iOS timeout.
- **Cost of evidence:** in PE-001, one extra photo added about 1,180 input tokens, 0.9 s and $0.001. Two document
  pages added about 2,360 input tokens. Thinking tokens, not images, dominate cost.

## 4. Limitations

- One run per case. No result is a measured effect size, and run-to-run variation was not measured.
- Sample sizes are small: 13 pilot analyses, 21 analyses in the 1.3 rounds, and two items with real sale benchmarks.
- One model (`gemini-3.6-flash`). Results may not carry over to other models.
- The pilot photos were only 768x1024, so the evaluation could not show whether resizing full-resolution iPhone photos
  to the 2048 px cap loses useful detail.
- Documents in the 1.3 matrix were synthetic. Only PE-001 used a real appraisal.
- The G8 blind human rubric is recorded as pending in the scorer. The release decision rested on the automated gates,
  Addendum A1, the Stage 5B regression and Bruce's review of the results.
- Open issue accepted for release: for the sparse text-only case, Stage 5B now returns a broad, low-confidence range
  (value confidence 0.2) that is preselected, where it previously returned no estimate.
- Google keeps paid Gemini prompts for a limited period for abuse monitoring. That is outside LTC's control and is
  disclosed in the Privacy Policy.

## 5. Product decisions in LTC 1.3

- **Supplementary evidence:** up to 3 extra photos and 1 document per analysis, only when the owner selects them. A
  PDF's first 10 pages are rendered to images on the device. An image document is sent as one image. Photos and pages
  are re-encoded on the device, which removes GPS and camera metadata.
- **Gateway v2:** the gateway uses the v2 prompt only when a request carries context or supplementary evidence. 1.2
  requests behave as before.
- **Valuation basis:** review classifies each estimate as per unit, group, or ambiguous.
  - Group estimates are split equally per unit and are not preselected.
  - Ambiguous estimates are never applied.
  - A warning flags a group price on a single item.
- **Provenance and date rules:**
  - The prompt has date rules, and an era that names a specific year is not preselected.
  - Owner claims are treated as the owner's, and conflicts with the evidence are reported.
  - The identifier check ignores ordinary year ranges.
  - Document-derived details are flagged.
- **Confidence:** identification confidence and value confidence are defined separately. The app shows "Value
  confidence: X" and states "A preliminary resale estimate, not an appraisal."
- **Apply correctness:**
  - The primary photo is the earliest one added.
  - The brand is applied.
  - Description provenance (owner text, prior AI text, edited text) is preserved.
  - Nothing changes until the owner chooses what to apply.
- **Consent and privacy:**
  - The AI disclosure is now version 2 and covers extra photos and documents.
  - Gateway logs are metadata only.
  - The Privacy Policy was updated (published November 2026).

## 6. Retained evidence and tooling (local, not in this repository)

| What | Where |
|---|---|
| Plans, stage reports, privacy review, release preflight | `~/Documents/LTC_Discovery_2026-11-04/*.md` |
| Evaluation runner, case matrix, synthetic-document generator, preserved bridge test | `~/Documents/LTC_Discovery_2026-11-04/eval13/` (see `README.md`, `BRIDGE_README.md`) |
| Local gateway stub, UI driver, deploy config check and smoke test | `~/Documents/LTC_Discovery_2026-11-04/build/`, `deploy/` (see `RETAINED_TOOLS.md`) |
| Private inputs, sealed ground truth, live results (1.3 evaluation) | `~/Documents/LTC_Eval13_Private/` (mode 700) |
| Addendum A1 and Stage 5B inputs, ground truth, results | `~/Documents/LTC_Eval13_Addendum_A1/`, `~/Documents/LTC_Eval13_Stage5B/` |
| PE-001 pilot harness and findings | `ai_eval/` on the local `ai-eval-harness` branch and worktree (`results/20261104-115305_evidence_pilot_live/`) |

## 7. Reproducing the evaluation

1. Use a local checkout at the release commit (or a later one). Copy `eval13/Eval13BridgeTests.swift` into
   `LegacyTreasureChest/LegacyTreasureChestTests/` without committing it, and check that it still compiles.
2. Create a simulator. Write its UDID where `runner.py` expects it (`build/sim_udid.txt`), and let the first run
   rebuild DerivedData.
3. Run offline first, with no Gemini calls:
   - `runner.py check`, then `prepare`.
   - `run --mock` for the neutral, good and bad scenarios.
   - `review`, then `score`.
   - `test_runner.py`.
4. A live run needs Bruce's explicit authorization. It takes the Gemini key on stdin, has a spending cap, and
   requires a sealed ground truth. Use the same 16-case matrix and compare against the gates above. For a model
   change, rerun the full matrix plus the A1 and Stage 5B cases.
