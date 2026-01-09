# Legacy Treasure Chest — Architecture

**Last Updated:** 2026-01-09 
**Status:** ACTIVE (single-user primary, production-quality build)  
**Target:** iOS 18+ (Swift 6, SwiftUI, SwiftData)  
**Core Principle:** Advisor, not operator (no marketplace automation)

---

## 1) Capability Spine (Do Not Wander)

This is the ordering we follow to keep the project coherent as complexity increases:

1. **Item (inventory + content)**
2. **Beneficiary association**
3. **Single-item liquidation**
   - Brief (why / tradeoffs)
   - Plan (what to do)
   - Checklist (execution)
4. **Disposition Engine**
   - Local partner discovery
   - Outreach preparation
5. **Sets**
   - Sell-together / lot logic
   - Set-level summaries
6. **Estate Sale / Batch Exit**
   - Select items
   - Generate agent-ready package
   - Beneficiary handoff support

---

## 2) Architectural Stance (Current)

### 2.1 Cloud-first AI (Gemini via backend gateway)
Core flows rely on structured JSON outputs and photo understanding, so cloud AI is primary—implemented behind a backend gateway so secrets never ship in the iOS app.

### 2.2 Provider-agnostic AI façade
The iOS app should depend on an abstraction (AI façade) so UI and domain logic remain stable if the backend changes model/provider.

### 2.3 Apple Intelligence is supplemental
Useful later for writing polish, Siri/App Intents, and other OS-level conveniences—**not** the primary engine for structured JSON liquidation/valuation workflows.

### 2.4 Single-user focus
SwiftData local-first. CloudKit and multi-user sharing are intentionally not near-term.

---

## 3) System Overview

LTC is a two-part system:

### 3.1 iOS App (SwiftUI + SwiftData)
- Primary UX and local persistence
- Media stored on disk (filesystem) with metadata in SwiftData
- Persists liquidation artifacts as versioned JSON records

### 3.2 Backend AI Gateway (FastAPI)
- Holds model keys and configuration (Gemini primary)
- Enforces DTO contracts (schema validation) and normalizes model variability
- Provides endpoints for analysis/brief/plan generation
- **Internal structure is now modular (while preserving the single gateway concept):**
  - `app/ai/util/` — time + JSON parsing helpers used across routes/services
  - `app/ai/prompts/` — prompt construction (strict JSON, no markdown)
  - `app/ai/normalization/` — lightweight normalizers/repair helpers to reduce model variability

---

## 4) Data Model (SwiftData) — Source of Truth

This section reflects the actual `LTCModels.swift` entities.

### 4.1 User
**`LTCUser`**
- Owns:
  - `items: [LTCItem]`
  - `beneficiaries: [Beneficiary]`
  - `triageEntries: [TriageEntry]`
  - Legacy sets: `sets: [LTCSet]` (temporary)
  - New sets: `itemSets: [LTCItemSet]`
  - Batches: `liquidationBatches: [LiquidationBatch]`

### 4.2 Item + Content Hub
**`LTCItem`**
- Core fields: `name`, `itemDescription`, `category`, `value` (unit), `quantity`
- AI-related optional fields:
  - `llmGeneratedTitle`, `llmGeneratedDescription`
  - `suggestedPriceNew`, `suggestedPriceUsed`
- Item-level disposition/workflow (kept):
  - `disposition: ItemDisposition` (Legacy vs Liquidate)
  - `liquidationStatus: LiquidationStatus`
  - `selectedLiquidationPath: LiquidationPath?`
- Relationships:
  - Media: `images`, `documents`, `audioRecordings`
  - Beneficiaries: `itemBeneficiaries`
  - Valuation: `valuation` (single latest snapshot)
  - **Pattern A**: `liquidationState` (new)
  - Set membership (new): `setMemberships`
  - Legacy set membership: `set` (temporary)
  - Legacy liquidation: `liquidationBriefs`, `liquidationPlan` (temporary)

**Design note:**
- `value` is **unit value**. Total value = `value × quantity`.
- `quantityInSet` can differ from item quantity (via membership) when needed.

### 4.3 Media Entities
- **`ItemImage`** (file path + createdAt)
- **`Document`** (file path + type + original filename)
- **`AudioRecording`** (file path + duration + optional transcription)

### 4.4 Beneficiaries (junction model)
- **`Beneficiary`** owned by user
- **`ItemBeneficiary`** junction linking item ↔ beneficiary
  - `accessPermission: AccessPermission`
  - optional `accessDate`
  - `personalMessage`
  - `notificationStatus: NotificationStatus`

### 4.5 Valuation (single latest snapshot)
**`ItemValuation`**
- `valueLow`, `estimatedValue`, `valueHigh`, `currencyCode`
- `confidenceScore`, `valuationDate`
- `aiProvider`, `aiNotes`
- `missingDetails: [String]`
- `userNotes` (persisted “More Details for AI Expert”)

---

## 5) Liquidate Architecture (Pattern A)

The Liquidate module stores “AI artifacts” as versioned records and keeps execution state in a plan record.

### 5.1 LiquidationState Hub
**`LiquidationState`**
- One “hub” per liquidation owner:
  - `ownerType: LiquidationOwnerType` = `.item | .itemSet | .batch`
  - `status: LiquidationStatus`
- Owns history:
  - `briefs: [LiquidationBriefRecord]`
  - `plans: [LiquidationPlanRecord]`
- Active selections:
  - `activeBrief` = first where `isActive`
  - `activePlan` = first where `isActive`

**Rule:** Exactly one of these should be set (enforced in business logic):
- `item: LTCItem?`
- `itemSet: LTCItemSet?`
- `batch: LiquidationBatch?`

### 5.2 BriefRecord (immutable)
**`LiquidationBriefRecord`**
- immutable, versioned JSON payload:
  - `payloadVersion` (e.g., `brief.v1`)
  - `payloadJSON: Data`
- metadata:
  - `aiProvider`, `aiModel`
  - optional `inputFingerprint` for dedupe/reproducibility
- `isActive` supports “current brief”

### 5.3 PlanRecord (mutable execution plan)
**`LiquidationPlanRecord`**
- versioned JSON payload:
  - `payloadVersion` (e.g., `plan.v1`)
  - `payloadJSON: Data` (checklist state + constraints snapshot)
- execution status:
  - `status: PlanStatus`
  - chosen path: `chosenPath: LiquidationPath`
- lineage:
  - optional `derivedFromBriefRecordId`

### 5.4 Legacy liquidation models (temporary)
Still present for migration/compat:
- `LiquidationBrief` (legacy)
- `LiquidationPlan` (legacy)
- `LTCSet` (legacy set type)

---

## 6) Sets and Grouping

### 6.1 New Sets: LTCItemSet + Membership
**`LTCItemSet`**
- identity + context:
  - `name`, `setType: SetType`
  - optional `story`, `notes`
  - `sellTogetherPreference: SellTogetherPreference`
  - `completeness: Completeness`
  - optional `estimatedSetPremium`
- relationships:
  - owned by user
  - `memberships: [LTCItemSetMembership]`
  - **Pattern A** liquidation: `liquidationState`

**`LTCItemSetMembership`**
- join model enabling future flexibility:
  - optional `role` (string)
  - optional `quantityInSet`
  - links `item` ↔ `itemSet`

### 6.2 Legacy Sets: LTCSet (temporary)
Older v1 set entity remains temporarily for transition:
- direct `items: [LTCItem]`
- legacy briefs/plans

---

## 7) Estate Sale / Batch Exit (Data model foundation)

**`LiquidationBatch`**
- lifecycle:
  - `status: LiquidationBatchStatus`
  - `saleType: LiquidationSaleType`
- planning:
  - optional `targetDate`
  - optional `venue: VenueType`
  - optional `provider` (e.g., estate sale company)
- relationships:
  - owned by user
  - `items: [BatchItem]`
  - **Pattern A** liquidation: `liquidationState`

**`BatchItem`**
- links `batch` ↔ `item`
- batch-context overrides:
  - `disposition: BatchItemDisposition` (include/exclude/donate/trash/etc.)
  - optional `lotNumber`, `roomGroup`
  - optional pricing hints: `priceFloor`, `priceTarget`
  - notes: `handlingNotes`, `sellerNotes`

This creates the correct foundation for “Estate Sale / Batch Exit” without forcing the UI/flow prematurely.

---

## 8) Triage (exists, not yet primary)

**`TriageEntry`**
- text-only “inbox” concept:
  - `rawText`
  - `inputsJSON` (qty/condition/goal/location)
  - `resultJSON` (triage output)
  - optional `convertedItem: LTCItem?`

Important: triage exists in the model but is not currently the primary workflow. The system already supports liquidation for text-only items without using triage.

---

## 9) Modules (Practical Grouping)

### Features
- Items (manual + AI-assisted + batch add)
- Media (Photos, Documents, Audio)
- Beneficiaries
- Liquidate (Brief/Plan/Checklist + records persistence)
- Sets (new model + membership)
- Batch / Estate Exit (data model foundation)

### Cross-cutting
- Data (SwiftData models)
- Core utilities (Theme, FeatureFlags, MediaStorage)
- - AI façade + backend provider
- Backend AI Gateway (FastAPI + Gemini + schema enforcement)
  - AI internals: `app/ai/{util,prompts,normalization}` (modularized; extract-only refactor underway)


---

## 10) Disposition Engine (Next Major Capability)

Disposition Engine extends Liquidate execution support:
- Given item/set/batch context + location + chosen path,
  - recommend partner type
  - return vetted local options + trust signals
  - generate outreach-ready content (email subject/body, attachment list)
- Remains advisor-oriented: prepare the handshake; user initiates contact.

---

## 11) Out-of-Scope (Near Term)

- marketplace automation/posting APIs
- multi-user sharing / CloudKit collaboration
- complex CRM pipelines for negotiations and sales ops

---

## 12) Related Docs
- `README.md` (most current status)
- `LIQUIDATION_STRATEGY.md`
- `DISPOSITION_ENGINE.md`
- `DECISIONS.md`
