# Legacy Treasure Chest
# Production Roadmap

Last Updated: March 2026

---

# Current System Status

Legacy Treasure Chest is now a **fully operational AI-native iOS application** with a deployed cloud AI gateway.

Validated architecture:

iPhone (SwiftUI)
      ↓
Cloud Run (FastAPI AI Gateway)
      ↓
Gemini 2.5 Flash

The system has been tested end-to-end from the iPhone through the cloud backend to Gemini and back.

This marks the completion of the **core engineering phase of the project**.

The remaining work shifts from engineering infrastructure to **distribution readiness and controlled external testing**.

---

# Phase 1 — Core Product Development (Completed)

This phase established the fundamental capabilities of the application.

### Core Inventory System

Users can catalog household possessions including:

- Items
- Sets
- Lots
- Batches
- Beneficiaries
- Documents
- Images
- Audio notes

All user data is stored **locally on device**.

---

### Advisory AI System

AI assists with:

- Item categorization
- Valuation ranges
- Liquidation strategy
- Auction vs dealer recommendations
- Partner discovery via Google Places

The AI system is designed to provide **advisory guidance only**, not automation.

---

### Export System

The application generates executor-grade documentation including:

- Executor Snapshot Report
- Detailed Inventory Report
- Outreach Packet
- Beneficiary Packet
- Executor Master Packet

These exports allow estate information to be safely shared with professionals such as:

- executors
- attorneys
- dealers
- auction houses

---

### Execution Mode

Execution Mode provides **lot-centric checklists** allowing an estate executor to track liquidation progress in a safe and reversible way.

This ensures the system supports **real-world estate execution**, not just planning.

---

# Phase 2 — AI Backend Architecture (Completed)

An AI gateway service was created to isolate the iOS application from direct AI API access.

Key capabilities:

- FastAPI backend
- Gemini model integration
- Google Places partner discovery
- Structured JSON output for iOS consumption
- Standardized error handling
- Request tracing via device ID

This architecture ensures:

- API keys are never stored in the mobile app
- AI providers can be changed without app updates
- cost control and monitoring remain centralized

---

# Phase 3 — Cloud Deployment (Completed)

The AI gateway has been deployed to **Google Cloud Run**.

Completed infrastructure work includes:

- containerized FastAPI deployment
- Google Secret Manager for API keys
- Gemini API key rotation
- hardened logging
- removal of API key exposure risks
- health endpoint monitoring

Cloud Run endpoint:

https://ltc-ai-gateway-530541590215.us-west1.run.app

---

# Phase 4 — End-to-End System Validation (Completed)

The complete system pipeline has been validated:

1. iPhone app sends request
2. Cloud Run gateway receives request
3. Gemini processes analysis
4. structured JSON returned to iOS app

Additional verification:

- logging verified
- device ID request tracing operational
- rate limiting active
- secret manager confirmed functioning

The AI infrastructure is now **production capable**.

---

# Phase 5 — Distribution Readiness (Current Phase)

Before external users can access the application through TestFlight, several public artifacts must be created.

Required items:

- Privacy Policy page
- Support page
- Contact method for testers

Recommended items:

- Product overview page
- Observer briefing document

These documents will be hosted on the project domain.

---

# Phase 6 — Controlled TestFlight Trial

The first external distribution will be a **small controlled TestFlight trial**.

Target group:

5–10 trusted observers.

Participants should ideally represent:

- different cities
- different housing styles
- different liquidation instincts

The goal of this phase is **observation, not growth**.

Focus areas:

- where users hesitate
- which exports are used
- whether AI guidance feels correct
- which workflows feel unclear

There will be:

- no marketing
- no monetization
- no scale expectations

---

# Phase 7 — Product Refinement

After TestFlight observations:

Evaluate:

- workflow clarity
- export usefulness
- advisory accuracy
- user hesitation points

Possible refinements:

- UX improvements
- AI prompt adjustments
- export layout improvements
- documentation updates

---

# Phase 8 — Public Release Preparation

Once the system performs well with external testers:

Prepare for public distribution:

- App Store submission
- website launch
- licensing model
- pricing strategy

---

# Guiding Product Principle

Legacy Treasure Chest is designed as an **advisor system, not an operator system**.

The application helps users:

- document household possessions
- receive advisory liquidation guidance
- generate structured documentation

The system intentionally does **not**:

- act as a marketplace
- conduct transactions
- store estate inventories in the cloud