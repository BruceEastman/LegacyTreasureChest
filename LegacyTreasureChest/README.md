# Legacy Treasure Chest
## Status Update (2026-01-09) — Text-Only AI Analysis Now Works

**What’s new**
- The iOS “Improve with AI” flow now supports **text-only analysis** (no photos required).
- The app successfully calls the backend endpoint `POST /ai/analyze-item-text` and receives a valid `ItemAnalysis` response.

**Why this matters**
- The system is now practical for day-to-day household use: you can create items quickly and still get AI help immediately.
- Photos remain recommended for higher confidence, but they are no longer a blocker.

**Key implementation notes**
- Backend: fixed text-only analysis to use a **true text-only prompt** and added minimal JSON normalization.
- Backend model alignment: `ItemAnalysis` requires `title`, `description`, and `category`. The prompt explicitly enforces these keys.

**Next focus**
- **Local Help (Disposition Engine) UI gating:** prevent 422 errors by disabling Local Help until required prerequisites exist (Brief + Plan), and clearly message the user what to do next.

## Current Status (Jan 8, 2026)

### What’s working now
- **Disposition Engine UI v1 is live in the iOS app** (Item Detail → Next Step → **Local Help**) behind a feature flag.
- The UI supports:
  - Running partner search from an **item context**
  - Showing a **ranked list** with **rating**, **review count**, and **distance**
  - Expanding a partner to view **Why recommended** + **Questions to ask**
  - Action links (e.g., **Call** / **Website**) when available
- **Briefs and Plans** work end-to-end (latency noticeable but acceptable for now).

### Known behavior / caveats
- Google Places `places:searchText` can intermittently return **HTTP 400 Bad Request**. Re-running the same search often succeeds. We added basic provider-side debug logging to capture request/response details when it occurs.
- Local Help results are most accurate **after a Brief + Plan exists** (the chosen path and scenario strongly influence partner types and queries).

### Next likely work (in priority order)
1) **Scenario coverage**: Expand `disposition_matrix.json` beyond the current defaults so categories like **Jewelry, Collectibles, Rugs, China/Crystal** map to appropriate partner types and queries.
2) **Product flow clarity**: Treat Local Help as “**Execute the Plan**” (or explicitly guide users that best results come after Plan).
3) **UI polish**: Improve formatting of expanded details and relabel/hide trust/debug details for non-developer users.

## Project Status — January 2026

Legacy Treasure Chest has reached an important milestone:  
**the transition from inventory to action.**

### What’s New

The app now includes a fully functional **Disposition Engine (v1)** that helps users answer:

> *“What should I do with this item, and who locally can help me?”*

Key capabilities now live on the backend:

- Intelligent partner discovery for:
  - Consignment
  - Estate sales
  - Auctions
  - Donation
  - Junk/haul services
- Uses real local businesses (via Google Places New)
- Returns consumer-friendly signals:
  - ⭐ Ratings
  - Number of reviews
  - Distance
- Adds estate-aware guidance:
  - Trust scoring (independent of Google)
  - Reasons for recommendation
  - Questions to ask before proceeding

The system is designed specifically for:
- Downsizing households
- Executors settling estates
- Older adults who need clarity, not complexity

### Current Focus

The backend foundation for disposition planning is now in place.

The next major phase is **UI integration**:
- Making these capabilities visible, understandable, and usable in the iOS app
- Determining where partner discovery lives:
  - Item detail view
  - Liquidation flow
  - Estate dashboard
- Designing a flow that supports *advice first*, not transactions

### What’s Next

Planned near-term work includes:
- SwiftUI screens for disposition recommendations
- Partner comparison and selection
- Guided outreach (email, website, phone)
- Expanding from single-item to **sets / estate-level** disposition

Legacy Treasure Chest is evolving from a catalog into an **active planning assistant**.

## 🧭 Liquidate Roadmap (Do Not Wander)

This is the authoritative ordering for Liquidate development. It matches our current implementation reality:
- **Single-item Liquidate works end-to-end** (Brief → Plan → Checklist execution), including items with **no photo**.
- **Sets / batch liquidation** are **not implemented** yet.
- **Formal triage** is **not implemented** yet.

### Milestones
- ✅ **M1 — Single-item Liquidate vertical slice** (Brief + Plan + Checklist + persistence + main UI entry)
- 🟡 **M2 — Harden UX & observability** (timing logs, retries, avoid duplicates, active state clarity)
- ⛔ **M3 — Disposition Engine v1 (“Local Help”)** (partners search + outreach pack + plan UI section)
- ⛔ **M4 — Sets & batch liquidation** (lots/sets, batch events, batch export)We started on Sets (read above)
- ⛔ **M5 — Formal triage** (prioritize work across many items)
Below is a **ready-to-paste README update** you can append to the **top** of the file. It’s concise, accurate, and sets clear context for future work without over-promising.

## 📌 Project Status Update — Sets v1 & Backend Stabilization

**Date:** January 2, 2026

### Summary

This checkpoint stabilizes the **Sets v1** experience and hardens the backend AI integration for liquidation workflows. The system now reliably supports liquidation analysis for both **Items** and **Sets**, with improved tolerance to LLM variability and no required changes on the iOS client.

### What’s Complete

* **Sets v1 (End-to-End)**

  * Create and edit Sets
  * Select Sets for liquidation
  * Generate AI-powered liquidation briefs and plans
  * UI and data model are sufficient for a first usable version

* **Backend AI Hardening**

  * Liquidation brief and plan endpoints are now resilient to Gemini JSON variability (e.g., wrapped responses, missing fields).
  * Server-side normalization ensures DTO contract compliance before validation.
  * Required fields (`scope`, `generatedAt`, `pathOptions[].id`, etc.) are safely stamped when missing.
  * iOS app remains unchanged and continues to fall back locally only on true backend failures.

* **Location-Aware Foundations**

  * Liquidation briefs now preserve `inputs` (goal, constraints, location).
  * This explicitly supports upcoming **Disposition Engine** work that relies on location to identify local and trusted entities.

* **Documentation Updates**

  * Updated: `LIQUIDATION_STRATEGY.md`, `DISPOSITION_ENGINE.md`, `DECISIONS.md`
  * Added: `ROADMAP.md`
  * Removed obsolete development notes.

### What This Release Is (and Is Not)

* ✅ This is a **stable functional baseline** for Sets.
* ❌ This is **not** the final design for Sets or the Disposition Engine.
* The focus here was correctness, resilience, and learnings from real use—not feature completeness.

### Next Planned Focus (Deferred)

* Refining Set semantics (valuation dynamics, sell-together heuristics)
* Disposition Engine implementation (location → trusted local entities → execution guidance)
* UX refinements based on real household usage

See:
- `LIQUIDATION_STRATEGY.md` for the implementation guide
- `DISPOSITION_ENGINE.md` for the Local Help capability spec
## 🔄 Current Development Status (Snapshot)

**Date:** 2026-01-01  
**Milestone:** Liquidation — Main UI Wired (ItemDetail → Liquidate Workflow)

### ✅ What’s Now Working (New Since Last Snapshot)

#### iOS App (SwiftUI + SwiftData)
- Liquidation is now **accessible from the normal app UI**:
  - `ItemDetailView` includes a bottom **“Next Step → Liquidate”** section.
  - Tapping navigates to `LiquidationSectionView` for the current item.
- `LiquidationSectionView` is now wrapped in a `Form`, making it **fully scrollable and usable as a production screen**.
- Liquidation workflow in the main UI:
  - Generate Brief (**backend-first**, local fallback only on failure)
  - Choose Path
  - Generate Plan (**backend-first**, local fallback only on failure)
  - Persist brief/plan records to SwiftData
- Theme alignment: primary text uses `Theme.text` (no `Theme.textPrimary` token exists).

### Notes
- UI copy / path label polish intentionally deferred until multi-item and estate workflows clarify the final UX structure.

## 🔄 Current Development Status (Snapshot)

**Date:** 2025-12-31  
**Milestone:** Liquidation Engine – Backend + Sandbox Complete, UI Wiring Next

### Overall State
Legacy Treasure Chest is now past core inventory and valuation and has entered the **Disposition / Liquidation phase**. The system is transitioning from “What do I have?” to “What should I do with it?” using an AI-native, backend-first architecture.

This is not an MVP rush. Development is proceeding deliberately toward a **production-quality, long-lived app**, with the developer as the sole user until fully proven.

---

### ✅ What Is Working

#### Backend (LTC AI Gateway – FastAPI)
- AI endpoints implemented and validated via `curl`:
  - `POST /ai/generate-liquidation-brief`
  - `POST /ai/generate-liquidation-plan`
- Gemini responses are:
  - Strictly JSON
  - Schema-validated with Pydantic
  - Repaired once automatically if malformed
- Liquidation models implemented:
  - `LiquidationBriefDTO`
  - `LiquidationPlanChecklistDTO`
  - `LiquidationPlanRequest`
- Backend successfully generates:
  - Strategic liquidation briefs
  - Operational, step-by-step liquidation plans

#### iOS App (SwiftUI + SwiftData, iOS 18+)
- `BackendAIProvider` now supports:
  - `generateLiquidationBrief(request:)`
  - `generateLiquidationPlan(request:)`
- Liquidation DTOs are centralized in `LiquidationDTOs.swift` and aligned with backend schemas.
- `LiquidateSandboxView`:
  - Can generate a Brief and Plan end-to-end
  - Persists AI outputs as JSON into SwiftData records
  - Confirms backend + decoding + persistence all work
- App compiles cleanly after resolving legacy/local method name mismatches.

---

### 🚧 What Is Not Done Yet (Intentional)

- Liquidation is **not yet accessible from normal app flows**.
  - No entry point from `ItemDetailView`
  - Currently only reachable via the Sandbox
- No user-facing “Liquidate” section in the main UI
- No finalized UX for:
  - Choosing a liquidation path
  - Viewing an active brief/plan from Item Detail
- Local heuristic liquidation logic exists only as a fallback and is not the primary path.

---

### 🎯 Next Milestone (Immediate Focus)

**Wire Liquidation into the normal app UI**

Specifically:
- Add a **bottom “Liquidate” section** to `ItemDetailView`
  - Positioned as a *next step*, not core metadata
- Navigate into `LiquidationSectionView`
- Support backend-first:
  - Generate Brief
  - Choose Path
  - Generate Plan
- Persist results to SwiftData and reflect state on the item

This work will touch multiple files and is being done in a **new, clean conversation** with a focused Bootstrap prompt to avoid drift.

---

### 🧭 Architectural Intent (Reaffirmed)

- AI handles analysis, strategy, and repetitive reasoning
- The app acts as an **advisor**, not a marketplace operator
- No direct eBay/Craigslist/etc. integrations
- Clear separation between:
  - Inventory
  - Valuation
  - Disposition
- Design favors clarity and trust for Boomer-age users

### 🔄 Project Status Update — Liquidation AI Backend & Plans (Dec 2025)

This update captures the current, **stable foundation** for the Liquidation module and clarifies what is complete, what is intentionally deferred, and what we will tackle next.

#### ✅ What Is Working (Verified)

**AI Gateway (FastAPI)**

* Single consolidated routes file: `app/routes/analyze_item_photo.py`
* Gemini-backed AI analysis is live and stable
* Supports:

  * **Photo-based item analysis**
  * **Text-only item analysis** (no photo required)
  * **Liquidation Brief generation (AI-native)**

**Item AI Analysis**

* Always returns a valuation (`ValueHints`)
* Category-aware valuation ranges
* Low-confidence + wide range when details are insufficient
* Explicit `missingDetails` list returned for user improvement
* Backend enforces valuation consistency (no silent nulls)

**Liquidation Briefs**

* Generated via AI (Gemini)
* DTO parity with Swift models confirmed
* Validated end-to-end via curl
* Supports:

  * scope: `item` or `set`
  * A/B/C paths + donate / needsInfo
  * Reasoning, confidence, assumptions, missing details
* Backend stamping:

  * `generatedAt`
  * `aiProvider`
  * `aiModel`

**iOS App (SwiftUI + SwiftData)**

* AI Analysis UI restored and improved
* Valuation narrative + range now displays correctly
* “Improve with AI” works for both photo and text-only items
* Local `LiquidationPlanFactory` still active and stable
* Plans currently generated locally by design (not a bug)

---

#### 🧠 Architectural Decisions (Locked In)

* **AI-first, not MVP-first**

  * No rush to ship
  * App is being built as the *final system*
  * User = developer until fully proven

* **Single routes file**

  * Intentional choice to enforce consistency
  * Easier reasoning about prompts, validation, and repairs
  * Avoids divergence between similar AI behaviors

* **AI-native progression**

  * Item Analysis → Liquidation Brief → Liquidation Plan
  * Local logic remains as fallback only

---

#### 🚧 Known Gaps (Intentional)

* Liquidation Plans are **still local on iOS**
* `/ai/generate-liquidation-plan` endpoint exists conceptually but is not yet wired end-to-end
* iOS does not yet call backend when selecting a liquidation path
* No UI yet for batch / estate-sale liquidation (sets)

---

#### ▶️ What We Will Do Next

1. **Stabilize Liquidation Brief generation**

   * Ensure Gemini never wraps responses (`{"item": {...}}`)
   * Harden normalization + repair logic

2. **Promote Plans to AI**

   * Implement backend-generated plans (`LiquidationPlanChecklistDTO`)
   * Keep local plan factory as fallback

3. **Wire iOS to AI Plans**

   * On “Choose Path”:

     * Call backend
     * Persist returned checklist JSON
     * Fall back locally on failure

4. **Extend to Sets / Estate Sale**

   * Multiple items → one brief
   * Shared plan + batch execution

---



**README addendum — Liquidate Module (Pattern A foundation complete)**

* Implemented **Pattern A** liquidation persistence:

  * `LiquidationState` hub owned by `LTCItem` (cascade)
  * `LiquidationBriefRecord` (immutable, versioned JSON, active flag)
  * `LiquidationPlanRecord` (mutable execution plan, versioned JSON, active flag)
* Implemented **LiquidateSandboxView** to validate:

  * Generate brief → create plan → execute checklist
  * Multiple briefs/plans persisted per item
  * Active brief/plan selection works
  * State persists when switching between items
* Implemented **local heuristic brief generator** (`LocalLiquidationBriefGenerator`) + DTO persistence:

  * DTOs encoded into SwiftData payload JSON
  * UI renders recommended path, reasoning, and path options
* Current status:

  * Builds and runs on device
  * Backend integration is the next milestone (swap brief generation to backend-first w/ local fallback)

*(Optional: add “Known follow-ups”)*

* Add backend endpoint + `BackendAIProvider.generateLiquidationBrief(...)`
* Add FeatureFlag to force local vs backend during rollout
* Add migration for legacy liquidation fields (if any remain)



## 📌 Project Status Update — Liquidate Module (Architecture Spike Complete)

**Date:** *(12-22-2025)*

We have completed a successful **architecture and feasibility spike** for the new **Liquidate Module**. This work focused on validating the *decision-support model* and end-to-end workflow rather than shipping a production MVP.

### ✅ What’s Working

* Liquidate operates on the existing unified `LTCItem` model (no parallel item entities).
* Liquidation **Briefs** and **Plans** are implemented as structured artifacts:

  * Briefs capture AI/heuristic analysis and recommendations.
  * Plans generate actionable checklists based on the selected liquidation path.
* The full UI flow works end-to-end in a **sandbox/debug context**:

  * Item selection
  * Brief generation
  * Path selection (A / B / C / Donate)
  * Plan creation and display
* Liquidation analysis is **photo-optional by design** (text-only supported).
* Build is green; app runs successfully on device.

### ⚠️ Known Limitations (Intentional at This Stage)

* Liquidation analysis currently uses a **local heuristic generator**.
* Briefs and plans may appear similar across items — this is expected and temporary.
* Liquidate is **not yet connected to the backend AI service**.
* Heuristics, DTOs, and UI are considered **prototype-level**, not final.

### 🎯 Key Outcome

This spike validated the **Liquidation Advisor concept**:

> Medium / High-value items benefit most from AI-assisted comparison of
> **Net Proceeds vs Effort**, followed by a user-chosen execution plan.

The system architecture is sound and ready to be refined into its final form.

### 🧭 Next Phase (Planned)

* Tighten final data model boundaries (SwiftData vs JSON artifacts).
* Make briefs and plans meaningfully **item-specific and path-specific**.
* Introduce set-aware liquidation logic.
* Define (but not yet implement) backend AI endpoints for liquidation.

**No commit was made at this stage by design.**
The next development phase will proceed from a clean architectural baseline.
## 📌 Current Status — Quantity v1 Complete (Dec 17 2025)

**Legacy Treasure Chest** now supports **set-based items** (e.g. china, glassware, flatware, collectibles) with clear **unit vs total valuation** across the app.

### ✅ What’s Implemented

#### Core Data Model

* `LTCItem.quantity` added (default = `1`)
* Quantity represents **number of identical units in a set**
* Backward compatible with existing items

#### Item Creation & Editing

* **Manual Add Item**: quantity supported
* **AI-Assisted Add Item**: quantity supported
* **Batch Add from Photos**: quantity supported
* **Item Detail View**:

  * Stepper-based quantity control
  * Clear distinction between **unit value** and **total value**
  * Footer shows total calculation when quantity > 1

#### AI Valuation Integration

* Unit value derived from:

  * AI valuation (`ItemValuation.estimatedValue`) when available
  * Fallback to manual `item.value`
* Total value = unit × quantity
* Valuation records remain **unit-based** (intentional, conservative)

#### Estate Dashboard

* All aggregates use **total values**:

  * Total estate value
  * Legacy vs Liquidate totals and percentages
  * Value by category
* **High-Value Liquidate Items**:

  * Sorted by total value
  * Displays quantity, total value, and “each” price when applicable

#### Estate Reports (PDF)

* **Estate Snapshot Report**

  * Totals reflect quantity
  * Legacy vs Liquidate summaries accurate for sets
* **Detailed Inventory Report**

  * Quantity-aware totals
  * Designed to be executor- and attorney-friendly

#### UX & Design

* Quantity behavior is **guided, not forced**
* Single-item flows remain frictionless
* Sets feel natural without adding complexity for simple items

---

### 🧭 Design Principles Reinforced

* **Conservative valuation** (unit-first, totals derived)
* **Clarity for non-technical users**
* **Estate-first thinking** (executor, attorney, beneficiary use cases)
* **AI-native**: AI assists, user remains in control

---

### 🚀 Next Likely Enhancements (Not Yet Started)

* AI prompts that explicitly account for quantity (e.g. “8 identical pieces”)
* Category-aware quantity presets (China, Glassware, Flatware)
* Inventory report layout polish (explicit Qty | Each | Total columns)
* Optional dashboard micro-copy explaining totals

### Summary (what I’m going to give you)December 15, 2025
## 📱 UI Issue Resolved: Keyboard Obscuring Text Fields in AI Sheets plus Dual Done buttons Fixed in More Details Text Input

**Status:** ✅ Resolved
**Affected Screens:**

* `ItemAIAnalysisSheet` (More Details for AI Expert)
* Earlier iterations of `ItemDetailView` (now stable)

---

### Problem Summary

While testing real-world usage on a physical iPhone, a critical usability issue was identified:

* When editing multi-line text fields (e.g., **“More Details for AI Expert”**),
* The **software keyboard appeared and covered the active text input**,
* The user **could not see existing text or what they were typing**,
* Tapping outside the field **did not dismiss the keyboard**,
* The issue was most visible inside **sheet-presented views**.

This made the AI-assisted refinement workflow effectively unusable.

---

### Symptoms Observed

* Text editor initially renders correctly.
* Once the keyboard appears:

  * The editor is pushed behind the keyboard.
  * Only predictive text suggestions are visible.
  * Typed content is hidden until editing is complete.
* “Done” commits text, but **editing occurs blind**.
* Issue reproduced consistently on device (not simulator-only).

---

### Root Cause

This was **not an AI issue** and **not a keyboard dismissal issue alone**.

The root cause was a **layout interaction between**:

* `ScrollView` inside a **modal sheet**
* `TextEditor` without keyboard-aware layout behavior
* Custom card-style UI not automatically adjusting for keyboard safe areas

In this configuration, SwiftUI **does not automatically move content above the keyboard**.

---

### Resolution

The issue was resolved by adjusting layout and presentation behavior so that:

* The sheet content **respects keyboard safe areas**
* The active text editor **remains visible while typing**
* The keyboard no longer obscures editable content

Once applied:

* Text fields remain fully visible during editing
* Existing content and new input are readable
* The UX behaves as expected for long-form text entry

This fix has been verified on a physical iPhone.

---

### Guidance for Future Development

To avoid regressions:

* ⚠️ Be cautious when combining:

  * `ScrollView`
  * `TextEditor`
  * `.sheet` presentation
* Always test **text-heavy screens on device**, not simulator only
* Treat “keyboard covers content” as a **blocking UX issue**, not cosmetic
* When adding new AI refinement or note-entry screens:

  * Verify the editor remains visible while typing
  * Verify dismissal and safe-area behavior

---

### Files Involved

* `ItemAIAnalysisSheet.swift`
* `ItemDetailView.swift`

## Current Status (Milestone: Physical Device Run)

**As of December 2025**

Legacy Treasure Chest now runs successfully on a physical iPhone (iOS 18+) using a local FastAPI AI gateway during development.

### What’s Working
- App installs and launches on a real iPhone (not simulator-only)
- SwiftUI + SwiftData core flows operational
- Navigation, Items, Estate Dashboard, Reports, and AI Test Lab accessible
- Backend AI requests routed through a local FastAPI gateway (no API keys in app)
- App Transport Security configured for local network development
- Signing, entitlements, and Info.plist stabilized

### Development Setup Notes
- `Generate Info.plist File` is disabled
- App uses a manually managed `Info.plist`
- Local AI gateway accessed via LAN IP during development
- This configuration is **development-only** and will change before TestFlight/App Store distribution

### Next Phase
The next development phase focuses on **real household usage**:
- UX clarity and friction reduction
- Copy and guidance improvements
- Workflow validation with real items, photos, and family members
- Refining AI usefulness based on actual behavior, not test cases

Infrastructure is considered “good enough” for now; priority shifts to product experience.

## Status Update — Estate Dashboard & Reports (2025-12-12)

### Estate Dashboard (Readiness Snapshot)

We added a v1 **Estate Dashboard** that answers: **“How ready is my estate inventory and allocation?”** using local SwiftData aggregation (no new backend endpoints).

Key concepts:

- **Legacy** = items with one or more beneficiaries assigned  
- **Liquidate** = items with no beneficiary (assumed to be sold; proceeds handled by the will/estate plan)

Dashboard sections:

- **Estate Snapshot**: total conservative estate value, item counts, Legacy vs Liquidate split
- **Estate Paths**: value + percentage share for Legacy vs Liquidate
- **Valuation Readiness**: valuation completion overall + by path  
  - Includes a lightweight **ⓘ tip** sheet (“How to increase readiness”) with prescriptive guidance and direct navigation to:
    - Items
    - Batch Add from Photos
- **Value by Category**: aggregated value and counts per category
- **High-Value Liquidate Items**: surfaces top Liquidate items by conservative value for quick review/triage
- **Export & Share**: entry point for generating printable reports (see below)

Implementation files:

- `LegacyTreasureChest/LegacyTreasureChest/Features/EstateDashboard/EstateDashboardView.swift`

### Estate Reports (PDF)

We added v1 PDF report generation, designed for sharing with an executor, attorney, or family:

- **Estate Snapshot Report** (one-page summary)
- **Detailed Inventory Report** (full item list with category, path, beneficiary, and value)

Entry points:

- From **Estate Dashboard** → **Export & Share** (bottom of dashboard)
- From **Home** (developer/lab tool entry used during testing)

Implementation files:

- `LegacyTreasureChest/LegacyTreasureChest/Features/EstateReports/EstateReportsView.swift`
- `LegacyTreasureChest/LegacyTreasureChest/Features/EstateReports/EstateReportGenerator.swift`

### Notes / Decisions

- The dashboard and reports use **local SwiftData only** (no new backend work).
- Conservative value calculations prioritize `ItemValuation.estimatedValue` when present, otherwise fall back to `LTCItem.value`.
- UX goal: keep reports discoverable but **not disruptive** to the primary “Items-first” workflow.

## AI Valuation System 12-11-2025

Legacy Treasure Chest includes a unified AI Valuation system that analyzes item photos and returns structured, conservative resale value hints for estate planning and downsizing.

The system has two main parts:

- **Backend – LTC AI Valuation Gateway (FastAPI + Gemini)**
- **iOS App – Item AI Analysis Sheet (SwiftUI + SwiftData)**

The goal is to give Boomers a realistic, conservative resale view of their belongings, not optimistic retail or insurance values.

---

### 1. High-Level Flow

1. User creates or selects an item and adds at least one photo.
2. From the Item Detail screen, the user taps **“Analyze with AI”**.
3. The iOS app sends:
   - The **first item photo**
   - The item’s **current title, description, and category**
   - Any **extra details** the user typed in the “More Details for AI Expert” text area
4. The backend calls Gemini with:
   - A **central system prompt** describing the valuation philosophy
   - **Category-specific Expert guidance** (Jewelry, Rugs, Art, China & Crystal, Furniture, Luxury Personal Items)
   - **General guidance** for remaining household categories
   - The image and assembled user hints
5. Gemini returns a strict JSON object (mapped to `ItemAnalysis` + `ValueHints`).
6. The iOS app:
   - Shows a **Valuation Summary**, **AI Suggestions**, **Why This Estimate**, and **Missing Details**
   - Updates the item’s **title, category, description, and valuation fields** when the user taps **“Apply Suggestions”**

---

### 2. Backend – Category Experts and General Guidance

All valuation runs through a single endpoint:

- `POST /ai/analyze-item-photo`
  - Request: `AnalyzeItemPhotoRequest` (image + optional `ItemAIHints`)
  - Response: `ItemAnalysis` with nested `ValueHints`

The central prompt:

- Enforces a **strict JSON schema** (no markdown, no extra fields).
- Uses **conservative fair-market resale value** (estate-sale / consignment / realistic online resale), *not* retail or insurance values.
- Encourages clear explanations in `aiNotes` and short, actionable prompts in `missingDetails`.

#### 2.1 Category-Specific Experts

The backend prompt currently includes dedicated guidance for:

- **Jewelry Expert v1**
- **Rugs Expert v1**
- **Art Expert v1**
- **China & Crystal Expert v1**
- **Furniture Expert v1**
- **Luxury Personal Items Expert v1**

Each Expert:
- Uses conservative **resale ranges** (`valueLow`, `estimatedValue`, `valueHigh` in USD).
- Explains **why** the range was chosen in `aiNotes`.
- Returns **high-impact missing details** in `missingDetails` (e.g., weight in grams, KPSI, artist signature, pattern name, maker labels).
- Adjusts behavior when the user provides better hints (brand, model, KPSI, provenance, etc.).

##### Jewelry Expert v1
- Focus: intrinsic + brand-driven value for rings, necklaces, bracelets, earrings, etc.
- Key drivers: **metal purity and weight, stone identity/quality, designer brand** (Cartier, Tiffany, Roberto Coin, etc.).
- Uses **real-world resale comps** (The RealReal, eBay, consignment) rather than retail/insurance.
- `missingDetails` examples:
  - “Need weight in grams”
  - “Need close-up of hallmark”
  - “Need stone type and approximate carat weight”

##### Rugs Expert v1
- Focus: hand-knotted and workshop rugs.
- Key drivers: **weave quality (KPSI / weave tier), materials (wool/silk/cotton), origin, size, age, condition**.
- Treats **user-supplied KPSI** as trustworthy when provided (user counts knots on the back).
- When KPSI is unknown, estimates a **weave tier** (coarse / medium / fine / very fine) and stays conservative.
- `missingDetails` examples:
  - “Need approximate KPSI (count knots per inch on the back)”
  - “Need clear close-up photo of the BACK with a ruler”
  - “Need the rug’s exact size”

##### Art Expert v1
- Focus: wall art and collectible art (paintings, prints, drawings, photographs).
- Key drivers: **artist identity, medium, original vs print, edition, size, condition, provenance**.
- Distinguishes **decorative art** from potentially collectible work.
- Conservative when artist/medium/edition are unclear.
- `missingDetails` examples:
  - “Need clear close-up photo of the artist’s signature”
  - “Need approximate height and width of the artwork”
  - “Need to know whether this is an original painting or a print”

##### China & Crystal Expert v1
- Focus: **fine china patterns and crystal stemware/serveware**.
- Key drivers: **brand, pattern name, quantity / completeness of sets, condition, discontinued status**.
- Recognizes that the market is generally **soft** versus original wedding registry / boutique pricing.
- `missingDetails` examples:
  - “Need brand and pattern name from the underside mark”
  - “Need to know how many matching pieces or place settings are included”
  - “Need information about chips, cracks, or cloudiness”

##### Furniture Expert v1
- Focus: household furniture (case goods, tables, seating, beds).
- Key drivers: **maker/brand, design era (e.g., mid-century), materials, construction quality, size, condition**.
- Recognizes that most used furniture sells for a **fraction of original retail**, unless it is designer / iconic.
- `missingDetails` examples:
  - “Need maker or brand name from any labels or stamps”
  - “Need approximate dimensions (width, depth, height)”
  - “Need closer photos of any damage or wear”

##### Luxury Personal Items Expert v1
- Rule of thumb:
  - If value is driven by **brand + model + condition**, use **“Luxury Personal Items”**.
  - If value is driven mostly by **metal weight or gemstone quality**, use **“Jewelry”**.
- Covers:
  - **Watches (fine timepieces)** – Rolex, Cartier, Omega, Patek, AP, etc.
  - **Designer Handbags** – Chanel, Hermès, LV, Gucci, YSL, Prada, etc.
  - **Fine Writing Instruments** – Montblanc, Pelikan, Waterman (high-end), etc.
  - **Small Leather Goods (SLGs)** – wallets, card holders, belts, key holders.
  - **Luxury Accessories** – designer sunglasses, scarves, cufflinks, lighters.
  - **Designer Jewelry behaving like a luxury good** – Cartier Love, Tiffany T, Yurman cable, Bvlgari B.Zero1, etc.
- Strong emphasis on **brand, model, authenticity cues, condition, and completeness** (box, papers, dust bag, authenticity cards).
- `missingDetails` examples:
  - “Need exact brand and model name”
  - “Need photo of case back or reference/serial number”
  - “Need to know if original box and papers are included”

#### 2.2 General Guidance for Remaining Categories

For remaining categories, the backend uses a **shared guidance block** instead of a full Expert:

- **Collectibles** (figurines, sports memorabilia, toys, etc.)
- **Electronics**
- **Appliance**
- **Tools**
- **Clothing**
- **Luggage**
- **Decor**
- **Documents**
- **Uncategorized / Other**

Each of these:
- Still returns a **conservative resale range**, focusing on realistic estate-sale / local-market outcomes.
- Emphasizes **brand, model/type, age, working condition, and visible wear**.
- Returns short, category-aware `missingDetails` prompts (e.g., “Need exact brand and model,” “Need to know if this item still works,” “Need closer photos of wheels and handles,” etc.).
- Treats most **documents** as having **organizational, not monetary value**, unless clearly collectible/historical.

---

### 3. iOS – Item AI Analysis Sheet (Hints & UX)

The iOS side uses a single view:

- `ItemAIAnalysisSheet`
  - Shows the **Current Item** (name, description, category, value)
  - Shows the **Photo Used for Analysis** (first image)
  - Provides a **“More Details for AI Expert”** section
  - Runs analysis and displays:
    - **Valuation Summary**
    - **AI Suggestions** (title, summary, category, tags)
    - **Improve This Estimate** (missing details)
    - **Why This Estimate** (provider, date, aiNotes)
    - **Item Details** (brand, maker, materials, style, origin, condition, features)

#### 3.1 Category-Aware Hints in the Text Area

The **hint text and placeholder example** in “More Details for AI Expert” are now **category-aware**:

- For example:
  - **Jewelry:** suggests metal purity, weight in grams, stone details, certificates.
  - **Rug:** suggests KPSI, materials, origin, size, age, condition, where purchased.
  - **Art:** suggests artist, medium, original vs print, edition number, size, provenance.
  - **China & Crystal:** suggests brand/pattern, number of pieces/place settings, chips/cracks/cloudiness.
  - **Furniture:** suggests maker/brand, dimensions, wood/materials, era, refinishing/reupholstery, condition.
  - **Luxury Personal Items:** suggests brand, model/collection, materials, condition, box/papers/receipts.
  - Other categories: show tailored hints (Electronics, Appliances, Tools, Clothing, Luggage, Decor, Collectibles, Documents, Other).

These hints live entirely on the **iOS side** and are mapped by `item.category` so the same UI works for all Experts and generic categories.

#### 3.2 How User Notes Are Used

- The text the user enters in “More Details for AI Expert” is stored in `ItemValuation.userNotes`.
- Before each run:
  - The sheet combines:
    - The current `item.itemDescription`
    - Any persisted `userNotes`
  - Into a single description passed to the backend as part of `ItemAIHints`.
- Over time, the user can refine the description and notes to produce:
  - Better **titles / summaries**
  - More accurate **valuation ranges**
  - More targeted **missingDetails** prompts

---

### 4. Valuation Mapping into SwiftData

On successful analysis:

- `ItemAIAnalysisSheet`:
  - Updates `item.name` from the AI `title`.
  - Updates `item.category` from `analysis.category`.
  - Builds a richer `item.itemDescription` combining:
    - AI `summary`
    - Key details (maker, materials, style, condition, features).
  - Maps `ValueHints` into:
    - `item.value` (midpoint if range, otherwise `estimatedValue` or boundary)
    - `item.suggestedPriceNew` (typically `valueHigh` or `estimatedValue`)
    - `item.suggestedPriceUsed` (typically `valueLow` or `estimatedValue`)
  - Upserts `ItemValuation`:
    - `valueLow`, `estimatedValue`, `valueHigh`
    - `currencyCode`
    - `confidenceScore`
    - `aiProvider`
    - `aiNotes`
    - `missingDetails`
    - `valuationDate` (from backend, set per run)
    - `updatedAt` timestamp
  - Preserves any existing `userNotes` (never overwritten by AI).

This design lets the user run multiple valuation passes per item as they add more details and photos, while keeping a single, latest `ItemValuation` attached to each `LTCItem`.

✅ AI Valuation UX & Data Model Update (Dec 9 2025)
This update summarizes recent improvements to the AI Valuation workflow, including how users provide additional details, how valuations are stored, and how the system now explains why an item is valued the way it is.
1. Unified Expert Valuation Experience
We refined the AI Analysis workflow so that every item—regardless of category—receives the same high-quality valuation experience.
Category-specific logic (e.g., jewelry vs. rugs vs. artwork) is handled by the backend Expert model, while the frontend presents a consistent, easy-to-understand interface.
Key principles:
One valuation snapshot per item, stored in ItemValuation.
No valuation history for now (keeps UX clean and avoids data clutter).
Users can re-run analysis anytime to generate an updated expert view.
2. “More Details for AI Expert” (User Notes)
We introduced a persistent notes field that lets users supply details that significantly improve valuation accuracy—such as:
Jewelry: weight, purity, chain length, certification
Rugs: knots per square inch, origin, age
Art: medium, dimensions, signed/original
These notes are:
Saved on the item (valuation.userNotes)
Reused automatically every time AI analysis is run
Included directly in the backend prompt to influence the valuation
Users no longer need to retype these details—this behaves like a conversational memory for the item.
3. Clear, Human-Readable Item Description
When users apply an AI analysis:
The summary and key attributes (materials, maker, style, condition, features) are merged into the item’s saved description.
This ensures the item record itself tells the story:
“This item, with these characteristics, is why the valuation range is what it is.”
The description now shows the defining traits that drive value and will remain visible even when not viewing the AI sheet.
4. Full AI Explanation Always Available (On-Demand)
We decided not to store the entire AI analysis structure long-term.
Instead:
The user can re-run Analyze with AI anytime to regenerate the full detailed analysis.
This is fast, always up-to-date, and uses their saved notes.
The saved summary + valuation snapshot is sufficient for everyday viewing.
This avoids expanding the data model prematurely while still giving users full transparency whenever they want it.
5. Backend Prompt Enhancements (Next Step)
To further improve valuation quality:
The backend will treat user notes as high-signal authoritative details.
The model will be asked to include optional “Approximate new replacement price” information in its explanation, when relevant.
This will appear in the AI Notes section (not as a stored numeric field).
This helps users understand both resale value and replacement cost when planning their estate or insurance needs.
Summary of Current Direction
Keep the valuation model simple (one snapshot).
Let users add meaningful details that persist with the item.
Let the AI regenerate full explanations when needed.
Ensure item descriptions clearly capture the characteristics that drive value.
Continue improving the backend Expert prompt to make the analysis more helpful.
✅ 1. README Update — Current Status (drop this into the top of README)
📌 Current Status — AI ValueHints v2 Integration December 8 2025
The Legacy Treasure Chest app now uses the updated ValueHints → ValueRange model across the entire AI pipeline. This includes:
Backend now returns the enriched value_hints block:
low, high, currency_code, confidence, sources[], and last_updated
Swift front-end updated to match the new model:
AIModels.ValueRange replaced old ValueHints
All views updated (AddItemWithAIView, BatchAddItemsFromPhotosView, ItemAIAnalysisSheet, AITestView)
Feature flag defaults updated to ensure AI is enabled by default (enableMarketAI = true)
SwiftData rebuild completed after schema updates (simulator reset required)
AI analysis now provides:
richer details (materials, maker, condition, features, extracted text)
improved valuation metadata
correct propagation of value estimates into LTCItem.value, suggestedPriceNew, suggestedPriceUsed
Next major milestone:
→ Design and implement ItemValuation.swift, allowing the app to store multiple valuation snapshots per item, with source/model/date/version fields.
✅ README Update (drop-in text block)
Add this as a new section near the top of your README under “Current Status” or “Recent Work Completed”.
(You can also keep it as a dated changelog entry.)
Beneficiaries Module — Completed Boomer-Side Functionality (2025-02)
The Beneficiaries module is now fully implemented for the primary “owner” (Boomer) workflow. The following features are complete:
Beneficiary Management
Create beneficiaries manually with name, relationship, email, and phone number.
Import beneficiaries directly from iOS Contacts using a custom ContactPicker.
Automatic deduplication: selecting a contact for an existing name merges the data rather than creating duplicates.
Beneficiaries imported from Contacts display a subtle “Linked to Contacts” badge in all views.
Edit Beneficiary screen allows updating:
name
relationship
email
phone
contact linkage (“Update from Contacts”)
Relationship Selector
Relationship field now uses a structured selector for consistent data:
Son, Daughter, Grandchild, Niece, Nephew, Sibling, Friend, Other
“Other / Custom…” opens a free-text field.
Beneficiary records always store a clean relationship value.
Assignment & Item Linking
Beneficiaries can be assigned to items through the ItemDetail screen using a picker.
Each assignment stores the access permission (immediate, upon passing, specific date).
Users can remove assignments or edit permissions at any time.
Beneficiary Overview Screen
“Your Beneficiaries” screen shows:
name + relationship
number of assigned items
total assigned value (using the item’s current estimated value)
a badge for Contacts-linked beneficiaries
Unassigned items appear in a separate section for quick distribution.
Beneficiary Detail View
Shows:
complete beneficiary information
Contact linkage indicator
assigned item list with thumbnails and permission details
total assigned value summary
Inline “Edit Beneficiary” button opens the edit sheet.
General Notes
This module is now feature-complete for the owner workflow and ready for TestFlight.
Future enhancements (Millennial/recipient workflow, shared claiming, CloudKit multi-user sync) can build on this foundation.
### 2025-11-28 — Beneficiaries Module & Contacts Integration

**Beneficiaries (Owner / Boomer view)**

- Implemented **YourBeneficiariesView** as the top-level entry point:
  - Shows each Beneficiary with relationship, number of items, and total assigned value (using current item values).
  - Displays a **“From Contacts”** badge for Beneficiaries linked to iOS Contacts.
  - Supports swipe-to-delete for Beneficiaries with no assigned items and prevents deletion when items are still linked (with an explanatory message).

- Implemented **BeneficiaryDetailView**:
  - Shows contact info (name, relationship, email, phone).
  - Shows total value of assigned items.
  - Lists assigned items with thumbnails, category, per-item value, and access rules, navigating into `ItemDetailView` on tap.

- Implemented **BeneficiaryFormSheet** (manual add):
  - Simple, theme-aligned sheet for manually adding Beneficiaries (name, relationship, email, phone).
  - New Beneficiaries appear in both Your Beneficiaries and the item-level Beneficiary picker.

- Implemented **ContactPickerView** + top-level Contacts integration:
  - “+” menu in Your Beneficiaries offers:
    - **Add from Contacts** — opens the system Contacts picker.
    - **Add Manually** — opens `BeneficiaryFormSheet`.
  - Selecting a contact will:
    - Reuse an existing Beneficiary linked to that contact if one exists.
    - Otherwise, try to **merge with an existing Beneficiary** by name/email (to avoid duplicates).
    - Only create a brand new Beneficiary when no reasonable match is found.
  - When merging, the app fills in missing email/phone but preserves any user-edited name.

- Item-level Beneficiary UX:
  - `ItemBeneficiariesSection` shows per-item Beneficiary links with access rules and notification status.
  - Users can:
    - Add a Beneficiary to an item via the Beneficiary picker.
    - Edit a link via `ItemBeneficiaryEditSheet` (access rules, date, personal message).
    - Remove a link (deletes the junction record, not the Beneficiary).

- **Unassigned Items**:
  - `YourBeneficiariesView` shows a dedicated **Unassigned Items** section listing items with no Beneficiaries.
  - Tapping an item navigates into `ItemDetailView` to assign Beneficiaries from there.

**Other sync / polish**

- Aligned category options across:
  - `ItemDetailView`
  - `AddItemView`
  - `AddItemWithAIView`
- Ensured Beneficiary-related views are fully Theme-driven (typography, colors, spacing) and integrated into the main navigation via Home → Beneficiaries.

## Status Update – AI Integration, Items UI, and Documents (2025-12-04)

### AI Integration

- AI item analysis now runs through the **LTC AI Gateway** backend:
  - iOS uses `AIService` with `BackendAIProvider`.
  - Backend is a FastAPI app that calls Gemini 2.0 Flash and returns strict JSON.
  - No Gemini API keys or secrets are present in the iOS app.
- The following flows are working end-to-end:
  - `AITestView` (internal lab) – single photo → ItemAnalysis.
  - Batch Add from Photos – multiple photos → multiple items with AI-filled details.
  - AI-assisted analysis on existing items via `ItemAIAnalysisSheet`.

### Items UI & Categories

- “Your Items” list now:
  - Shows a **thumbnail** for each item (first photo if available, placeholder otherwise).
  - Groups items by **Category** when not searching (Art, Jewelry, Rug, Luxury Personal Items, etc.).
  - Falls back to a flat thumbnail list while searching, for easier scanning of matches.
- Category options have been expanded and aligned with the AI backend, including:
  - `China & Crystal`
  - `Luxury Personal Items`
  - `Tools`
  - Plus existing categories like `Art`, `Furniture`, `Jewelry`, `Collectibles`, `Rug`, `Luggage`, `Decor`, `Other`.
- Existing items may still have older or legacy category values; these will be normalized over time as items are edited.

### Documents vs Photos – Current Decision

- **Documents**:
  - Currently optimized for PDFs and other files added via the system file picker (Files, Mail, etc.).
- **Photos**:
  - All camera-based images, including photos of receipts, appraisals, labels, and other “document-like” images, are managed in the Photos section.
- Intentional decision for this phase:
  - Documents = external files (especially PDFs).
  - Photos = all images, even when they represent documentation.
- Deferred enhancement:
  - In a future iteration, enhance the Documents module to:
    - Import images from Photos as `IMAGE` documents.
    - Add document-type metadata (e.g., Appraisal, Receipt, Warranty, Insurance Statement).

### Next Focus – Beneficiaries

- Upcoming work will focus on the **Beneficiaries** experience:
  - Confirm and polish the existing Item → Beneficiary linking (ItemBeneficiariesSection, BeneficiaryPickerSheet, ItemBeneficiaryEditSheet).
  - Introduce a “Your Beneficiaries” screen to view and manage beneficiaries.
  - Add a “Beneficiary detail” view to see all items associated with a given person (e.g., “What does Sarah get?”).
- AI features for beneficiary suggestions (`suggestBeneficiaries`) and personalized messaging (`draftPersonalMessage`) remain planned but are not yet implemented; current phase is about getting the core data model and UX flows solid.

## AI Integration Status (Local Backend + Gemini)

**Last Updated:** 2025-11-28

- The Legacy Treasure Chest iOS app now uses a **provider-agnostic AI layer**:
  - `AIProvider` protocol defines `analyzeItemPhoto`, `estimateValue`, `draftPersonalMessage`, and `suggestBeneficiaries`.
  - `AIService.shared` is the façade used by views and is initialized with `BackendAIProvider` by default.
- A separate **FastAPI backend** (`LTC_AI_Gateway`) runs on the Mac host and handles all calls to Gemini:
  - Endpoint: `POST http://127.0.0.1:8000/ai/analyze-item-photo`
  - Backend holds `GEMINI_API_KEY` and `GEMINI_MODEL` in `.env` and never exposes them to the iOS app.
  - Pydantic models mirror the Swift `ItemAIHints`, `ValueRange`, and `ItemAnalysis` types.
- `BackendAIProvider`:
  - Encodes item photos as Base64 JPEG (`imageJpegBase64`).
  - Sends `AnalyzeItemPhotoRequest` (image + optional `ItemAIHints`) to the backend.
  - Decodes the response into Swift `ItemAnalysis` using `JSONDecoder` with default camelCase keys.
- `AITestView`:
  - Uses `AIService.shared.analyzeItemPhoto(_:hints:)` end-to-end through the backend.
  - Confirmed working in the iOS Simulator with realistic test photos and optional hints.
- **Security**:
  - No Gemini API key or secret is present in the iOS app, Info.plist, or build settings.
  - All AI traffic from the app flows through the backend gateway.

**Next AI Front-End Tasks (Option B):**

1. Wire `AddItemWithAIView` to rely solely on `AIService` + `BackendAIProvider`.
2. Ensure `BatchAddItemsFromPhotosView` uses the backend for each photo in a batch.
3. Confirm `ItemAIAnalysisSheet` calls the backend for re-analysis on existing items.

✅ Legacy Treasure Chest — Project Status (Updated)
Last Updated: (November 28, 2025)
Milestone: AI Batch Add & Item-Level AI Analysis — Completed
App Version: Phase 1C+ (AI-Native Foundation Complete)
Target Platform: iOS 18+, SwiftUI, SwiftData, Apple Intelligence-enabled devices
🚀 Current High-Level Status
Legacy Treasure Chest now includes a fully functional personal inventory system with integrated AI-powered item analysis, batch import capabilities, media management, and beneficiary assignment.
The following modules are fully implemented and working end-to-end:
📦 Core Features — Complete
Authentication
Sign in with Apple (production-ready)
Simulator-friendly authentication override
User-specific data management (LTCUser)
Item Management
ItemsListView with search, sorting, deletion
AddItemView for manual entry
ItemDetailView with live SwiftData persistence
Categories, values, timestamps, descriptions
Media Modules
Photos
Add, view, pinch-to-zoom, delete, share
Documents
FileImporter, type detection, preview via QuickLook
Image/PDF support, share sheet
Audio
Recording, playback, deletion
Microphone permission handling (iOS 18)
MediaStorage
Unified file storage for images, documents, and audio
Beneficiaries
Create/manage beneficiaries
Item-level beneficiary assignment via junction model
Edit access rules and permissions
Sheet-based UI fully integrated into ItemDetailView
🤖 AI System — Complete & Extensible
AI Architecture
Provider-agnostic abstraction (AIProvider protocol)
Central AI façade (AIService)
Concrete Gemini provider (GeminiProvider)
Prompt templating + JSON structured return format
Full error handling with friendly messaging
Item-Level AI Analysis
Users can analyze any item’s primary image
AI suggests:
Improved title & description
Category
Value estimate & range
Attributes, materials, style, condition
Extracted text (OCR)
AI results displayed in a dedicated analysis sheet
“Apply to Item” writes results back to SwiftData
AI Test Lab
Standalone internal testing tool for prompt iteration
Allows image selection + optional hints + raw AI inspection
🖼️ Batch Add from Photos — Complete
A major user-facing feature:
User selects multiple photos from library
AI analyzes each image:
Title, description, category, value
Tags, attributes, features
Extracted OCR text
User reviews results in a scrolling list
User toggles which items to import
Items are created in SwiftData with associated images
Includes:
Error-safe design (per-image error display)
Graceful handling of decode failures
Immediate import into the system
Works well with large batches (3–10+ images)
🎨 Design System — Fully Integrated
All new UI uses Theme.swift colors, fonts, spacing
Custom branded section headers & cards
Uniform toolbar tinting
Consistent typography across modules
🧱 Architecture Summary
SwiftData: primary persistence layer
SwiftUI: complete UI layer
MediaStorage: file management for all media
Gemini Provider: first-class AI backend
Modular Feature Folders:
Items
Photos
Documents
Audio
Beneficiaries
AI (Models, Services, Views)
Authentication
Shared UI + Utilities
🏁 Current State Assessment
The app is now stable, modular, and ready for:
Extensive AI tuning
Adding fair market value confidence displays
Batch add improvements (retry, inline edits, etc.)
Later phases: CloudKit, Sharing, Marketplace integrations
This is a significant milestone:
Legacy Treasure Chest now has a complete AI-native foundation, allowing rapid expansion of capabilities without reworking the core architecture.
## Beneficiaries Module (Item-Level Assignment)

**Status:** Implemented and working in the iOS app.

The Beneficiaries module allows an LTCUser to define people who will receive specific items and to configure when and how those people gain access.

### Data Model

- `LTCUser`
  - Owns `beneficiaries: [Beneficiary]`
- `Beneficiary`
  - Core fields: `name`, `relationship`, optional `email`, optional `phoneNumber`
  - Optional contact linkage via `contactIdentifier` and `isLinkedToContact`
  - Back-link to item links via `itemLinks: [ItemBeneficiary]`
- `LTCItem`
  - Owns `itemBeneficiaries: [ItemBeneficiary]`
- `ItemBeneficiary` (junction model)
  - Links `LTCItem` ↔ `Beneficiary`
  - Stores:
    - `accessPermission: AccessPermission`  
      - `.immediate`, `.afterSpecificDate`, `.uponPassing`
    - Optional `accessDate`
    - Optional `personalMessage`
    - `notificationStatus: NotificationStatus`
      - `.notSent`, `.sent`, `.accepted`

This keeps Beneficiary as the canonical LTC record, with ItemBeneficiary holding per-item rules.

### UI / UX

All UI is Theme-driven (`Theme.swift`) and integrated into `ItemDetailView`:

- **ItemDetailView**
  - Hosts the Beneficiaries section alongside Photos, Documents, and Audio.
  - Owns presentation for:
    - Beneficiary picker/creator sheet
    - Beneficiary link editor sheet
  - Supports:
    - Add Beneficiary to item
    - Edit link (access rules + message)
    - Remove link (swipe-to-delete)

- **ItemBeneficiariesSection**
  - Shows an empty state when there are no linked beneficiaries:
    - Explanation of purpose
    - Themed “Add Beneficiary” button
  - When links exist:
    - Card-style list of beneficiaries
    - Displays:
      - Beneficiary name and relationship
      - Access permission summary (Immediate / After date / Upon passing)
      - Notification status badge
    - Tapping a row opens the editor; swipe-to-delete removes the link.

- **BeneficiaryPickerSheet**
  - Presented from `ItemDetailView` on “Add Beneficiary”.
  - Shows:
    - Existing beneficiaries for the current `LTCUser`
    - A form to create a new beneficiary (name, relationship, optional email/phone)
  - Selecting or creating a beneficiary:
    - Creates a new `ItemBeneficiary` with default `.immediate` access
    - Attaches it to the current item
    - Associates new Beneficiaries with the user so they are available for other items

- **ItemBeneficiaryEditSheet**
  - Allows editing an existing `ItemBeneficiary` link:
    - Picker for `accessPermission`
    - Date picker for `accessDate` when `.afterSpecificDate` is chosen
    - Card-style `TextEditor` for `personalMessage`
    - Read-only display of `notificationStatus`
  - Changes are saved back to the linked `ItemBeneficiary` when the user taps “Done”.

### Future Enhancements (Planned)

- Integrate with device Contacts:
  - Import a contact to create or link a `Beneficiary`
  - Populate `contactIdentifier` and `isLinkedToContact`
- Notification workflows:
  - Use `notificationStatus` to track outbound messages and acknowledgements
- Dedicated Beneficiaries management screen:
  - View and manage all Beneficiaries independent of items
- AI assistance:
  - Suggest likely beneficiaries for items
  - Draft personal messages based on item history and user preferences

# 📌 Milestone Update — Audio Stories Module Implemented (Nov 2025)

The **Audio Stories** module for Legacy Treasure Chest is now fully implemented and integrated into the Item Detail flow. This brings audio recording, playback, and management capabilities to each item in the catalog.

### ✔️ Completed in this milestone

- **Audio Recording**
  - Microphone permission request via `NSMicrophoneUsageDescription`
  - AVAudioRecorder-based recording with proper session configuration
  - Accurate duration capture before stopping the recorder
  - Audio files stored under `Media/Audio` using MediaStorage

- **Playback & Audio Management**
  - Inline play/pause with `AVAudioPlayer`
  - Single-playback enforcement (starting one stops another)
  - Stable handling of playback completion and session transitions
  - Clear user feedback and safe fallbacks

- **SwiftData Integration**
  - New `AudioRecording` model linked to each `LTCItem`
  - SwiftData persistence for file path, duration, timestamps
  - Automatic updatedAt propagation to parent item

- **UI/UX Implementation**
  - Fully themed with `Theme.swift` (colors, typography, spacing)
  - Integrated into ItemDetailView with correct section header styling
  - Empty-state messaging + “Record Story” CTA
  - List of audio stories with titles, timestamps, and durations
  - Playback icons and deletion controls consistent with Photos/Documents

- **Deletion Workflow**
  - SwiftData removal of `AudioRecording` objects
  - File cleanup via MediaStorage with soft-fail safety
  - Stopping playback when deleting the active recording

### 🔒 Architecture & Safety
All audio interactions follow the existing architectural patterns:
- Media files stored on disk, metadata stored in SwiftData
- AVAudioSession properly activated/deactivated
- Structured recording and playback lifecycle to avoid race conditions
- No global singletons — AudioManager is isolated per view instance

This completes full media support (Photos, Documents, Audio) for each item.
Next milestone: **Beneficiaries module implementation**.

## 📌 Update — Documents Module v1 Complete (2025-11-25)

This milestone completes the first working version of the **Documents Module** and brings the app to a solid baseline:

- App launches successfully with SwiftData `ModelContainer` and `ModelContext` initialized.
- Core models exist and compile: `LTCUser`, `LTCItem`, `ItemImage`, `AudioRecording`, `Document`, `Beneficiary`, `ItemBeneficiary`.
- Items persist correctly across launches.
- `MediaStorage` is implemented and working for:
  - Images under `Media/Images`
  - Audio under `Media/Audio`
  - Documents under `Media/Documents`
- `MediaCleaner` exists (not yet wired into the main flows).

### Authentication

- Sign in with Apple implemented and stable via:
  - `AuthenticationService`
  - `AuthenticationViewModel`
  - `AuthenticationView`
- Simulator sign-in override available.
- `HomeView` shows correctly after successful sign-in.

### Items Flow

- `ItemsListView` uses `@Query` sorted by `createdAt`.
- Search works on item `name` and `description`.
- **Add Item**
  - `AddItemView` is pushed via `NavigationLink`.
  - Fields: `name`, `description`, `category` (Picker), `value` (currency).
  - Saves a new `LTCItem` into SwiftData and returns to the list.
- **Item Detail**
  - `ItemDetailView` uses `@Bindable var item: LTCItem`.
  - Editing name/description/category/value auto-saves via SwiftData.
  - Returning to the list immediately reflects updates.
- **Delete**
  - Swipe-to-delete in `ItemsListView` removes items using SwiftData.

### Photos Module (Working)

- `ItemPhotosSection`:
  - Uses `PhotosPicker` to add one or more images.
  - Persists images via `MediaStorage.saveImage` under `Media/Images`.
  - `ItemImage` model is linked to `LTCItem.images`.
- Thumbnails:
  - Grid of square thumbnails with delete and context menu.
- Preview:
  - `ItemDetailView` owns a sheet with full-screen zoomable/pannable preview (`ZoomableImageView`).
- Deletion:
  - Removes `ItemImage` from SwiftData.
  - Attempts to delete underlying file via `MediaStorage.deleteFile`.
- Behavior is stable (no presentation/state warnings).

### Documents Module (Working v1)

- `ItemDocumentsSection`:
  - Uses `fileImporter` to attach PDFs and images from Files / iCloud Drive.
  - Persists documents via `MediaStorage.saveDocument` under `Media/Documents`.
  - `Document` model linked to `LTCItem.documents`.
  - Stores `documentType` (e.g., PDF, IMAGE, UTI) and `originalFilename`.
- Display:
  - List view with icon, filename, type, and size (e.g., `PDF · 322 KB`).
  - Shows a clean filename (original name, not UUID prefix).
- Preview:
  - `ItemDetailView` sheet:
    - Uses `ZoomableImageView` for image documents.
    - Uses QuickLook for PDFs/other types.
    - Includes **Done** and **Share** controls.
- Share:
  - Uses `UIActivityViewController` (via `ActivityView`) to share/open documents.
- Deletion:
  - Removes `Document` from SwiftData.
  - Attempts to delete underlying file via `MediaStorage.deleteFile`.
- File size guard:
  - Simple upper limit (e.g., 50 MB) with a user-facing error if exceeded.

### Other Sections (Placeholders)

- `ItemAudioSection` – placeholder for future audio stories.
- `ItemBeneficiariesSection` – placeholder for future beneficiary management.

---


Legacy Treasure Chest is an iOS app designed to help households organize, catalog, and document personal items, including photos, documents, audio notes, and beneficiary designations. It focuses on making downsizing, estate planning, and family communication easier for Boomers and their families.

## Features (in progress)
- Item catalog with photos, documents, and audio sections
- SwiftData-backed local storage
- Clean SwiftUI architecture
- Authentication (Sign in with Apple planned)
- Future: AI-assisted photo/document analysis
- Future: CloudKit sync and family sharing

## Project Structure
- `LegacyTreasureChest/` — SwiftUI code for app features
- `Docs/` — architectural notes and project documentation

## Technology
- Swift 6
- SwiftUI
- SwiftData
- Xcode 16+
- iOS 18+ target planned

