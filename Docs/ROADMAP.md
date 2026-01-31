# Legacy Treasure Chest — Roadmap to Production

**Last Updated:** 2026-01-30

This roadmap reflects the *actual state* of Legacy Treasure Chest today and defines a disciplined path from a proven single‑user system to a small, controlled external trial. It intentionally prioritizes **executor‑grade completion, clarity, and reversibility** over speed or monetization.

> **Core principle:** Advisor, not operator. Ship only what increases confidence for real people doing real estate work.

---

## Capability Spine (Locked)

The original capability spine has been followed closely and remains the organizing backbone of the product:

1. **Item (inventory + content)**
2. **Beneficiary association**
3. **Single‑item liquidation**

   * Brief (why / tradeoffs)
   * Plan (what to do)
   * Checklist (execution)
4. **Disposition Engine**

   * Local partner discovery
   * Outreach preparation
5. **Sets**

   * Sell‑together / lot logic
   * Set‑level summaries
6. **Estate Sale / Batch Exit**

   * Select items and sets
   * Lot grouping
   * Executor‑grade overrides

This spine is considered **complete through #6 (Batch v1)**.

---

## Production Gates (New)

To avoid scope creep and premature distribution, development now proceeds through **explicit production gates**. A gate must be completed and stable before moving to the next.

---

## Gate 1 — Execution Mode v1 (In Progress)

**Goal:** Enable a non‑technical executor to *finish* a prepared batch.

**Definition of done:**

* Execution is **lot‑centric**
* Each lot has a **standard, non‑configurable checklist**
* Checklist state is:

  * Lightweight
  * Reversible
  * Separate from planning
* A user can clearly answer: *“Which lots are done, and which are not?”*

**Explicit non‑goals:**

* No automation
* No partner handoff
* No pricing or listing changes
* No AI execution guidance

> Execution Mode v1 is the final internal‑use feature required before involving external users.

---

## Gate 2 — Externalization Readiness (Planned)

**Goal:** Make the system safe, predictable, and understandable for people who are not the original builder.

This phase is intentionally small and finite.

### Scope

* UX clarity sweep (no dead ends, clear empty states)
* Executor‑friendly warnings (advisory, not blocking)
* Failure tolerance verification (AI unavailable, partial data, abandoned flows)
* First‑run explanation:

  * What the app *does*
  * What it *does not do*
  * How it is meant to be used

**Outcome:**

* A trusted person can use the app without hand‑holding
* No irreversible actions
* No confusion about completion

---

## Gate 3 — Exports & External Views v1 (Planned)

**Goal:** Allow LTC to safely and clearly communicate *outward* once the physical estate is documented.

This is not sharing or collaboration. It is **controlled externalization** of read‑only information.

### Export Units (v1)

* **Item export**

  * Complete item record
  * Photos, documents, notes, valuation context
* **Set export**

  * Cohesive summary + member items
* **Batch / Lot export**

  * Executor‑ready packet
  * Lot grouping, handling notes, readiness state
* **Beneficiary summary export**

  * For attorneys or executors

### Format (v1)

* PDF or bundle‑based
* Purpose‑specific layout (dealer, executor, advisor)
* Designed for email or message attachment

**Non‑goals:**

* No portals
* No access control
* No two‑way sync

---

## Gate 4 — Controlled External Trial (TestFlight)

**Goal:** Learn how real people actually use the system.

### Characteristics

* 5–10 trusted users
* TestFlight distribution only
* No marketing
* No monetization
* No promises

### What We Observe

* Where users hesitate
* What they finish vs abandon
* Which exports they use
* Which parts create confidence

This gate informs *all* future decisions.

---

## Instrumentation (Plan, Not Enforcement)

Before or during the external trial, lightweight usage markers may be added:

* Has created items
* Has created a batch
* Has entered execution mode
* Has completed a batch

All instrumentation is:

* Local‑first
* Anonymous
* Observational only

---

## Monetization & Licensing (Intentionally Deferred)

No licensing, paywalls, or business logic will be implemented until:

* External usage patterns are observed
* Value is clearly demonstrated
* The buyer (owner vs executor) is understood

This is a **deliberate decision**, not an omission.

---

## Guiding Principle Going Forward

> Finish real work first. Then invite others.

This roadmap exists to protect focus, preserve trust, and ensure that Legacy Treasure Chest matures into a production‑quality, executor‑grade system before it ever asks anyone else to rely on it.
