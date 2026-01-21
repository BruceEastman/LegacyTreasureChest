

### The correct approach

👉 The Bootstrap Prompt should define a **canonical backend + iOS file map** that is assumed to exist **unless explicitly changed**.

Then, in each category conversation:

* I only ask for files **if they differ from the baseline**
* or if a category requires **new data fields or prompt variants**

This turns category work into **controlled extensions**, not scavenger hunts.

---

## 3️⃣ Final, refined Bootstrap Prompt Template (production-ready)

Below is a **clean, stable Bootstrap Prompt** you can reuse verbatim for every category.

You only change:

* `<CATEGORY_NAME>`
* the Gemini / research conversation you paste in

---

# **Bootstrap Prompt — Category Disposition Implementation (Canonical)**

## Project Context

You are assisting with **Legacy Treasure Chest (LTC)** — an AI-native iOS app (iOS 18+, SwiftUI, SwiftData).

**Core principle:**

> **Advisor, not operator. Executor-grade clarity.**

This system already implements:

* **Item and Set scopes**
* **AI-generated Brief → user-selected Plan → Checklist with progress**
* **Disposition Engine = “Execute the Plan”** (partner discovery + outreach prep)

This architecture **must not change**.

---

## Objective for This Conversation

Implement **category-specific disposition intelligence** for:

> **Category: `<CATEGORY_NAME>`**

The goal is to:

* Keep **user experience identical across categories**
* Allow category-specific recommendations (local expert vs hub shipping, consignment vs auction, etc.)
* Avoid architectural drift or special-case flows

---

## Canonical System Flow (Invariant)

1. User creates or selects **Item or Set**
2. User generates **AI Brief**
3. User selects **AI Plan**
4. User executes the Plan via **Disposition Engine**

   * Partner discovery
   * Outreach instructions
   * Logistics guidance

Disposition actions are **gated behind “Plan exists.”**

---

## Inputs I Will Provide

* A **Gemini or research conversation** describing:

  * category market dynamics
  * valuation realities
  * disposition alternatives
* Any **personal heuristics or constraints** I trust

These are **inputs only**, not architectural authority.

---

## Your Required Outputs (in this exact order)

### 1️⃣ Category Disposition Spec (Markdown — authoritative)

Produce:

**`Docs/Categories/<CATEGORY_NAME>_Disposition_Spec_v1.md`**

Must include:

* Subtypes within the category
* Quality bands and decision thresholds
* Liquidity model (local vs hub, condition sensitivity, etc.)
* Default unit of work (item, lot, set, estate batch)
* Brief requirements (value ranges, effort vs return, confidence)
* Plan checklist blocks (reusable + category-specific)
* Disposition partner types + trust gates + search terms
* Minimum documentation package (photos + metadata)
* Executor-facing copy (warnings, do/don’t, rationale)
* `schemaVersion: 1`

---

### 2️⃣ Architecture Impact Assessment

Identify **exactly what changes are required**, if any, in:

* iOS data models
* iOS UI capture fields
* Backend DTOs / prompts
* Disposition Engine matrix

Prefer **additive, optional fields**.
If no changes are needed, explicitly say so.

---

### 3️⃣ Implementation Plan (Safe & Incremental)

Provide a **3-phase plan**:

* **Phase 1:** data + UI capture
* **Phase 2:** Brief / Plan generation
* **Phase 3:** Disposition “Execute Plan”

Each phase must be independently testable.

---

### 4️⃣ Regression Checklist

Provide a short checklist to confirm:

* Existing categories still work
* Brief → Plan → Checklist flow remains intact
* Disposition Engine behaves as expected

---

## Canonical File Map (Assumed Unless Stated Otherwise)

### iOS (always available)

1. `LTCModels.swift` — SwiftData models (Items, Sets, Briefs, Plans)
2. AI Services:

   * `LiquidationAIService.swift`
   * `DispositionAIService.swift`
   * `BackendAIProvider.swift`
3. UI Entry Points:

   * `ItemDetailView.swift`
   * `SetDetailView.swift`
4. Media handling:

   * `MediaStorage.swift`
   * image picker components

### Backend (always available)

5. Liquidation routes:

   * brief generation endpoint
   * plan generation endpoint
   * DTOs
   * prompt selection logic
6. Disposition Engine:

   * partner search route
   * partner discovery services
   * provider implementations
   * `disposition_matrix.json`

If any file deviates from this map, request it explicitly and explain why.

---

## Guardrails

* Do **not** invent new flows
* Do **not** bypass Brief → Plan → Checklist
* Do **not** introduce category-specific UI paradigms
* Do **not** write code unless explicitly asked
* Call out **intentional differences** vs other categories

---

## Conversation Goal

Produce a **Category Disposition Spec** that can be implemented cleanly, consistently, and safely within the existing system.

---

## Final recommendation

You’ve landed on a **very strong methodology**:

* Gemini = research input
* ChatGPT (me) = architecture + spec synthesis
* One canonical bootstrap prompt
* One spec per category
* One invariant user flow

This is exactly how you scale category intelligence without turning LTC into a fragile, bespoke system.

When you’re ready, tell me:
👉 **Which category we do first** (Luxury Clothing is still the best opener),
or paste the Gemini conversation again under this new structure and we’ll generate **Spec v1**.
