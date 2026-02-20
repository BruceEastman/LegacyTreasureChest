# Legacy Treasure Chest — Export System Plan of Record (v1)

**Status:** Active  
**Scope:** On-device PDF generation only  
**Philosophy:** Advisory, not legal archive  
**Last Updated:** 2026-02-17  

---
**Update** Update to this plan reflecting the work alreacy accomplished 

---

## Estate Snapshot — Disposition Snapshot v2 (Current State)

As of this build, the Estate Snapshot Report reflects the unified **LiquidationState (Pattern A)** model across:

- Items  
- Sets  
- Batches  

### Snapshot Includes

- Estate total (item-based, conservative value × quantity)
- Beneficiary rollups (Legacy items)
- Category rollups
- Top-valued items (Legacy and Liquidate)
- **Disposition Summary (v2)**
  - Status counts:
    - Not Started
    - Has Brief
    - In Progress
    - Completed
    - On Hold
    - Not Applicable
  - Active Brief count
  - Active Plan count
  - Value rollups for:
    - Items
    - Sets (conservative value derived from member items × membership quantity)
    - Batches (staging view of linked items/sets)

### Advisory Positioning

Snapshot reflects the **current catalog state** at time of generation.

- Reports are generated on-device.
- No historical archive is maintained.
- Regeneration at a later date may produce different results if the underlying inventory has changed.
- Legacy Treasure Chest provides advisory reporting and does not function as a legal record system.

---

# 1. Core Philosophy

Legacy Treasure Chest (LTC) is an advisory physical estate planning system.

Exports:

- Reflect the **current state** of the estate at the time of generation
- Are generated **on-device**
- Are not immutable legal records
- Do not provide historical versioning
- Do not attempt to preserve export history
- Do not create audit-trail obligations

Every export must clearly state:

> “This report reflects the current state of the estate as of [Date].”

The burden of preserving a generated report lies with the recipient.

---

# 2. Audience Model

Exports are audience-driven.

## 2.1 Beneficiaries

Two use cases:

### A. Final Allocation Report (vFuture)
- Items assigned to that beneficiary
- Photos
- Description
- Quantity
- Estimated value (clearly labeled)
- No liquidation instructions
- No estate totals

### B. Consideration List (vFuture)
- Curated items for review
- May vary per recipient
- Advisory tone
- No operational instructions

---

## 2.2 Sales / Consignment / Luxury Hub Partners (vFuture)

- Curated asset packet
- Full detail (description, photos, documentation)
- Estimated conservative resale value included
- No executor checklist logic in v1
- Audience framing added in later phase

---

## 2.3 Executor / Attorney

This is the primary focus of Exports v1.

Two reports:

### 1. Executor Snapshot Report
- Estate totals
- Disposition summary
- Beneficiary summaries
- Category summaries
- Top valued assets
- Timestamp
- Advisory disclaimer

### 2. Detailed Inventory Report
- Complete list of cataloged assets
- Category
- Estate path (Legacy / Liquidate)
- Beneficiary (if assigned)
- Quantity
- Unit value
- Total value
- Timestamp

---

## 2.4 Operational Liquidation Packets (vFuture)

- Set/Lot/Batch-specific
- Includes readiness checklists
- Includes disposition preparation steps
- Includes partner preparation guidance
- Action-oriented

Not included in Exports v1.

---

# 3. Scope Definition — Exports v1 Complete

Exports v1 is complete when:

- [ ] Executor Snapshot is polished and disposition-aware (Items, Sets, Batches/Lots if supported)
- [ ] Detailed Inventory is clean and multi-page safe
- [ ] Advisory timestamp statement included
- [ ] Footer metadata included (Generated On, Schema Version)
- [ ] Language tone consistent and professional
- [ ] No misleading references to unsupported entity types
- [ ] No export history model
- [ ] No snapshot persistence

---

# 4. Explicit Non-Goals (v1)

- No export history tracking
- No immutable snapshot storage
- No version control
- No legal audit guarantees
- No embedded liquidation checklists
- No saved curated packet models
- No external collaboration workflows

---

# 5. Sequencing Plan

## Phase 1 — Executor Snapshot v1 Polish
- Tighten section hierarchy
- Add advisory timestamp
- Add schema/version footer
- Clean language
- Ensure multi-page spacing correctness

## Phase 2 — Disposition Snapshot v2
- Reflect true Disposition Engine logic
- Include Items + Sets + Batches/Lots
- Replace beneficiary heuristic where necessary

## Phase 3 — Curated Asset Packet (Neutral v1)
- Item selection-based packet
- Photos and details
- No operational overlays
- No checklist logic

---

# 6. Design Principle

Exports are not different documents.

They are:

> Structured views over the estate model, tailored by audience and intent.

Complexity must not precede clarity.

---

# 7. Category Commitment

LTC remains:

- Advisory
- On-device
- Planner-controlled
- Non-archival
- Executor-friendly
- Trust-focused

Not a legal compliance system.
