# Execution Mode v1 — Specification

## Purpose

Execution Mode v1 provides a structured, executor-friendly way to **carry out** a prepared Batch.  
It builds directly on Batch v1 and assumes that planning and readiness have already occurred.

Execution Mode does **not** automate selling. It supports *doing the work*.

---

## Preconditions (When Execution Mode is Relevant)

Execution Mode is intended for batches where:
- Most entries have a resolved disposition
- Lots are assigned
- The batch is approaching Active status

Execution Mode may still be entered early, but warnings may be shown.

---

## Core Design Principles

- **Execution is per Lot**  
  Lots are the unit of physical work (labeling, staging, listing, delivery).

- **Checklist-driven, not task-freeform**  
  Executors want to see “what’s left,” not invent tasks.

- **State is lightweight and reversible**  
  Execution progress can be reset or corrected.

- **No automation in v1**  
  Execution Mode assists humans; it does not act on their behalf.

---

## Execution Mode Entry Points

### Batch Level
- “Begin Execution” button shown when:
  - At least one lot exists
- Button navigates to **Execution Overview**

### Lot Level
- Lots list gains an “Execute” affordance
- Each Lot has its own execution state

---

## Execution Overview (Batch-Level)

Shows:
- Batch name + metadata
- Lots with:
  - Item / Set counts
  - Execution progress (% complete)
- Global execution warnings:
  - Undecided entries
  - Unassigned lots
  - Incomplete execution steps

Purpose:
> “Where are we overall?”

---

## Lot Execution View (Core of v1)

Each Lot has a **standard checklist**, derived from its contents.

### Example Default Checklist (v1)

Checklist items are **not configurable yet**.

**Preparation**
- ☐ Review items and sets in this lot
- ☐ Confirm disposition choices
- ☐ Add handling notes if needed

**Documentation**
- ☐ Verify photos exist for all items
- ☐ Add missing photos (if discovered during execution)

**Staging**
- ☐ Physically group items
- ☐ Label items with lot number
- ☐ Note location (room / storage area)

**Ready**
- ☐ Lot is ready for sale / handoff

Each checklist item has:
- Boolean completion
- Optional timestamp
- Optional executor note

---
### “Ready” Semantics (v1)

- “Lot is ready for sale / handoff” is the **final checklist item**
- Marking it complete indicates executor confidence, not system validation
- No additional state transitions occur when a lot is marked Ready


## Execution State Model (v1)

Execution state is **separate from planning**.

### New lightweight model (conceptual)

- ExecutionState
  - batch (or lot) reference
  - checklistItems [id, completed, completedAt, note]

v1 may embed this directly on Lot context rather than as a standalone entity.

---
### Persistence Rules (v1)

Persisted per checklist item:
- `completed` (Boolean)
- `completedAt` (Optional timestamp)
- `note` (Optional free text)

Derived (not persisted):
- Lot completion percentage
- Batch completion percentage
- Execution warnings

### Execution State Ownership (v1)

- Execution state is owned at the **Lot level**
- Each Lot has exactly one execution checklist
- Batch-level execution status is **derived** from its Lots
- No separate batch execution state is persisted in v1


## What Execution Mode v1 Does NOT Do

- No partner handoff
- No listing creation
- No pricing changes
- No accounting
- No AI-generated execution guidance
- No customization of checklist steps

Execution Mode v1 ends when:
> “All lots are marked Ready.”

---

## Relationship to Future Versions

### Execution Mode v2+ may add:
- Partner-specific checklists
- Photo capture during execution
- Label printing
- Exportable lot summaries
- AI execution hints

v1 intentionally stays minimal to validate workflow.

---

## Success Criteria for Execution Mode v1

Execution Mode v1 is successful if:
- A non-technical executor can:
  - Open a batch
  - Pick a lot
  - Follow a checklist
  - Know when they are “done”
- No batch data model changes are required
- No automation assumptions are baked in
