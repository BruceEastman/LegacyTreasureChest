# Prospective Enhancements

Ideas recorded for later consideration. Nothing here is scheduled or implemented. Each entry
should be justified by real usage or evaluation evidence before it moves to the roadmap.

---

## PE-001: Supporting photos for Improve with AI

**Recorded:** 2026-11-03
**Status:** Proposed. Not implemented. No production code changes.
**Priority:** After the Gemini 2.5 Flash migration (deadline 2026-12-01).

### Idea

Let Improve with AI accept supplementary photos of an existing item, in addition to the
primary photo. For example:

- maker labels and tags
- hallmarks and silver marks
- artist signatures
- china and crystal backstamps
- serial numbers, model plates and date codes
- construction details (rug backs and knots, dovetails, stitching, movement)

### Why

Many identification and valuation errors come from information that one overview photo
can't show. The Phase 2 photo collection already includes cases where the key evidence is
missing from the primary photo: china and crystal patterns without a backstamp, a rug shown
only in close-up, and a dealer-branded sewing machine.

### Evaluation plan (before any build decision)

Use the `ai_eval` harness on the same items to compare three workflows:

1. **Primary photo only** (current photo analysis, no text)
2. **Primary photo plus text** (current Improve with AI with the title and description)
3. **Primary photo plus supporting photos** (with and without text)

Compare identification accuracy, unsupported claims, valuation realism against known sold
prices, latency, and token cost. `items.csv` already has a `supporting_photos` column, and
`build_suite.py` already produces the photo-only and photo-plus-text variants. The third
workflow needs a harness-only request builder that sends several images, which the current
`/ai/analyze-item-photo` contract doesn't support.

### Things to decide later

- **Backend contract:** a new optional `supportingImagesJpegBase64` list, or a new endpoint.
  Either way the change must stay backward compatible with existing iOS builds.
- **Prompts:** how to label each supporting photo's role (label, mark, signature, detail).
- **Limits:** caps on photo count and size, given latency (iOS 35s timeout) and token cost
  (about 1,120 tokens per image at Gemini 3 default resolution).
- **iOS:** how supporting photos relate to the item's existing `ItemImage` records, and
  whether the user picks the role for each photo.
- **Privacy:** supporting photos are covered by the same cloud-processing consent as the
  primary photo.
