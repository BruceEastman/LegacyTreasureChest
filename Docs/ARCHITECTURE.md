Below is a clear, structured update plan to **bring your ARCHITECTURE.md in line with your new AI-first direction** — while preserving the good structure you already have.

I’ll start with **what needs to change**, then provide the **updated file**, keeping your organization and style intact, but removing outdated assumptions (e.g., Apple Intelligence as primary, Gemini behind a feature flag, privacy-first constraints that no longer apply).

---

# 🔧 What Needs Updating

Your current ARCHITECTURE.md assumes:

* **Apple Intelligence is the primary AI engine**
* **Gemini is optional**, behind a feature flag
* The app is **privacy-first and local-first**
* Cloud AI is only for limited market analysis
* Audio transcription uses Apple services
* Vision/image understanding uses Apple frameworks

### But after our deep discussions, your new architectural stance is:

## **1. Cloud-first AI (Gemini as primary)**

* Core workflows require full model flexibility
* Photo → Item creation = Gemini vision + reasoning
* Valuation = Gemini market research
* Message drafting = Gemini or optional OpenAI

## **2. AIService abstraction**

* Provider-agnostic
* GeminiProvider is first implementation
* Future: optional OpenAIProvider, optional Apple Intents writing tools

## **3. Apple Intelligence is supplemental**

* Not the primary AI engine
* Useful for:

  * iOS-wide writing tools (polish user-entered text)
  * Siri / App Intents integration
* **No direct LLM API** for JSON or valuation → cannot support your core flows

## **4. Single-user focus**

* CloudKit sync is **not** in the near-term roadmap
* Privacy trade-offs are acceptable
* Focus is on making *your own workflow* efficient

## **5. Your modules are now:**

* Items (manual + AI-assisted)
* Media (Photos, Documents, Audio)
* Beneficiaries
* **AI Layer** ← NEW major module

So the doc needs a large but straightforward rewrite.

---

# ✨ Here is the Updated `ARCHITECTURE.md` (Drop-in Replacement)

Below is a **fully updated, polished, ready-to-use** version that reflects your actual roadmap and priorities.

You can paste this file directly into `Docs/ARCHITECTURE.md`.

---

````markdown
# Legacy Treasure Chest — Architecture

**Last Updated:** 2025-02-28  
**Status:** ACTIVE  
**Version:** 2.0.0 (AI-First Architecture)  
**Target:** iOS 18.0+

---

# 1. Overview

Legacy Treasure Chest is an AI-native iOS application that helps users catalog possessions, analyze value, attach media, and designate beneficiaries for legacy planning.

### **New One-Sentence Summary**
An AI-first iPhone app that uses cloud AI (Gemini) to automate item creation, valuation, and beneficiary assistance, supported by SwiftData local storage and a consistent SwiftUI design system.

---

# 2. Technology Stack

## Platform
- **iOS:** 18.0+
- **Language:** Swift 6 (strict concurrency)
- **UI Framework:** SwiftUI
- **Architecture Pattern:** MVVM with service layer

## Data & Persistence
- **Local Database:** SwiftData (primary store)
- **Media Storage:** Application Support via `MediaStorage`
- **Sync:** CloudKit (future, optional)
- **Storage Principle:** Metadata in SwiftData, large binary assets in file system

## AI Integration (New Architecture)
### **Primary: Cloud AI (Gemini 2.0 Flash)**
- Image analysis (item identification, attributes)
- Value estimation via market research
- Reasoning + classification (category suggestions)
- Message generation
- Beneficiary suggestion and pattern detection

### **AIService Abstraction**
A provider-agnostic façade enabling:
- Gemini as primary provider  
- Optional future providers (OpenAI, local models, etc.)

```swift
AIService
 ├── GeminiProvider (primary)
 └── FutureProvider (optional)
````

### **Supplemental: Apple Intelligence**

* System-level writing tools (polish/edit)
* Siri + App Intents integration
* Transcription (optional)

> Apple Intelligence does *not* provide general-purpose LLM API access; it is not used for core automation.

## Authentication

* **Sign In With Apple** (exclusive)
* No credentials stored
* Keychain used only for Apple-related tokens

---

# 3. Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                         SwiftUI Views                         │
│  (Items, Item Detail, AI Creation Flow, Beneficiaries, etc.)  │
└───────────────▲──────────────────────────────────────────────┘
                │
                │
┌───────────────┼──────────────────────────────────────────────┐
│                       ViewModels                              │
│      (@Observable, validation, orchestration, business logic) │
└───────────────▲──────────────────────────────────────────────┘
                │
                │
┌───────────────┼──────────────────────────────────────────────┐
│                        Service Layer                           │
│   AuthService     MediaStorage     AIService     ItemService   │
│            ┌──────────────────────────────┐                   │
│            │         AI Providers         │                   │
│            │   (GeminiProvider primary)   │                   │
│            └──────────────────────────────┘                   │
└───────────────▲──────────────────────────────────────────────┘
                │
                │
┌───────────────┼──────────────────────────────────────────────┐
│                    Local Storage & Media Files                 │
│          SwiftData (entities)     File System (media)          │
└───────────────▲──────────────────────────────────────────────┘
                │
                │
┌───────────────┼──────────────────────────────────────────────┐
│                 Cloud Providers (Optional / Future)            │
│  CloudKit Sync (multi-device)   Marketplace APIs (future)      │
└───────────────────────────────────────────────────────────────┘
```

---

# 4. Module Structure

## App Layer

* `LegacyTreasureChestApp.swift`
* Dependency injection setup
* Theme initialization

## Core Layer

* **AIService** (new AI abstraction)
* **GeminiProvider** (first implementation)
* **MediaStorage / MediaCleaner**
* Shared helpers and extensions

## Data Layer

* SwiftData models:

  * `LTCUser`
  * `LTCItem`
  * `ItemImage`
  * `AudioRecording`
  * `Document`
  * `Beneficiary`
  * `ItemBeneficiary`
  * **AI-related fields on LTCItem** (aiDescription, aiValueLow/High, etc.)

## Features Layer

* **Items**

  * Manual creation + AI-assisted creation flow
  * Item detail editing
* **Media**

  * Photos, Documents, Audio modules
* **Beneficiaries**

  * User-level beneficiary creation
  * Item-level assignment (ItemBeneficiary)
* **AI**

  * AITestView (internal playground)
  * Photo → Item analysis workflows
  * Value refresh workflows

---

# 5. AI Architecture (Critical)

## AIService (Abstraction)

Defines the high-level interface the app depends on:

```swift
protocol AIProvider {
    func analyzeItemPhoto(_ data: Data) async throws -> ItemAnalysis
    func estimateValue(description: String, category: String?) async throws -> ValueRange
    func draftMessage(item: LTCItem, beneficiary: Beneficiary) async throws -> String
    func suggestBeneficiaries(item: LTCItem, candidates: [Beneficiary]) async throws -> [BeneficiarySuggestion]
}
```

## GeminiProvider

* The first concrete provider
* Handles:

  * REST requests
  * API key management
  * JSON decoding
  * Error + retry logic
* Owns prompt templates and tuning

## Data Models

Used both in AIService and SwiftData:

* `ItemAnalysis`

  * title
  * description
  * category
  * confidence
  * valueHints?

* `ValueRange`

  * low, high
  * currency
  * sources
  * lastUpdated

* `BeneficiarySuggestion`

  * beneficiary
  * confidence
  * reasoning summary

---

# 6. Design System (Theme.swift)

All modules adhere to:

* Brand typography (Theme fonts)
* Brand colors (Theme.primary, Theme.accent, etc.)
* Spacing system via Theme.spacing
* Section header styling (`.ltcSectionHeaderStyle()`)
* Card backgrounds via `.ltcCardBackground()`

The design system ensures UI consistency across:

* Photos
* Documents
* Audio
* Beneficiaries
* AI item creation & review screens

---

# 7. Key Architectural Decisions (Updated)

### **1. Cloud-First AI (Gemini as Primary)**

**Why:**

* Most capable vision + reasoning model available
* Handles valuation via market research
* Clearer JSON control
* Needed for your workflow

**Trade-offs:**

* Requires network connectivity
* API costs (acceptable for solo use)

---

### **2. AIService Provider Pattern**

**Why:**

* Allows Gemini now
* Allows OpenAI later
* Keeps business logic stable

---

### **3. Apple Intelligence = Supplemental**

**Why:**

* No general-purpose LLM API
* Great for writing polish + Siri
* Not suitable for your automated flows

---

### **4. SwiftData for All Entities**

* Local, simple, modern
* Excellent match for your single-user phase

---

### **5. Manual → AI-assisted → Fully Automated Workflows**

Your modules follow this evolution path:

1. Manual flows (already implemented)
2. AI-assisted creation (Phase 1)
3. AI-suggested beneficiaries (Phase 2)
4. Value refresh automation (Phase 3)
5. Fairness dashboard (Phase 4)

---

# 8. Future Enhancements (True Roadmap)

1. **Add Item with AI flow** (photo → analysis → review → save)
2. **Batch photo import** for scanning a room quickly
3. **Value refresh scheduler**
4. **Beneficiary AI (patterns + fairness insight)**
5. **Legacy export (PDF / digital book)**
6. **CloudKit multi-device sync**
7. **Optional spouse/caregiver collaboration**
8. **Marketplace APIs (eBay/Etsy/Auction houses)**

---

# 9. Related Documents

* DATA-MODEL.md
* SERVICES.md
* MVP-SCOPE.md
* AI-LAYER.md (future detailed AI docs)

```

---

# 4️⃣ Summary

- This updated `ARCHITECTURE.md` now matches **your real direction**:  
  **AI-first, Gemini-first, provider-agnostic, cloud-first, with Apple Intelligence as supplemental**.
- It removes outdated assumptions and aligns with the plan we will implement in the AI module buildout.
- You can replace your existing file with this one directly.

If you’d like, I can also generate:

- `AI-LAYER.md` (detailed design for AIService + GeminiProvider)  
- A diagram showing the planned “Add Item with AI” flow  
- Prompt templates for Gemini photo analysis  

Just tell me what you’d like next.
```
