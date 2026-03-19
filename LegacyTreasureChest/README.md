# Legacy Treasure Chest

https://ltc-ai-gateway-530541590215.us-west1.run.app
cloud run deploy ltc-ai-gateway --source . --region us-west1 --allow-unauthenticated

## 2026-03-19 — Fixed item-level Local Help hidden in Release/TestFlight

### Issue
Item-level **Local Help** was not appearing on `ItemDetailView` in local Release/TestFlight-style behavior, even though:
- Set-level Local Help was working
- Brief and Plan generation for items appeared to succeed
- The item Local Help UI code was present in `ItemDetailView`

### Symptoms observed
- In **Item Detail → Next Step**, only **Liquidate** appeared
- The **Local Help** row did not appear at all, including the disabled/gated version
- This indicated the Local Help block was being skipped before prereq gating was evaluated

### Root cause
The `dispositionEngineUI` feature flag had been updated to return **true by default unless explicitly turned off**, but `registerDefaultValues()` was still registering the Release default as `false`:

```swift
FeatureFlagKeys.dispositionEngineUI: debugDefault   // ON in DEBUG, OFF in Release

## Update — Launch Screen Cleanup, AI Regression Check, and Local Help Restoration (March 17, 2026)

### Summary
Completed a focused validation and cleanup pass in preparation for the next TestFlight build. We investigated a temporary AI failure affecting all AI-backed features, confirmed the cloud backend and Gemini path are functioning, fixed a real Local Help regression in set navigation, and updated the Local Help feature flag behavior so the feature is visible by default for TestFlight users unless explicitly turned off.

---

### 1. AI Failure Investigation — Current Status
We investigated a morning regression where all AI-backed actions appeared to fail in the app, including:
- Add New Item from Photo
- Improve with AI
- Create Brief

We validated the backend directly and confirmed:

- Cloud Run `/health` endpoint returned `200 OK`
- `/ai/analyze-item-text` returned a successful structured response
- `/ai/analyze-item-photo` returned a successful structured response
- Cloud Run was able to reach Gemini successfully
- The backend/Gemini path is currently healthy

**Conclusion:**  
This does **not** appear to be a persistent backend outage or Gemini/secret failure. The earlier issue was most likely transient (network, cloud/model-side hiccup, cold start/scaling event, or build/version ambiguity on device). No backend code change was required to restore operation.

---

### 2. Launch Screen Cleanup
Completed the launch screen integration/cleanup work needed for iPhone startup polish and to remove the prior storyboard warning path.

Related files included:
- `LaunchScreen.storyboard`
- `LegacyTreasureChest.xcodeproj/project.pbxproj`
- `Info.plist`

This work is part of the TestFlight-readiness cleanup and is now incorporated into the current codebase.

---

### 3. Set-Level Local Help Regression — Fixed
A real regression was identified in **Set Details**:

- The **Local Help** row was still visible
- But tapping it incorrectly opened **Execute Plan**
- This was caused by the Local Help navigation link targeting `SetExecutePlanView(itemSet:)` instead of the partner discovery screen

**Fix applied in `SetDetailView.swift`:**
- Updated the Local Help destination to:
  - `DispositionPartnersView(itemSet: itemSet)`
- Updated the set-level Local Help gate to use:
  - `localHelpPrereqsMet`
instead of only checking for an active plan

**Result:**  
Set-level Local Help now opens the intended partner discovery / Google Places workflow again.

---

### 4. Item-Level Local Help Visibility — Default Behavior Updated
For items, the Local Help UI block was still present in code, but it was wrapped in the `dispositionEngineUI` feature flag.

We discovered that the existing implementation used:
- `UserDefaults.bool(forKey:)`

That meant the effective default was `false` whenever the flag had never been set, even though the intent/comments suggested otherwise.

**Fix applied in `FeatureFlags.swift`:**
- Updated `dispositionEngineUI` so it now defaults to **ON unless explicitly turned off**

New behavior:
- If `ltc_feature_dispositionEngineUI` has never been set, the app returns `true`
- If it has been explicitly set, the stored value is respected

**Reason for this change:**  
Local Help is one of the key differentiating features that should be tested in TestFlight by external users.

---

### 5. Notes on Current Device Testing
After the feature-flag fix, item-level Local Help was still not visible on the developer’s existing local phone install. Based on the code review, the most likely explanation is **stale local `UserDefaults` state** from prior builds, not a current code-path failure.

Because of that, the correct source of truth for validation is now:
- a **fresh TestFlight install**
- on a **separate iPhone**
- using the newly archived build

---

### 6. Next Validation Plan
The next build/download from TestFlight should validate the following on a clean device install:

1. **Item flow**
   - Generate Brief
   - Generate Plan
   - Confirm **Local Help** appears
   - Open Local Help and confirm partner discovery search works

2. **Set flow**
   - Generate Brief
   - Generate Plan
   - Confirm **Local Help** appears
   - Open Local Help and confirm partner discovery search works

3. **Core AI flows**
   - Add New Item from Photo
   - Improve with AI
   - Create Brief

---

### 7. Current Assessment
At the end of this pass:

- Cloud Run backend is healthy
- Gemini integration is healthy
- AI text route is working
- AI photo route is working
- Set-level Local Help regression is fixed
- Local Help feature flag behavior is now aligned with TestFlight testing goals
- Next source-of-truth validation is a fresh TestFlight install on a second device

This leaves the project in a good position for the next TestFlight build and external-user readiness verification.

## 2026-03-16 — Warning Cleanup and Stability Hardening Pass

This pass was completed during the waiting period before the next external TestFlight build cycle.

### Objective
Clean up Xcode warnings with priority on:
1. privacy / permissions
2. deprecated APIs with possible runtime impact
3. concurrency / actor-isolation issues
4. logic warnings that could hide real bugs
5. low-risk cosmetic cleanup

### Result
All previously listed warnings from this pass were resolved successfully.

---

## Warnings Fixed

### 1) `ItemAudioSection.swift`
**Issue**
- Deprecated microphone permission APIs:
  - `AVAudioSession.recordPermission`
  - `AVAudioSession.requestRecordPermission`

**Change made**
- Updated permission handling to the current `AVAudioApplication` APIs.

**Why it mattered**
- This is a user-facing privacy/permission path.
- Important for runtime behavior and future compatibility on current iOS targets.

---

### 2) `SetDetailView.swift`
**Issue**
- Deprecated geocoding APIs on iOS 26:
  - `CLGeocoder`
  - `reverseGeocodeLocation(_:completionHandler:)`

**Change made**
- Added `import MapKit`
- Replaced `CLGeocoder` reverse geocoding with `MKReverseGeocodingRequest`
- Removed the old `CLGeocoder` property
- Added lightweight helper methods to extract city / region / country code from the returned address data

**Why it mattered**
- Minimum deployment target is iOS 26.1
- This was no longer future cleanup; it was an active platform deprecation in location-related behavior

**Note**
- The new implementation is a warning-removal / stability-hardening migration intended to preserve current autofill behavior without redesigning the feature

---

### 3) `AIService.swift`
**Issue**
- Main actor isolation warnings caused by default initializer arguments:
  - `BackendAIProvider()`
  - `FeatureFlags()`

**Change made**
- Removed actor-sensitive object creation from default parameter values
- Changed initializer to accept optional injected values and construct defaults inside the initializer body

**Why it mattered**
- Concurrency / actor-isolation warnings may indicate real correctness issues
- This service is central to AI-assisted item analysis and related flows

---

### 4) `DispositionAIService.swift`
**Issue**
- Main actor isolation warning caused by default initializer argument:
  - `BackendAIProvider()`

**Change made**
- Same pattern as `AIService`
- Removed default object construction from the parameter list
- Constructed fallback dependency inside the initializer body

**Why it mattered**
- Same concurrency/stability concern as above
- This service is part of the Disposition Engine / partner search flow

---

### 5) `BeneficiaryPacketComposer.swift`
**Issue**
- Nil-coalescing warning where fallback was never used:
  - `item.itemDescription ?? ""`

**Change made**
- Replaced with direct use of `item.itemDescription`

**Why it mattered**
- This was a logic cleanup warning
- It confirmed that the model property is non-optional and removed misleading fallback logic

---

### 6) `OutreachPacketComposer.swift`
**Issue**
- Same nil-coalescing warning pattern:
  - `item.itemDescription ?? ""`

**Change made**
- Replaced with direct use of `item.itemDescription`

**Why it mattered**
- Same reasoning as `BeneficiaryPacketComposer`
- Reduced misleading dead-code fallback logic in export composition

---

### 7) `BatchAddItemsFromPhotosView.swift`
**Issue**
- Deprecated SwiftUI API:
  - `.onChange(of:perform:)`

**Change made**
- Updated to the current `onChange` closure form using old/new parameters

**Why it mattered**
- Low risk, but worth cleaning because the app targets a modern iOS version and this view is part of the photo-import workflow

---

### 8) `ItemAIAnalysisSheet.swift`
**Issue**
- Unused immutable value:
  - `currencyCode`

**Change made**
- Removed the unused local constant

**Why it mattered**
- Low-risk cleanup only
- Reduced noise in analysis sheet code

---

### 9) `LTCDeviceIdentity.swift`
**Issue**
- Variable declared as `var` but never mutated:
  - `query`

**Change made**
- Changed `var query` to `let query`

**Why it mattered**
- Cosmetic cleanup only
- Clarified intent in Keychain lookup code

---

### 10) `LaunchScreen.storyboard`
**Issue**
- Interface Builder warning:
  - `"View Controller" is unreachable because it has no entry points...`

**What happened**
- The existing storyboard appeared visually correct in Interface Builder
- Clean Build Folder did not remove the warning
- The warning persisted despite confirming an initial view controller and storyboard entry point

**Change made**
- Replaced the existing launch screen file with a newly created **Launch Screen** file
- Rebuilt the app after replacement

**Result**
- Warning was eliminated

**Why it mattered**
- This was the only remaining packaging / launch-related warning
- Replacing the file was the safest resolution after the existing storyboard continued to report a false/stuck warning state

---

## Working Approach Used
This pass followed a strict low-risk cleanup process:
- fixed only 1–2 issues at a time
- prioritized runtime-sensitive warnings first
- used complete file replacements for smaller files when appropriate
- used minimal edits for local one-line fixes
- rebuilt after each change set
- avoided speculative architecture changes

---

## Deployment / Testing Notes
During this pass, we also confirmed the practical build/test workflow:

- Use **actual iPhone hardware** for runtime validation of:
  - microphone permission flow
  - location/geocoding behavior
  - camera/photo-related flows
  - general UI behavior

- Use **Any iOS Device (arm64)** for archive-style compile/build confidence before the next TestFlight submission

---

## Current Status After This Pass
- Warning cleanup pass completed successfully
- All listed warnings from this round were resolved
- Project is in a better state for the next external TestFlight build cycle
- Recommended next step is a quick runtime sanity pass on device for the areas touched:
  - microphone recording permission flow
  - current-location autofill
  - batch add from photos
  - app launch/open flow

## TestFlight External Observer Readiness — Status Summary

### Current Status
We have completed the initial App Store Connect / TestFlight setup for **Legacy Treasure Chest** and the app is now positioned for a **small controlled external observer round**.

### What Was Completed

#### 1. App Store Connect Setup
- Created the **App Store Connect app record** for:
  - **App Name:** Legacy Treasure Chest
  - **Bundle ID:** `com.bruceeastman.LegacyTreasureChest`
- Confirmed Xcode signing with the correct Apple developer team
- Resolved initial signing/team configuration issues in Xcode

#### 2. Xcode Archive / Upload Path
- Set initial version/build numbering and successfully archived the app
- Uploaded builds to App Store Connect through Xcode Organizer
- Established the working archive/upload path for future TestFlight builds

#### 3. Info.plist / Distribution Fixes Required for Upload
During the first upload attempts, several distribution-related issues were identified and corrected:

- Added required bundle metadata:
  - `CFBundlePackageType = APPL`
- Added and configured a proper launch screen:
  - created `LaunchScreen.storyboard`
  - set launch screen interface file base name correctly
  - removed conflicting plist-only launch screen configuration
- Added required supported orientations:
  - `UISupportedInterfaceOrientations`
  - `UISupportedInterfaceOrientations~ipad`
- Added required location usage purpose string:
  - `NSLocationWhenInUseUsageDescription`
- Cleared export compliance / encryption questionnaire for uploaded TestFlight builds

#### 4. TestFlight External Testing Setup
- Created external testing group:
  - **Initial Observers**
- Added the required **Test Information**
- Added Beta App Review contact information and reviewer notes
- Added **What to Test** text for the external observer group
- Submitted builds for Beta App Review
- Received Apple approval for external testing

#### 5. Warning Cleanup / Stability Pass
- Performed a separate warning cleanup pass after initial Apple review friction
- Cleaned up all identified Xcode warnings before preparing the next observer build
- Uploaded a cleaner follow-up build for external observers

#### 6. Current Build Status
- **Build 1.0 (3)** has been uploaded
- Export compliance for build 3 was completed
- Build **1.0 (3)** was added to the **Initial Observers** external group
- Older build **1.0 (1)** was removed from the external group
- The short **What to Test** content was added for build 3
- The project is now ready for adding the first small set of trusted external observers

---

## Recommended Immediate Next Step
Add **2–3 highly trusted external observers by email** to the **Initial Observers** TestFlight group and begin the first controlled observer round.

Recommended approach:
- use **email invites only**
- do **not** use a public link
- keep the group very small initially
- monitor tester status in App Store Connect:
  - Invited
  - Accepted
  - Installed

---

## Notes / Lessons Learned
- TestFlight **export compliance must be answered per build**
- A newly uploaded build may show **Missing Compliance** even if the previous build was already cleared
- External testing groups are **build-based**, so new builds must be explicitly added to the group
- While a build is in Beta App Review, App Store Connect may prevent replacing it until review is complete
- Archiving to **Any iOS Device (arm64)** is normal for distribution and is separate from the deployment target
- The archive/distribution process surfaced issues that were not obvious during normal device-only development

---

## Current Operational Baseline
- App Store Connect app record exists
- TestFlight external group exists
- Apple external review path is approved
- Build **1.0 (3)** is the intended build for the first trusted observer round
- Warning cleanup has been completed
- Next work is real-world observer feedback, not distribution setup

---
# Public Documentation Hosting (TestFlight Readiness) — 2026-03-06

**Status:** Complete
**Scope:** External documentation required for TestFlight distribution
**Components:** Cloudflare DNS, Cloudflare Workers (static hosting), Public documentation pages

This update establishes the public documentation required for external TestFlight distribution.

Apple requires applications distributed to external testers to provide publicly accessible URLs for a **Privacy Policy** and **Support page**. These pages must be available over HTTPS.

To satisfy this requirement, a minimal static documentation site was created and deployed using Cloudflare infrastructure.

---

## Architecture

The site is hosted using **Cloudflare Workers static asset deployment** attached directly to the project domain.

```
Cloudflare DNS
      ↓
Cloudflare Worker (static assets)
      ↓
legacytreasurechest.com
```

This approach provides:

• zero hosting cost
• global CDN distribution
• automatic HTTPS certificates
• no server maintenance
• minimal operational complexity

---

## Public Pages Created

The following pages were deployed:

```
https://legacytreasurechest.com
https://legacytreasurechest.com/privacy
https://legacytreasurechest.com/support
```

### Index Page

Provides a short overview of the Legacy Treasure Chest system and links to supporting documentation.

### Privacy Policy

Describes the system’s privacy-first architecture, including:

• local device storage for household inventory
• stateless AI processing
• third-party services (Google Cloud Run, Gemini API, Google Places)
• limited request metadata logging for debugging and rate limiting

### Support Page

Provides a simple contact channel for user support and troubleshooting.

---

## Key Design Principle

The public documentation reinforces the core architectural principle of Legacy Treasure Chest:

**Advisor system, not operator system.**

The application:

• helps users catalog possessions
• provides advisory AI guidance
• generates structured documentation for estate planning

The system intentionally does **not**:

• operate a marketplace
• conduct transactions
• store estate inventories in the cloud

---

## Outcome

This milestone completes the **public documentation requirement for TestFlight distribution**.

The following URLs can now be used in App Store Connect:

```
Privacy Policy
https://legacytreasurechest.com/privacy

Support URL
https://legacytreasurechest.com/support
```

With this step completed, the project advances to the next phase:

**Controlled TestFlight distribution preparation.**



# Orientation System + First Launch Onboarding (2026-03-06)

**Status:** Complete  
**Scope:** User orientation, onboarding, and early-stage guidance  
**Components:** iOS App (SwiftUI), Help/Guide system, Items empty-state UX

This update introduces a structured **orientation system** for Legacy Treasure Chest designed to help new users quickly understand what the system does and how to begin using it.

The goal was to provide a **clear mental model of the system** before users begin cataloging items, without requiring videos or external documentation.

This is especially important because LTC supports a multi-phase workflow that is not familiar to most users.

---

# Problem

Early TestFlight demonstrations revealed that new users did not immediately understand the full scope of the system.

Without context, users tended to assume LTC was simply an **inventory app**, missing major capabilities such as:

- AI-assisted valuation guidance
- liquidation planning
- beneficiary designation
- executor-grade exports

The system needed an **embedded explanation of its purpose and workflow** that lives entirely inside the app.

---

# Solution: Orientation Layer

A three-part orientation layer was implemented:

### 1. First-Launch Onboarding

A short onboarding experience now appears the first time the app launches.

The onboarding explains the four core questions LTC answers:

- **What do we have?**  
  Capture possessions with photos and AI-assisted descriptions.

- **What is it worth?**  
  Receive advisory resale value guidance.

- **Who should receive it?**  
  Assign items to beneficiaries or plan liquidation.

- **What does the executor need?**  
  Generate professional estate documentation.

Users are also introduced to the **Estate Journey model**:

The final onboarding screen includes a direct action button to **begin adding items**.

This keeps the guide focused on **orientation and trust**, while operational learning happens naturally inside the product.

---

# Advisor Model Clarification

The guide also clearly states the LTC philosophy:

- LTC is an **advisor**, not an operator
- AI provides guidance but does not take actions
- nothing is automated or executed on behalf of the user
- the inventory remains **stored on the user’s device**
- exports reflect the catalog exactly as recorded

This reinforces the product’s **privacy-first architecture**.

---

# Architecture Impact

No backend changes were required.

All orientation components are implemented as **SwiftUI views** within the existing app structure:

---

### 2. "How It Works" Guide

A structured in-app guide was added to explain the system’s capabilities.

This guide is permanently accessible from the Home screen.

It includes sections covering:

- The Estate Journey
- Building an inventory
- AI valuation guidance
- Legacy items and beneficiaries
- Selling and liquidation strategies
- Executor documentation and exports
- Privacy and the advisor model

The guide focuses on **capabilities and system philosophy**, not step-by-step instructions.

---

### 3. Improved First-Use UX (Empty State)

The **Items screen empty state** was redesigned to guide first-time users.

Instead of simply displaying “No items yet,” the screen now:

- explains the first step
- highlights the two primary ways to begin
- uses the same icons present in the navigation bar

Actions presented:

- **Add with Photos** (`photo.on.rectangle.angled`)
- **Add Manually** (`plus`)

This provides immediate clarity without requiring users to read documentation.

---

# Guide System Simplification

The previous Help content was simplified to reduce redundancy.

Removed sections:

- Getting Started workflow instructions
- What the app is / is not
- detailed operational checklists

These were replaced with a streamlined structure:

These components are purely UI and documentation layers and do not interact with the data model.

---

# Result

New users now receive:

1. A clear explanation of **what LTC does**
2. A mental model of the **Estate Journey**
3. Immediate guidance on **how to begin**

This significantly improves first-time comprehension and prepares the system for **expanded TestFlight evaluation**.
# Cloud Run Smoke Test + Secret Manager Hardening (2026-03-05)

**Status:** Complete
**Scope:** Cloud integration validation + security hardening
**Component:** `LTC_AI_Gateway` (FastAPI → Cloud Run → Gemini 2.5 Flash)

This update successfully validated the **end-to-end cloud architecture** for the Legacy Treasure Chest AI backend and implemented security improvements to prevent API key exposure.

---

# Architecture (Validated)

```
iPhone App (SwiftUI)
        ↓
Cloud Run
FastAPI (LTC_AI_Gateway)
        ↓
Gemini 2.5 Flash
```

Cloud Run service:

```
https://ltc-ai-gateway-530541590215.us-west1.run.app
```

Health endpoint:

```
/health
```

---

# Step 4.5 — Cloud Smoke Test

The following validation sequence was executed.

## 1. Backend health

Command:

```
curl https://ltc-ai-gateway-530541590215.us-west1.run.app/health
```

Result:

```
{"status":"ok"}
```

Confirmed:

* Cloud Run service reachable
* FastAPI application running
* Middleware functioning

---

## 2. Direct AI gateway test

Command:

```
curl -X POST \
https://ltc-ai-gateway-530541590215.us-west1.run.app/ai/analyze-item-text \
-H "Content-Type: application/json" \
-d '{"text":"Vintage brass candlestick"}'
```

Result:

* HTTP `200`
* Valid structured JSON response
* `aiProvider: gemini-2.5-flash`

Confirmed:

* Gemini integration functioning
* Backend request routing correct
* JSON extraction pipeline working

---

## 3. iPhone → Cloud Run → Gemini test

Executed from the iPhone app using **Improve with AI**.

Cloud Run logs confirmed:

```
POST /ai/analyze-item-photo
deviceId: AD658682-6265-46B6-836B-C9DFBD309633
status: 200
```

Confirmed:

* iOS client successfully calling Cloud Run
* Request headers properly propagated
* Middleware request tracking functioning
* Gemini responses returned to the app

---

# Observed Behavior

During early testing Gemini returned a temporary upstream error:

```
503 UNAVAILABLE
"This model is currently experiencing high demand"
```

This resolved automatically on retry and is a known transient behavior for hosted LLM APIs.

Future improvement:

* Add **retry with exponential backoff** for transient statuses (`429`, `503`, `504`).

---

# Security Hardening Implemented

## 1. Moved Gemini API key to Secret Manager

Previous configuration used a direct environment variable.

New configuration:

```
Secret Manager
   ↓
Cloud Run environment injection
   ↓
GEMINI_API_KEY
```

Secret name:

```
gemini-api-key
```

Cloud Run configuration:

```
--set-secrets GEMINI_API_KEY=gemini-api-key:latest
```

Benefits:

* API keys no longer stored in Cloud Run config
* Secrets can be rotated without code changes
* Follows Google Cloud security best practices

---

## 2. API key rotation

Because an earlier key appeared in logs during debugging:

* Old Gemini API keys were **disabled**
* New key created
* Stored as **Secret Manager version 2**

Secret status:

```
gemini-api-key
  ├── version 1 (revoked)
  └── version 2 (active)
```

---

## 3. Prevented API key leakage in logs

`httpx` INFO logging was printing full request URLs:

```
INFO:httpx:HTTP Request:
https://generativelanguage.googleapis.com/... ?key=API_KEY
```

This exposed secrets in Cloud Run logs.

Fix added in `main.py`:

```python
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)
```

Result:

* Full request URLs no longer logged
* API keys protected from log exposure

---

# Result

The **Legacy Treasure Chest cloud architecture is now fully operational**:

```
iPhone
   ↓
Cloud Run (FastAPI AI Gateway)
   ↓
Gemini 2.5 Flash
```

All core requirements validated:

* Cloud Run deployment functioning
* AI gateway routing correct
* Gemini API integration working
* Structured JSON responses returned to the app
* Device identity logging functioning
* Secrets secured via Secret Manager
* Logging hardened against key leakage

---

# Next Steps

After completing the cloud validation:

```
Step 5 — Privacy Policy Page
Step 6 — TestFlight external readiness
```

These steps prepare the app for **external users and App Store submission**.

---

If you'd like, I can also give you a **very short 6-line “Executive Summary” version** that many teams place above entries like this so the README stays easier to skim as the project grows.

# Cloud Run Deployment + Gemini Integration Fix (2026-03-05)

**Status:** Complete
**Scope:** Backend externalization / AI Gateway deployment
**Component:** `LTC_AI_Gateway` (FastAPI → Cloud Run → Gemini 2.5 Flash)

This update resolved the final issues preventing the Legacy Treasure Chest AI Gateway from running correctly on **Google Cloud Run** and successfully calling **Gemini 2.5 Flash**.

After these fixes, the full production architecture is now functioning:

```
iPhone App
   ↓
Cloud Run (FastAPI AI Gateway)
   ↓
Gemini 2.5 Flash
```

---

# Key Issues Identified

During Cloud Run deployment several issues surfaced simultaneously.

## 1. Secret Value Contained Invalid Data

The original `GEMINI_API_KEY` secret stored in **Secret Manager** contained a pasted command string rather than the actual API key.

Example of the invalid value:

```
gcloud config set project legacy-treasure-chest
gcloud secrets versions add ltc-gemini-api-key --data-file=-
```

This caused Gemini requests to fail with:

```
API_KEY_INVALID
```

### Fix

A new secret version containing the **actual API key** was created:

```
gcloud secrets versions add ltc-gemini-api-key --data-file=-
```

Verification:

```
gcloud secrets versions access latest --secret=ltc-gemini-api-key
```

---

## 2. Cloud Run Was Using the Wrong Secret Version

Cloud Run was still referencing the **older invalid secret version**.

Service configuration showed:

```
GEMINI_API_KEY
  secretKeyRef:
    name: ltc-gemini-api-key
    key: '2'
```

This was corrected so the service reads the valid version.

---

## 3. Environment Variable Contained Hidden Characters

Secrets copied into Secret Manager sometimes contain trailing characters such as:

```
\n
\r
\t
```

These characters can break API authentication.

### Fix

`gemini_client.py` now sanitizes all environment variables before use.

```
_strip whitespace
_remove \r \n \t
_reject remaining control characters
```

Function added:

```
_sanitize_env()
```

This prevents hidden characters from breaking authentication again.

---

## 4. Backend Defaulted to an Invalid Gemini Model

The gateway default model was:

```
gemini-2.0-flash-exp
```

This model is **not available** on the endpoint being used and produced:

```
404 NOT_FOUND
models/gemini-2.0-flash-exp is not found
```

### Fix

The backend default model was updated to:

```
gemini-2.5-flash
```

This matches the model used during development and provides the desired performance/latency balance.

```
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
```

Cloud Run environment variables were also updated:

```
GEMINI_MODEL=gemini-2.5-flash
```

---

# Backend Hardening Improvements

The Gemini client now includes additional production safeguards:

### Environment Sanitization

```
_sanitize_env()
```

Ensures secrets and environment variables contain no hidden control characters.

---

### Retry Logic

Gemini calls retry once on transient failure.

```
attempts: 2
retry delay: 0.4s
```

---

### Structured Logging

Gemini upstream errors now log:

```
status code
response snippet
```

This allows fast diagnosis without exposing secrets.

---

# Deployment Verification

Cloud Run deployment was verified using a direct endpoint test.

```
POST /ai/analyze-item-text
```

Test request:

```
curl -X POST https://ltc-ai-gateway-530541590215.us-west1.run.app/ai/analyze-item-text
```

Example response:

```
aiProvider: gemini-2.5-flash
```

HTTP status:

```
200 OK
```

This confirms:

* Cloud Run container running
* secrets loading correctly
* Gemini authentication working
* AI gateway endpoint functioning

---

# iOS Client Update (Next Step)

The iOS client should now default to the Cloud Run gateway rather than a local FastAPI server.

File:

```
Features/AI/Services/BackendAIProvider.swift
```

Recommended default backend URL:

```
https://ltc-ai-gateway-530541590215.us-west1.run.app
```

Local development should still be supported using a runtime override (for example via `UserDefaults`).

Suggested behavior:

| Mode              | Backend                |
| ----------------- | ---------------------- |
| Normal operation  | Cloud Run              |
| Local development | Local FastAPI override |

This change ensures:

* the app works out of the box against production infrastructure
* developers can still use a local server when needed

---

# Result

The Legacy Treasure Chest architecture now operates as intended:

```
iPhone
   ↓
Cloud Run (FastAPI AI Gateway)
   ↓
Gemini 2.5 Flash
```

This configuration will be used for:

* TestFlight builds
* external user trials
* production deployment.



# 🚀 Step 4 — iOS Client Hardening for Cloud Mode

**Status:** Implemented (client-side)
**Date:** 2026-03-04
**Scope:** iOS networking reliability, error normalization, request discipline
**Backend:** Cloud Run (LTC_AI_Gateway)
**Philosophy:** Advisor system — calm, predictable, non-crashing

---

# 1. Objective

Prepare the **Legacy Treasure Chest iOS client** to operate reliably against a **cloud backend** under real-world conditions:

• slow networks
• Cloud Run cold starts
• backend outages
• rate limiting
• malformed responses
• decoding failures

The app must **never crash**, must **not expose raw server errors**, and must present **calm, actionable user messaging**.

---

# 2. Client Reliability Improvements Implemented

## 2.1 Unified Error Model

AI networking now maps transport and server failures into a **stable client error type** used across the AI layer.

Handled conditions include:

| Condition                 | Client Behavior                   |
| ------------------------- | --------------------------------- |
| Offline / network failure | Safe message, retry suggestion    |
| Timeout                   | Safe message, retry suggestion    |
| 429 Rate Limit            | “Too many requests” guidance      |
| 502/503 upstream failure  | “Service temporarily unavailable” |
| Backend decoding issues   | “Unexpected response” message     |
| Unknown errors            | Safe fallback message             |

This prevents raw backend errors from appearing in the UI.

---

## 2.2 Request ID Propagation

Every AI request now generates a **client request ID**.

Headers added to all backend calls:

```
X-Request-ID
X-LTC-Device-ID
```

Benefits:

• Correlates device requests with Cloud Run logs
• Enables targeted debugging without exposing internal details to users
• Improves operational diagnostics for future external users

---

## 2.3 Stable Device Identity

A persistent **device identifier** is now generated and stored via:

```
LTCDeviceIdentity.swift
```

Characteristics:

• UUID stored in Keychain
• Stable across launches
• Used for backend request identification
• Not tied to user accounts (privacy preserving)

Header format:

```
X-LTC-Device-ID: <stable UUID>
```

---

## 2.4 Network Retry Discipline

AI requests now implement **conservative retry behavior**:

| Error Type           | Retry              |
| -------------------- | ------------------ |
| Network interruption | retry once         |
| Timeout              | retry once         |
| 502 / 503            | retry once         |
| 429                  | no automatic retry |
| 4xx errors           | no retry           |

This improves reliability during:

• Cloud Run cold starts
• temporary network interruptions

without creating repeated calls or runaway retries.

---

## 2.5 Safe JSON Handling

Unexpected or malformed responses from the backend are now safely handled:

• decoding errors are caught
• failures return controlled client errors
• no crash paths remain in the AI service layer

---

# 3. Environment Routing Verification

Client routing logic verified:

| Build Type           | Backend              |
| -------------------- | -------------------- |
| Debug                | Local FastAPI server |
| Release / TestFlight | Cloud Run backend    |

The base URL selection is centralized in:

```
BackendAIProvider.swift
```

No hard-coded backend URLs exist elsewhere in the client.

---

# 4. Files Updated

Client hardening changes were implemented in:

```
LegacyTreasureChest/Core/Utilities/LTCDeviceIdentity.swift
LegacyTreasureChest/Features/AI/Models/AIModels.swift
LegacyTreasureChest/Features/AI/Services/BackendAIProvider.swift
```

Primary responsibilities:

**LTCDeviceIdentity**
• stable device ID generation
• Keychain persistence

**AIModels**
• normalized error types
• safe user-presentable messages

**BackendAIProvider**
• request header injection
• retry logic
• timeout handling
• error normalization

---

# 5. Smoke Testing Performed

Basic validation was performed against the Cloud Run backend:

✔ `/health` endpoint reachable
✔ client generates request IDs
✔ device ID header present
✔ backend errors surfaced as safe client messages

A backend runtime error was observed (`500`) related to Gemini URL construction; investigation indicated a newline in environment configuration. Backend sanitization was implemented separately.

This backend issue does **not affect the Step-4 client hardening work.**

---

# 6. Result

The LTC iOS client now behaves **predictably and safely** when interacting with a cloud backend:

• no raw server errors
• no crash paths from networking
• consistent error messaging
• traceable requests
• privacy-preserving device identification

This establishes the foundation for **external TestFlight usage**.

---

# 7. Remaining Work (Next Conversation)

Remaining items outside the Step-4 scope:

• finalize backend fix for Gemini URL newline
• redeploy Cloud Run revision
• perform full smoke test suite
• verify client messaging for each failure case

---

# 8. Position in Roadmap

| Step                                   | Status        |
| -------------------------------------- | ------------- |
| Step 2 — In-App Help                   | ✅ Complete    |
| Step 3 — Backend Hardening + Cloud Run | ✅ Complete    |
| Step 4 — iOS Client Hardening          | ✅ Implemented |
| Step 5 — Cloud Smoke Testing           | ⏭ Next        |

---

# 🚀 Step 3B — Cloud Run Deployment Complete (LTC_AI_Gateway)

**Status:** ✅ Production Cloud Backend Live
**Date:** 2026-03-04
**Scope:** Cloud externalization of FastAPI backend
**Philosophy Preserved:** Stateless, advisory-only, no user accounts, no server-side storage

---

## 1. Cloud Architecture Achieved

Legacy Treasure Chest now runs its AI backend on **Google Cloud Run**.

### Production Service

```
Service Name: ltc-ai-gateway
Region: us-west1
URL: https://ltc-ai-gateway-530541590215.us-west1.run.app
Health Endpoint: /health
```

Health check verified:

```
HTTP 200
{"status":"ok"}
```

This confirms:

* Container builds correctly
* Secrets injected successfully
* Runtime environment stable
* Public invocation working

---

## 2. Infrastructure Decisions (Locked)

### Cloud Provider

* Google Cloud Platform
* Cloud Run (fully managed, stateless)

### Backend Design

* FastAPI
* Uvicorn container
* No database
* No user authentication (TestFlight phase)
* No server-side item storage
* Stateless request/response model

### Container Strategy

* `gcloud run deploy --source=.` flow
* Artifact Registry (Docker)
* Cloud Build for container builds

---

## 3. Security Model

### Secret Management

All sensitive keys moved to **Secret Manager**:

| Secret Name                 | Injected As             |
| --------------------------- | ----------------------- |
| `ltc-gemini-api-key`        | `GEMINI_API_KEY`        |
| `ltc-google-places-api-key` | `GOOGLE_PLACES_API_KEY` |

Secrets are:

* Not stored in repo
* Not stored in container
* Injected at runtime only

---

### Org Policy Override (Project-Scoped)

To allow public Cloud Run invocation:

Project-level overrides applied for:

* `iam.allowedPolicyMemberDomains`
* `iam.managed.allowedPolicyMembers`

This allows:

```
allUsers → roles/run.invoker
```

Only for project:

```
legacy-treasure-chest
```

No org-wide weakening of security.

---

## 4. IAM Permissions Stabilized

Resolved required service account permissions for:

* Cloud Build → push to Artifact Registry
* Compute SA → read source zips + write logs
* Cloud Run service agent → push images
* Secret Manager access at runtime

All required IAM bindings are now correctly configured.

---

## 5. Public Invocation Enabled

Cloud Run service is publicly callable:

```
allUsers → roles/run.invoker
```

This allows:

* iOS device calls
* TestFlight distribution
* No auth flow required (v1 constraint preserved)

---

## 6. Budget & Cost Controls

Budget created: **$50 alert**

Environment guardrails:

* `LTC_AI_PER_MINUTE_LIMIT`
* Kill switches:

  * `LTC_DISABLE_ALL_AI`
  * `LTC_DISABLE_GEMINI`
  * `LTC_DISABLE_PLACES`

Cloud Run limits:

* Concurrency: 20
* Min instances: 0
* Max instances: 2

Note:

> In-memory rate limiting resets on cold start (acceptable for v1).

---

## 7. iOS Integration Updated

`BackendAIProvider.swift` updated with build-configuration routing:

| Build Type           | Backend       |
| -------------------- | ------------- |
| Debug                | Local FastAPI |
| Release / TestFlight | Cloud Run     |

This enables:

* Local dev workflow unchanged
* Cloud demo capability from physical iPhone
* Clean separation of environments

No runtime toggle UI required.

---

## 8. Current Production State

LTC now has:

* ✅ Live cloud backend
* ✅ Secret-managed AI keys
* ✅ Public HTTP endpoint
* ✅ Budget alerts
* ✅ Health monitoring
* ✅ Device-ready demo capability

This marks transition from:

> “Local-only development system”
> to
> “Externally callable cloud-backed AI system”

---

# 🔜 What This Unlocks

Now possible:

* TestFlight external distribution
* Real-device cloud demo
* Controlled external trials
* Quota & usage monitoring
* Gradual auth layer introduction (future)
* Rate limiting hardening (future)
* Monitoring & structured logging expansion

---

# ⚙️ Documentation Files To Update

You likely want to update:

1. `README.md` (top section summary)
2. `CLOUD_READINESS_PLAN_v1.md`
3. `ARCHITECTURE.md`
4. `EXTERNALIZATION_PLAN_v1_3.md`
5. `ROADMAP.md` (mark Step 3B complete)

---

If you’d like, I can now:

* Produce a **separate architecture delta section**
* Or produce a **Cloud Run deployment appendix**
* Or prepare a clean **“Cloud Externalization Gate Complete” milestone entry**
* Or help define the next logical production gate

This was a major structural shift for LTC. You handled a full DevOps cycle end-to-end.


# 🟢 Production Readiness – Phase 1 Complete 3-2-2025

## Step 2 – In-App Help & Executor Clarity

**Status:** Complete
**Scope:** UI + Copy Only
**Backend Changes:** None
**Architecture Changes:** None

---

## Objective

Strengthen first-time user clarity and executor confidence prior to cloud deployment and TestFlight preparation.

This phase focused on eliminating ambiguity in:

* How to start using LTC
* What the system does (and does not do)
* How to attach critical documentation
* How scanning works in a practical, non-technical way

---

## Implemented

### 1️⃣ Home Screen Improvements

* Added **“Getting Started & Help”** card to Home (user-facing).
* Positioned as a primary support surface (not inside internal Tools).
* Styled distinctly from workflow actions (e.g., Sets).

---

### 2️⃣ HelpView.swift (Executor-Focused Help)

Structured in action-first order:

1. **Getting Started (First 5 Minutes)**

   * Explicit instruction to tap “View Your Items”
   * Inline icon guidance for:

     * Photo-based add
     * * button add
2. **Recommended Workflow**

   * Clean, numbered estate progression
3. **What This App Is**
4. **What This App Is Not**
5. **Scanning & Documents**

   * Dedicated navigation to deeper guidance
6. **Advisor Philosophy**

Tone: calm, professional, non-marketing.

---

### 3️⃣ ScannerHelpView.swift (Dedicated Help Screen)

Created separate screen to reduce cognitive overload.

Clarifies:

* When documents matter
* Simple attach flow
* Optional folder + naming structure (LTC Documents)
* Practical scanning technique tips
* How to move misfiled PDFs

Positioned as guidance — not required system behavior.

---

### 4️⃣ Contextual Microcopy (ItemDocumentsSection)

Added empty-state guidance:

> Tip: Use your iPhone’s built-in scanner in Notes or Files to create a PDF, then attach it here.

This reduces friction at the moment of action rather than relying solely on Help navigation.

---

## Design Philosophy Reinforced

* Advisor, not operator
* No automation of external systems
* No silent cloud storage
* No feature creep
* Executor-grade clarity over feature density

---

## Why This Phase Matters

Before moving to cloud deployment and TestFlight:

* First-time user experience must be calm and obvious.
* Documentation capture (receipts, appraisals, provenance) must feel manageable.
* Executor trust must be established through clarity and structure.

This phase meaningfully reduces onboarding friction without increasing technical complexity.

---

## Production Readiness Status

Phase 1: User Clarity & Help
→ **Complete**

Next milestone:
Cloud externalization preparation and TestFlight readiness.

---

## 2026-02-26 — AI Analysis Hardening Pass (Frontend + Backend)

### Summary

Production hardening of AI analysis workflow after real-world usage surfaced intermittent 502 failures from Gemini response validation.

### Backend Improvements

- Fixed schema repair issue in `/ai/analyze-item-photo`.
- Coerced `style` field from `[String]` → `String` before `ItemAnalysis` validation.
- Eliminates repeat 502 failures caused by valid but mismatched Gemini output.
- No architectural changes; minimal normalization layer hardening.

### Frontend Improvements

Unified graceful failure handling across:

- Add Item with AI
- Batch Add Items from Photos
- Item AI Analysis Sheet

Changes:
- Removed raw backend `HTTP 502` body text from UI.
- Added user-friendly error message.
- Added controlled **“Try Again”** button.
- Maintains advisor-not-operator principle (no automatic retries).

### Result

- AI analysis failures are now recoverable.
- No sensitive backend details exposed to end users.
- UX is resilient without expanding system complexity
---

# 🔄 2026-02-25 — UI Refinement Pass v1.1 (Currency & Dashboard Stabilization)

## Status: Presentation Maturity Phase

This session focused exclusively on **system-wide UI polish and formatting consistency**.
No new features were added.

Primary goal: remove false precision, standardize currency formatting, and stabilize layout behavior across views and dashboard summaries.

---

# 💰 1. Currency Formatting Standardization (System-Wide)

## Problem

Currency values were inconsistently formatted:

* Two decimal places displayed throughout the app (`$42,500.00`)
* Duplicate `NumberFormatter` implementations across:

  * `EstateReportGenerator`
  * `BeneficiaryPacketPDFRenderer`
  * `OutreachPacketPDFRenderer`
* SwiftUI views used `.currency(code:)` directly, allowing decimals
* Implicit false precision for advisory AI valuations

This implied appraisal-level precision that LTC does not claim.

---

## Decision

LTC now displays:

* **Whole-dollar values only**
* No cents anywhere in UI or PDFs
* Consistent display across:

  * SwiftUI views
  * Estate Snapshot PDF
  * Detailed Inventory PDF
  * Outreach Packet
  * Beneficiary Packet
  * Executor packet components

---

## Implementation

### 1️⃣ Centralized Currency Utility

Introduced shared formatting utility (`CurrencyText` / `CurrencyFormat`) used by:

* All SwiftUI views
* All PDF renderers

Removed duplicated `NumberFormatter` logic from:

* `EstateReportGenerator`
* `BeneficiaryPacketPDFRenderer`
* `OutreachPacketPDFRenderer`

All formatting now routes through a single source of truth.

---

### 2️⃣ SwiftUI View Updates

Replaced patterns like:

```swift
Text(item.value, format: .currency(code: currencyCode))
```

With:

```swift
CurrencyText.view(item.value)
```

And replaced:

```swift
total.formatted(.currency(code: currencyCode))
```

With centralized formatting equivalents.

Editable `TextField` currency inputs were updated to:

* Integer-based bindings
* `.precision(.fractionLength(0))`
* `.numberPad` keyboard where appropriate

---

## Result

* No false precision
* Stable whole-dollar formatting
* Professional advisory presentation
* Single currency formatting source

---

# 🧭 2. Estate Dashboard — High-Value Liquidate Items Layout Refinement

## Problem

The High-Value Liquidate section suffered from:

* Title column collapse (showing “P …”)
* Value splitting across lines (`$42,50` + `0`)
* Horizontal compression conflicts
* Overly tight row structure

This reduced readability and executive clarity.

---

## Design Change

Re-architected `highValueItemRow(for:)`:

### Old Layout

```
Thumbnail | Title/Category | Spacer | Value
```

This caused compression conflicts.

### New Layout

```
Thumbnail | Title
           Category
           Value
```

Value now appears **beneath the description**, eliminating layout contention.

---

## Improvements

* Larger thumbnail (56pt)
* Title limited to 2 lines
* Category single line
* Value placed below description
* Monospaced digits for visual stability
* No horizontal squeeze behavior

---

## Result

* Clean, stable dashboard layout
* High-value items now read like curated highlights
* Professional, executive-grade presentation
* Responsive across device sizes

---

# 📌 Architectural State After This Pass

LTC is now:

* Feature complete (current phase)
* Presentation stabilized
* Currency precision standardized
* PDF and UI formatting aligned
* Layout compression issues resolved



# ✅ Executor Master Packet v1 — COMPLETE

**Status:** Production-ready (On-device generation)
**Location:** Estate Dashboard → Export & Share → Executor Master Packet
**Export Model:** ZIP Bundle (2 PDFs + optional media)
**Philosophy:** Formal, operational export for executor / attorney / CPA use

---

## Purpose

The **Executor Master Packet** provides a structured, professional-grade export suitable for:

* Executor
* Attorney
* CPA
* Estate planning review
* Financial oversight

It is designed to be:

* Clear
* Complete
* Non-emotional
* Operationally useful
* Generated entirely on-device (no cloud dependency)

---

## What the Packet Contains (v1)

### Always Included (Required)

1. **ExecutorSnapshot.pdf**

   * Estate totals
   * Category summaries
   * Disposition summary
   * Beneficiary overview
   * Top-valued assets
   * Timestamp + advisory disclaimer

2. **DetailedInventory.pdf**

   * Full item list
   * Category
   * Quantity
   * Estimated value
   * Estate path (Legacy / Liquidate)
   * Assigned beneficiary (if applicable)

---

### Optional Inclusions (User Toggles)

* Audio recordings
* Supporting documents
* Images

  * Primary images only (default)
  * Full-resolution images (optional)

Assets are included in structured subfolders inside the bundle:

```
ExecutorMasterPacket_<Name>_<YYYY-MM-DD>/
    ExecutorSnapshot.pdf
    DetailedInventory.pdf
    Audio/
    SupportingDocs/
    Images/
```

---

## Guardrails & Share Controls

Export size is estimated before generation.

Guardrails:

* ≥ 50MB → Soft warning
* ≥ 100MB → Strong warning
* ≥ 250MB → Hard block

Share intent options:

* Mail / Messages
* Files / AirDrop (allows explicit override of hard block)

Preflight now includes realistic PDF size estimation (background generation).

---

## Architecture Notes

Files added:

* `ExecutorMasterPacketExportView.swift`
* `ExecutorMasterPacketComposer.swift`
* `ExecutorMasterPacketBundleBuilder.swift`

Reuses:

* `EstateReportGenerator`
* `ExportSizeEstimator`
* Existing guardrail and share infrastructure

Pattern parity with:

* Beneficiary Packet
* Outreach Packet

No schema changes required.

No cloud dependency.

---

## Design Intent

The Executor Master Packet represents the **most complete formal export in LTC v1**.

It is not:

* A contract
* A formal appraisal
* A binding estate plan

It is:

* An advisory estate state snapshot
* A structured operational reference
* A professional discussion document

---

## Production Gate Status

* ✅ Beneficiary Packet v1 — Complete
* ✅ Outreach Packet v1 — Complete
* ✅ Executor Master Packet v1 — Complete

Exports v1 feature set is now functionally complete.

---

## Beneficiary Packet v1 (Family / Heirs)

**Purpose:** A personal, legacy-forward export bundle for family members and heirs.

**Export model:** ZIP bundle  
`BeneficiaryPacket_<Name>_<YYYY-MM-DD>.zip`

**Contents:**
- `Packet.pdf` (always)
- `Audio/` (optional)
- `Documents/` (optional)
- `Images/` (selected images by default; optional full-resolution)

**Guardrails (bundle size):**
- Soft warning: ≥ 50MB
- Strong warning: ≥ 100MB
- Hard block: ≥ 250MB (requires explicit override via Files/AirDrop)

**User controls (before generation):**
- Toggle: Audio
- Toggle: Documents
- Toggle: Full-resolution images
- Preflight estimated bundle size + share recommendation (Mail vs Files/AirDrop)

**Entry points:**
- Estate Dashboard → Export & Share → Beneficiary Packet
- Beneficiary Detail → Export → Beneficiary Packet (prefilled beneficiary + assigned items)
---

## Status Update — Outreach Packet v1 (External Business Export)2-23-2025

Outreach Packet v1 is now functionally complete.

### Purpose
A professional, range-only export bundle designed for external business discussions, including:
- Auction houses
- Estate sale companies
- Dealers
- Consignment partners

### Architecture
OutreachPacket_<Target>_<YYYY-MM-DD>/
├── Packet.pdf
├── /Audio (if present)
└── /Documents (if present)

### Included Content

- Cover page with Packet Summary Block
- Sets (if applicable)
- Loose items
- Conservative value ranges (no exact values)
- Audio summaries (1–2 sentence AI-generated preview)
- Audio Appendix (with file references)
- Documents Appendix (with file references)
- Advisory footer (every page)

### Guardrails

- No checklist state
- No internal liquidation strategy
- No beneficiary assignments
- No exact value anchoring
- No cloud hosting
- No automatic sending

### Implementation Components

- `OutreachPacketComposer`
- `OutreachPacketPDFRenderer`
- `OutreachPacketBundleBuilder`
- `OutreachPacketExportView`

### Design Principle

Advisor, not operator.

All exports reflect the current catalog state and are generated entirely on-device.

---
### Included Content

- Cover page with Packet Summary Block
- Sets (if applicable)
- Loose items
- Conservative value ranges (no exact values)
- Audio summaries (1–2 sentence AI-generated preview)
- Audio Appendix (with file references)
- Documents Appendix (with file references)
- Advisory footer (every page)

### Guardrails

- No checklist state
- No internal liquidation strategy
- No beneficiary assignments
- No exact value anchoring
- No cloud hosting
- No automatic sending

### Implementation Components

- `OutreachPacketComposer`
- `OutreachPacketPDFRenderer`
- `OutreachPacketBundleBuilder`
- `OutreachPacketExportView`

### Design Principle

Advisor, not operator.

All exports reflect the current catalog state and are generated entirely on-device.

---
**Export Model:** Bundle-based (on-device only)

# ✅ What Was Accomplished (Session Summary)

### Backend

* Added `_post_gemini_text` for non-JSON Gemini responses
* Added `call_gemini_for_audio_summary`
* Implemented `POST /ai/summarize-audio`
* Validated base64 + MIME allowlist
* Clean 502 error handling
* Endpoint visible in `/docs`

### iOS

* Extended `AudioRecording` model with:

  * `summaryText`
  * `summaryStatusRaw`
  * `summaryGeneratedAt`
* Asynchronous summary generation after recording save
* Proper status lifecycle: `pending → ready/failed`
* Cleaned debug UI
* Removed hardcoded endpoint
* Rewired to `BackendAIProvider.defaultBaseURL`
* Confirmed end-to-end: iPhone → Mac mini → Gemini → SwiftData

### Architecture

* No branching logic added
* No duplication of base URL
* No blocking UI
* No export-layer coupling yet

This is production-grade groundwork.

---

# 📌 What Remains (Export Layer Context)

## Audio

* Add summary usage to Outreach Packet PDF (Audio Appendix)
* Decide: regenerate summary if missing during export? (Probably no — advisory system)

## Export Layer

* Finalize Outreach Packet v1
* Implement Packet Summary Block (cover page aggregation)
* Add asset bundling (PDF + audio files + documents)
* Standardize bundle naming convention
* Create export orchestration service (single pathway)

## Clean Architecture

* Consider moving audio summary call out of View layer and into:

  * ItemAudioService
  * or BackendAIProvider extension
* Add retry mechanism (optional)
* Add summary regeneration trigger (future)

---

## Audio Summary Pipeline (v1)

### Status

Complete and functioning end-to-end (local development).

### Flow

1. User records audio story.
2. Audio file saved locally under Media/Audio.
3. `AudioRecording` inserted with `summaryStatusRaw = "pending"`.
4. iOS asynchronously:

   * Reads file
   * Base64 encodes
   * Calls `/ai/summarize-audio`
5. Backend sends audio + prompt to Gemini.
6. Gemini returns 1–2 sentence summary.
7. Summary persisted to SwiftData.
8. Status updated to `ready` or `failed`.

### Design Principles

* Non-blocking UI
* Advisory only (no forced regeneration)
* No historical versions
* Single baseURL source (BackendAIProvider)
* Clean failure handling

### Future Use

* Outreach Packet Audio Appendix
* Beneficiary Packet emotional context
* Search indexing (future)

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

## Current Status (February 12, 2026)

### Valuation Aggregation Refinement (Batch + Lot)

During real-world household use, a valuation inconsistency was identified:

- Batch totals correctly aggregated individual items.
- Sets included in a batch were not contributing to batch or lot totals.
- Member items of a set risked being double-counted if both the set and its items were assigned to the same lot.

This has been corrected.

### What Changed

- **Batch estimated value now includes sets.**
- **Lot estimated value now includes sets.**
- If a set and its member items are assigned to the **same lot**, member items are excluded from the item subtotal to prevent double-counting.
- Lot Detail screen continues to show **individual items only** (explicitly labeled) to maintain structural clarity.

### Architectural Intent

- No new data fields were introduced.
- No override or sell-mode complexity was added.
- No automation was introduced.
- Logic remains deterministic and local.
- Advisor-first principle preserved.

This refinement hardens Batch v1 behavior without expanding scope.

---



## Execution Mode v1 (Implemented)

Execution Mode v1 enables a **non-technical executor** to complete a prepared batch using a **lot-centric, checklist-driven workflow**. This phase is intentionally lightweight, local-only, and non-automated.

### Core Characteristics
- **Lot-centric execution**
  - Execution is performed at the lot level (derived from batch items and sets).
- **Standard checklist**
  - Each lot uses a fixed, non-configurable checklist defined in code.
- **Local-first persistence**
  - Stored locally using SwiftData.
  - No backend calls, no automation, no AI during execution.
- **Advisor, not operator**
  - The system records executor actions but does not enforce or automate outcomes.

### What Is Persisted
For each checklist item in a lot:
- Completion state (Boolean)
- Optional completion timestamp
- Optional executor note

No batch-level execution state is persisted.

### Derived (Not Persisted)
- Per-lot execution progress (e.g. `3 / 9 (33%)`)
- Lot readiness (`Ready` is the final checklist item)
- Batch-level execution progress (derived by scanning lots)

### Completion Semantics
Execution Mode v1 is considered complete when **all lots** in a batch have their final checklist item:

> **“Lot is ready for sale / handoff”**

marked complete.

“Ready” represents executor confidence only.  
No system validation or state transition occurs.

### Explicitly Out of Scope (v1)
- Automation or task orchestration
- Partner handoff or listing workflows
- Pricing, export, or labeling features
- Execution-time AI assistance
- Batch-level execution state persistence

Execution Mode v1 is intentionally conservative and reversible, serving as a stable foundation for future execution enhancements.


## Batch v1 (Estate Sale Batches) — Completed (January 30 2026)

Batch v1 provides an executor-grade foundation for organizing an estate sale (or similar liquidation event) without automation or AI. The goal is to safely group **Items and Sets** into **Lots**, apply batch-specific overrides, and track readiness.

### What Batch v1 includes

**Data model**
- `LiquidationBatch` represents a liquidation event container (status, sale type, venue, provider, target date).
- Join models:
  - `BatchItem` links an `LTCItem` to a batch with batch-specific overrides.
  - `BatchSet` links an `LTCItemSet` to a batch with batch-specific overrides.
- Batch overrides (join level): `disposition`, `lotNumber`, `roomGroup`, `handlingNotes`, `sellerNotes` (and optional future-safe fields).

**UI**
- `BatchListView`
  - Lists batches with quick stats (lots, decisions progress, estimated value).
  - Create / delete batches.
- `BatchDetailView` (inside `BatchListView.swift` for now)
  - Edit batch metadata using safe pickers (Status / Sale Type / Venue).
  - Add Items / Add Sets sheets (deduplicated).
  - Lot grouping:
    - Assign/rename/clear lots
    - Lot totals: estimated value (items only) + Decisions X/Y
    - Batch readiness warnings (undecided entries, everything unassigned)
  - Entry editors for batch-specific overrides (items + sets).

### Design principles used
- **Advisor-first**: no automation, no selling execution, no AI in Batch v1.
- **Join model overrides**: item/set may be used differently across batches without modifying the underlying catalog entity.
- **Lots are execution units**: lots are designed for labeling, staging, and listing groups.
- **Compile-safe, incremental development**: built in small steps with frequent compile/run checks; bulk actions are reversible.

### Notes for future updates
- Estimated value currently totals **items only** (set valuation is intentionally deferred until a clear model is chosen).
- Batch UI is currently consolidated in `Features/Batches/BatchListView.swift` for speed; it can be refactored into separate files when Batch v2 begins.
- Next likely phase is **Execution mode** (lot checklists, staging, labels) or **Disposition Engine handoff** (partners/outreach).

## Current Status (January 28, 2026)

Legacy Treasure Chest continues to evolve as an **advisor-first**, production-quality system focused on clarity, trust, and executor-friendly workflows.

Recent updates include:

- **Jewelry v1 support**
  - Jewelry is treated as a distinct luxury category with advisory-only readiness guidance.
  - The system highlights key decision considerations (designer vs. materials-based jewelry) without enforcing classification or suppressing user choices.
  - Curated selling pathways are surfaced where appropriate, while keeping all decisions user-controlled.

- **Improved readiness checklist presentation**
  - Readiness checklists are now rendered cleanly and consistently across categories.
  - Internal metadata and redundant headings are removed from the UI, improving readability without changing underlying content.

- **Clearer user-facing language**
  - Internal concepts such as “Partner” remain unchanged in the codebase.
  - User-facing language now uses clearer, action-oriented terms (e.g., *Selling Options*, *Where to Sell*, *Local Help*).
  - “Local Help” is intentionally distinct from luxury selling workflows, reflecting real-world differences between proximity-based assistance and specialized luxury resale.

These changes reinforce the core design principle of Legacy Treasure Chest:

> **Advisor, not operator.**  
> The system provides informed guidance and best practices while preserving full control for users and executors.

** Readiness checklists are currently rendered as advisory markdown; future versions may introduce interactive checklist state.

## Recent Update — Luxury Categories v1 (Watches & Handbags)

The Legacy Treasure Chest app now includes first-class support for **Luxury Categories v1**, with a focus on **deterministic, advisor-grade guidance** rather than automated selling.

### What’s new

**Luxury Readiness Checklists (v1)**
- Category-specific readiness checklists appear in **Set → Execute Plan** for luxury sets
- Current supported luxury categories:
  - Watches
  - Designer Handbags
  - Designer Shoes / Boots
  - Designer Apparel
- Checklists are:
  - Set-scoped
  - Advisory only (no gating or scoring)
  - Bundled from a single source-of-truth markdown file

**Curated Luxury Partner Hubs**
- Luxury partner selection is **deterministic and instant**
- No backend or location search for luxury paths
- Category-specific routing:
  - Watches → watch-focused hubs (e.g. WatchBox / Chrono24)
  - Handbags → handbag-specialist hubs (e.g. Fashionphile / Rebag / Vestiaire)
  - Other luxury → general luxury mail-in hubs
- Supports informed executor or owner decision-making without forcing outcomes

**Path B Semantics**
- For qualifying luxury scenarios, Path B is labeled:
  > **“Luxury Mail-in Hub”**
- Determined via lightweight, explainable heuristics using set context and item summaries

### Design principles reinforced
- Advisor, not Operator
- Deterministic over inferred behavior
- Frontend-first, compile-safe iteration
- Executor-grade clarity over consumer marketplace UX

This establishes a stable foundation for future luxury categories (e.g. Jewelry) without expanding the data model or backend surface area.


## Current System Status (v1)

Legacy Treasure Chest is being developed as a production-quality, AI-native advisor for household inventory and disposition decisions. The system intentionally prioritizes correctness, trust, and real-world workflows over rapid MVP delivery.

### Disposition Behavior
- **Luxury categories use deterministic, curated partner paths** (e.g., luxury mail-in hubs)
- **Contemporary and lower-value categories use search-based discovery**
- Partner selection is advisory; the system does not automate transactions

### Readiness Checklists (New)
For deterministic disposition paths (e.g., Luxury Clothing, Luxury Personal Items), the system now defines **Readiness Checklists** that prepare users before partner execution.

- Readiness is **advisory, not blocking**
- Checklists focus on condition, authentication, and disclosure
- Readiness appears during **Execute Plan**, not during item entry or partner selection

The canonical reference for readiness logic and checklist content lives in:


## Project Status Update — Luxury Clothing & Closet Lots (2026-01-21)

This project has completed a **foundational milestone** in category-specific disposition planning, using **Luxury Clothing** as the first end-to-end vertical slice.

### What Was Completed

**1. Category Reality Locked (Luxury Clothing)**
- Confirmed that **Luxury / Designer clothing is not a local-discovery problem** in most markets.
- Implemented **hub-only, specialist-first disposition** for Luxury Clothing.
- Local consignment is no longer the default recommendation for this category.

**2. New Set Pattern Introduced: `Closet Lot`**
- Added a new `SetType.closetLot` to support selling clothing **as a lot**, without itemizing each garment.
- This enables realistic closet workflows while preserving the existing Item → Brief → Plan → Execute architecture.

**3. Disposition Engine Enhancement**
- Added a curated partner type (`luxury_hub_mailin`) that:
  - bypasses Google Places
  - returns specialist, national channels appropriate for luxury apparel
  - executes instantly and deterministically
- Existing categories and partner discovery behavior remain unchanged.

**4. UI & Model Alignment**
- Updated Set UI logic to properly handle `closetLot`.
- Ensured all enum switches are exhaustive and stable.
- Preserved conservative, category-based item suggestion logic (no premature inference).

**5. Authoritative Spec Created**
- Added **Clothing Disposition Spec v1** as the single source of truth for:
  - lot metadata
  - photo requirements
  - allowed disposition paths
  - Brief and Plan output contracts
- This spec will drive backend prompts and frontend capture going forward.

### Current State
- Architecture is stable.
- Changes are additive and non-breaking.
- Luxury Clothing now reflects real-world market behavior.
- The system is ready to extend **Brief + Plan generation for `closetLot`** using the approved spec.

### Next Focus
- Backend Brief/Plan support for:
  - `scope = set`
  - `setType = closetLot`
- Continue spec-first, incremental category expansion using the same pattern.

---

*Legacy Treasure Chest continues to prioritize correctness, executor-grade guidance, and real-world usability over speed to MVP.*

## Recent Update — Manual Item Creation with Photos (Stable, Cancel-Safe)

**Status:** Implemented and verified  
**Scope:** iOS UI / SwiftData (no backend changes)

### What Changed
Manual item creation now supports **adding photos during creation**, without forcing AI analysis or risking partial data persistence.

Users can:
- Create an item with **text + photos in a single flow**
- Review photos before saving
- **Cancel safely** without creating empty items or orphaned media files

This restores the natural real-world workflow:
> *“I’m holding the item → I add a photo → I add what I know → I save.”*

### Why This Matters
Previously, manual creation required photos to be added **after** the item was saved, which added friction and broke the natural capture moment.

This update:
- Improves capture ergonomics for single, high-attention items
- Preserves batch photo workflows for high-volume intake
- Maintains strict data integrity (no ghost items, no orphan files)

### Architectural Principles Preserved
- **Advisor, not operator**: AI analysis remains a deliberate, separate step
- **Capture ≠ Analysis**: Item creation is fast and local; AI is opt-in
- **Stability first**: No SwiftData objects or media files are persisted until Save
- **Zero side effects on Cancel**: Cancel leaves no trace in storage or database

### Implementation Notes (High Level)
- Photos selected during creation are held **in memory**
- Disk writes and `ItemImage` records are created **only after the item is saved**
- Cancel simply dismisses the view — nothing to clean up

This change lays a clean foundation for higher-value work:
**category-specific valuation, liquidation strategy, and disposition advice** — the core differentiators of Legacy Treasure Chest.


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
  - Backend is a FastAPI app that calls Gemini 2.5 (as of January 2026) and returns strict JSON.
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

