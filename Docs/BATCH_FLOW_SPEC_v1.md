# Batch Flow v1 — Estate Sale / Batch Exit (Sets Included)

**Status:** Approved v1 spec
**Date:** 2026-01-28
**Audience:** Boomer owner + Executor
**Principle:** Advisor, not operator (no automated selling, no auto-contact). 
**Capability Spine:** Step 6 — Estate Sale / Batch Exit.  

---

## 1) Purpose

Enable a user/executor to define a **Batch (Estate Sale scope)** consisting of a mix of **Items and Sets** that will be sold in one operational event, producing:

* Clean **scope list** (what is in/out)
* Conservative **value roll-up** (items, sets, total)
* Clear **highlights** for estate sale agent conversations

This v1 does **not** automate transactions or outreach.

---

## 2) Goals (v1)

1. Create/persist a `LiquidationBatch`
2. Add **Items and Sets** to a Batch using two creation modes:

   * **Sell everything not assigned to a beneficiary** (recommended default)
   * **Build a custom sale list** (manual)
3. Support review & edits:

   * Include / Exclude entries
   * Notes and lightweight grouping metadata (room group / handling notes)
4. Show Batch Summary:

   * counts, conservative totals
   * highlight list (top value)
   * specialty-set presence (advisory labeling only)
5. Deterministic behavior; avoid double counting; compile-safe iteration.

---

## 3) Non-goals (v1)

* No pricing tools for estate sales
* No negotiation/CRM tracking (commissions, quotes, etc.)
* No automatic outreach or “send packet”
* No beneficiary workflow beyond eligibility filtering
* No deep “lot numbering” system (optional lightweight fields only)

---

## 4) Definitions

### 4.1 Batch

A **Batch** is a snapshot of the intended scope for a sale event. It does not change:

* the item’s global disposition
* beneficiary assignment
* item/set liquidation artifacts

### 4.2 Eligibility rule (Beneficiaries)

**Items assigned to any Beneficiary are ineligible for inclusion** (they should not show in the eligible selection list).

* “Assigned” means: item has ≥ 1 `ItemBeneficiary` link.
* v1 does **not** allow “override include anyway.”

Rationale: prevents accidental sale of legacy-designated items.

---

## 5) Data Model (SwiftData)

### 5.1 Existing entities (already present)

* `LiquidationBatch`
* `BatchItem` (batch ↔ item join)

### 5.2 New entity required (v1): `BatchSet`

A join model parallel to `BatchItem`.

**Purpose:** represent set-level inclusion with batch context overrides.

**Fields (v1 recommended):**

* Relationship:

  * `batch: LiquidationBatch`
  * `itemSet: LTCItemSet`
* Batch-context state:

  * `disposition: BatchEntryDisposition` (include/exclude/donate/trash)
  * `roomGroup: String?`
  * `handlingNotes: String?`
  * `sellerNotes: String?`
* Optional future-friendly:

  * `lotNumber: String?` (string to avoid premature constraints)

> Note: Reuse the same `BatchEntryDisposition` enum for `BatchItem` and `BatchSet` to keep UI consistent.

---

## 6) Set Inclusion Rules (Deterministic)

### 6.1 Set eligibility (for Mode A auto-fill)

A set is eligible for inclusion if **all of its member items are eligible** (no beneficiaries).

* If any member has beneficiaries:

  * the set is not auto-included
  * eligible loose items can still be included individually (if they have no beneficiaries)

### 6.2 Double-count prevention

If a set is included in a batch, its member items are treated as “covered by the set” for:

* Summary totals
* Highlight lists (unless explicitly designed otherwise)

UI behavior (v1):

* In the “Eligible Items” list:

  * items that are in an included set should be **hidden** or **shown as disabled** with a label:

    > “Included via Set: {Set Name}”

Totals behavior (v1):

* Batch Total = sum(included sets) + sum(included loose items **not** in included sets)

---

## 7) Batch Creation UX (Two modes)

### 7.1 Mode A (default): “Sell everything not assigned to a beneficiary”

Intent: Whole-house estate sale.

Auto-populate scope:

* Include all eligible sets (rule above)
* Include all eligible items not already covered by included sets

Then show Review/Edit.

### 7.2 Mode B: “Build a custom sale list”

Intent: selective downsizing or partial sale.

User manually selects:

* sets
* items

Then show Review/Edit.

---

## 8) Screens (v1)

### Screen 1 — Batch List

* Shows existing batches:

  * name
  * status
  * counts (sets/items)
  * estimated total (conservative)
* CTA: **Create Batch**

### Screen 2 — Create Batch Wizard

Fields:

* Batch name (default: “Estate Sale – {date}”)
* Optional target date
* Mode selector:

  * **Sell everything not assigned to a beneficiary (recommended)**
  * **Build a custom sale list**

### Screen 3 — Batch Scope Builder (Review & Edit)

Two sections:

* **Sets in this sale**
* **Items in this sale**

Each row shows:

* thumbnail (best available representative photo)
* name
* value (conservative)
* include/exclude toggle
* optional: room group / notes entry

### Screen 4 — Batch Summary

* Total estimated value (conservative)
* Item and set counts
* Highlights:

  * Top N entries by value
  * Specialty categories present (advisory tags only)

---

## 9) Conservative valuation rules (v1)

### Item total

Use:

* `ItemValuation.estimatedValue` if present else `LTCItem.value`
* Multiply by `item.quantity`

### Set total

Sum member item totals (as above).

* If set has a “set premium” field, v1 may show it as *advisory only* but **not** add it into totals unless you already have a locked rule.

### Batch total

As defined by the double-count rule.

---

## 10) Milestones & Definition of Done

### B1 — Models + List scaffolding

DoD:

* `BatchSet` model added + migrations compile
* BatchList screen loads and shows batches
* Can create/delete a batch (simple)

### B2 — Eligibility + Mode A auto-fill

DoD:

* Beneficiary filter excludes assigned items from eligible pools
* Mode A auto-fills sets + items correctly
* No double counting in computed totals

### B3 — Mode B manual selection

DoD:

* Select sets/items with search
* Prevent selecting items already covered by included set (disabled or hidden)
* Persist selections via join models

### B4 — Review/Edit + Summary

DoD:

* Include/exclude toggles per entry
* Notes fields persist
* Summary shows correct totals + highlights

### B5 (later) — Batch Brief/Plan + Local Help (estate agent handshake)

Not in v1. Future spec.

---

## 11) Open decisions (resolved for v1)

* ✅ Sets included in v1
* ✅ No beneficiary overrides in v1
* ✅ Two creation modes with the recommended labels above

---

## 12) Implementation notes (guardrails)

* Keep Batch as a “wrapper.” No mutations to item/set global disposition.
* Keep all behaviors deterministic and explainable (no inference).
* Prefer compile-safe incremental implementation (B1 → test → commit, etc.).
