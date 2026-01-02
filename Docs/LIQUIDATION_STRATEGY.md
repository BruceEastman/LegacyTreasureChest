# Liquidate Module — Strategy, Architecture, and Implementation Guide

**Status (as of 2026-01-01):** Single-item Liquidation is working end-to-end (Brief → Plan → Checklist execution) and is now wired into the main UI. Sets / batch liquidation and formal Triage are **not implemented yet**.

This document is the **implementation guide** for Liquidate. It is intentionally practical: what exists, what is deferred, and the milestones that keep us from wandering.

---

## 1. Product intent (non-negotiables)

### 1.1 Advisor, not operator
Legacy Treasure Chest is a **decision-support system**. Liquidate:
- **Does**: analyze tradeoffs, recommend a path, produce an actionable plan, and prepare “handshake” materials.
- **Does not**: post listings, negotiate with buyers, automate marketplace actions, or guarantee prices.

### 1.2 Conservative and trust-first
Liquidate guidance is conservative by design:
- Focus is **fair-market resale** and **net proceeds vs effort**, not optimistic retail.
- Outputs must always be explainable: *why this path*, *what assumptions*, *what missing info*.

---

## 2. Vocabulary (used across backend + iOS)

- **Brief**: strategic recommendation and tradeoffs for a liquidation decision.
- **Plan**: operational checklist tailored to the selected path.
- **Checklist execution**: the user marks tasks complete; results are persisted.
- **Disposition Engine**: “Local Help” partner discovery + outreach pack (planned; see DISPOSITION_ENGINE.md).
- **Triage**: prioritization (“what should I deal with first?”) (planned; see §7).

---

## 3. Current capabilities (implemented)

### 3.1 Single item workflow
For a single item, the app supports:
1. Generate **Brief** (backend-first)
2. Choose **Path** (A/B/C/Donate, etc.)
3. Generate **Plan** (backend-first)
4. Execute checklist tasks and persist state

### 3.2 Photo optional
Liquidation can run on a text-only item (no photo required). This is a feature, not a compromise:
- It ensures the workflow works during early inventory creation and later refinement.

### 3.3 Persistence approach
Liquidation artifacts are persisted as structured JSON records (SwiftData stores the record + JSON payload). This supports:
- repeatability
- re-generation
- future evolution of schemas

---

## 4. Liquidate architecture (conceptual layers)

Liquidate should be understood as three layers:

1) **Decision Support**
- Brief generation
- Path selection

2) **Execution Support**
- Plan generation
- Checklist execution

3) **Tracking**
- active brief/plan selection
- completion status and notes (as implemented in checklist records)
- later: partner contact tracking and outcomes

---

## 5. UI placement rules (current + future-safe)

- Liquidate is a **“next step”** on Item Detail, not core metadata.
- Liquidate screens must remain:
  - readable
  - scrollable
  - resilient to long content
  - stable for Boomer users (clear labels, no dense jargon)

---

## 6. Implementation roadmap (do not wander)

This roadmap is the authoritative ordering. If a task appears “fun” but is out of order, it waits.

### Milestone 1 — Single-item liquidation is reliable (DONE)
**DoD**
- Brief generation succeeds reliably (backend-first with friendly errors)
- Plan generation succeeds reliably (backend-first with fallback if needed)
- Checklist execution persists and reloads correctly
- Accessible from normal app UI

**Status:** ✅ Done

### Milestone 2 — Harden single-item UX and observability (IN PROGRESS / NEXT)
**DoD**
- Timing logs (iOS + backend) for Brief and Plan
- Clear retry UX and prevention of double-submit duplicates
- Brief/Plan “active” state clearly visible (what is current vs historical)

**Status:** 🟡 Next

### Milestone 3 — Disposition Engine v1 (PLANNED)
Add “Local Help” inside the Plan:
- partner discovery results (ranked + trust signals)
- outreach packet (email copy + attachments list)

**Status:** ⛔ Planned (depends on Milestone 2)

### Milestone 4 — Sets and batch liquidation (PLANNED)
Introduce true group liquidation:
- sets / lots (user-selected group)
- estate-sale/batch event concept
- batch reporting/export

**Status:** ⛔ Planned (depends on Milestone 3 foundations)

### Milestone 5 — Formal triage (PLANNED)
Triage becomes valuable once multi-item workflows exist:
- “what should I do first?” prioritization
- quick wins and high-friction routing

**Status:** ⛔ Planned (after Milestone 4)

---

## 7. Deferred features (explicitly out of scope until later)

### 7.1 Sets / group liquidation
Not implemented yet. When we implement it, we will introduce a dedicated batch object (e.g., `LiquidationBatch` / `EstateSaleBatch`) rather than forcing it into per-item records.

### 7.2 Formal triage
Not implemented yet. Current behavior is “manual triage” by user choice of item. Formal triage comes after batch exists.

### 7.3 Marketplace automation
Not a goal. The system may recommend channels and prep copy, but it will not post or transact.

---

## 8. Engineering guardrails

- Keep iOS and backend DTOs in strict parity.
- Prefer backend-configured strategy knobs for tuning (especially for Disposition Engine logic).
- Maintain local fallbacks where they improve resilience, but treat backend as the canonical “intelligence” source.

---

## 9. Next actions (when returning to this doc)

When you’re ready for the next wave of implementation work, start here:
1) Finish Milestone 2 hardening tasks (logging, retries, active state clarity).
2) Open DISPOSITION_ENGINE.md and implement v1 partner discovery + outreach endpoints behind a feature flag.
