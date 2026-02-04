Context:
- I am actively using LTC to build my real household estate plan.
- No new features are being added unless strictly required.
- This session is about fixing or refining something I encountered during real use.

Trigger (what happened):
- [Describe the exact moment or decision where something felt wrong, confusing, or insufficient]

Expectation:
- What I expected the system to help me do or clarify
- What it actually did instead

Scope (best guess):
- [ ] UX copy / language
- [ ] Flow / sequencing
- [ ] Execution Mode
- [ ] Lot / Set / Batch semantics
- [ ] Export
- [ ] Data model
- [ ] Unsure

Constraints:
- Prefer smallest possible change
- No new concepts unless unavoidable
- Advisor, not operator principle must remain intact

Relevant artifacts (if known):
- Screen / View: (e.g. EstateDashboardView, Lot Execution View)
- Model: (e.g. LiquidationBatch, Lot, ExecutionState)
- Doc: (e.g. EXECUTION_MODE_v1.md, ROADMAP.md)

Question:
- Is this a bug, a missing affordance, or a design flaw?
- What is the smallest correct fix?
# DOCUMENTS that may be needed/attached
High-value docs to keep referencing
You do not need all of them every time — but mentioning which one applies is gold:
- ROADMAP.md
→ for intent, gates, and “are we allowed to do this yet?”
- EXECUTION_MODE_v1.md
→ for anything involving lots, readiness, or executor behavior
- ARCHITECTURE.md
→ for “where should this live?” and “what layer owns this?”
- DISPOSITION_ENGINE.md
→ when Local Help, partners, or Google Places semantics are involved

You do not need to paste these every time.
Just saying “this touches Execution Mode v1 semantics” is enough to anchor us.

# FIELD_NOTES to be captured for each item

## Observations
- [date] Brief description of friction

## Questions Raised
- Does the system assume X when I assumed Y?

## Potential Changes (Do Not Implement Yet)
- Maybe lot instructions should appear earlier?
