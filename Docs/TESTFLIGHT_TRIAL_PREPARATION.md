# Refined Step 6 — Controlled TestFlight Preparation

### Key adjustment

For a **5–10 trusted tester trial**, the most important artifact is **not the App Store description** — it is the **tester briefing and testing instructions**.

Those determine whether testers:

* understand the product
* test the right workflows
* provide useful feedback.

---

# Step 6 Deliverables (Refined)

There are still **four deliverable groups**, but the execution order changes.

---

# 1. Technical Pre-Flight Verification (NEW GROUP)

This must happen **before writing or submitting anything**.

If this step fails, nothing else matters.

### Build Verification

Confirm:

* Clean **Release build**
* Archive succeeds
* Build uploads to App Store Connect
* Build processes successfully
* TestFlight build appears

Verify:

```
Version: 1.0
Build: 1
```

(or whatever you decide).

---

### App Capability Verification

Quick smoke test on device:

* App installs cleanly
* Onboarding works
* Photo analysis works
* AI response returns
* Export generation works

---

### Backend Health Check

Verify Cloud Run:

Health endpoint returns OK.

Confirm logs show:

* requests arriving
* Gemini responses returning
* no authentication failures

---

### Quota / Cost Safety Check

Confirm:

* Gemini quotas sufficient
* Google Places quota sufficient
* Cloud Run scaling safe

With 5–10 testers this is trivial, but verifying once is wise.

---

# 2. External Tester Brief + “What to Test”

These should be written **together**.

They come from the same content but serve two audiences.

| Artifact              | Audience             |
| --------------------- | -------------------- |
| External Tester Brief | Email / invitation   |
| “What to Test”        | TestFlight interface |

The brief will explain:

* what the product is
* what it is not
* who the test is for
* what we want feedback on
* privacy model

The **What to Test** field will focus on:

* specific workflows
* specific features
* feedback areas.

---

# 3. App Store Connect Listing Copy

For this controlled test, this does **not need to be marketing copy**.

It should simply be **clear and honest product positioning**.

Fields needed:

### Required

* Subtitle
* Description
* Keywords

### Optional

* Promotional Text

For TestFlight this text mainly helps:

* Apple reviewers
* curious testers

It does not need to be polished yet.

---

# 4. Trial Operations Plan

Once the build is live and testers are invited, define:

### Support Contact

You already have:

```
legacytreasurechest.com/support
```

But you should also include:

```
support@legacytreasurechest.com
```

(if you plan to use it).

---

### Issue Reporting Method

Recommend:

**Primary**
TestFlight “Send Feedback”

**Secondary**
Email

---

### Known Issue Communication

For 5–10 testers:

Simplest approach:

* email thread
* occasional TestFlight update notes

No system needed yet.

---

# 5. Trial Success Criteria

Before inviting testers, define what success means.

Suggested goals:

### Product Understanding

Testers understand:

* cataloging
* AI advisory
* exports

without explanation.

---

### AI Guidance Credibility

Testers feel:

* AI categorization is reasonable
* valuation ranges make sense
* partner suggestions feel plausible.

---

### Export Value

At least one tester finds:

* Executor Snapshot
* Inventory Report
* Outreach Packet

**useful and understandable**.

---

### Stability

No:

* crashes
* backend failures
* blocked workflows.

---
# 6 First External Install Dry Run

Before inviting external testers, perform a full TestFlight installation on a separate device.

Recommended method:

Invite a trusted internal tester (spouse or colleague) through TestFlight and use their device as the first clean installation.

Steps:

1. Upload the Release build to App Store Connect.
2. Enable TestFlight for external testers.
3. Send the first invitation to a trusted tester.
4. Install the build on their device via TestFlight.

Perform a full workflow:

- Launch the app
- Complete onboarding
- Add an item using the camera
- Run AI analysis
- Save the item
- Assign a beneficiary
- Generate an export

Verify:

- AI responses return successfully
- Cloud Run logs show requests
- Export PDF generates correctly
- No crashes or permission issues occur.

This validates the entire external distribution pipeline before inviting additional testers.

# Final Step 7 Execution Order

This is the **recommended sequence**.

### 1️⃣ Technical Pre-Flight

Verify:

* build
* backend
* quotas.

---

### 2️⃣ Write Tester Brief + “What to Test”

These are the **most important documents**.

---

### 3️⃣ Write App Store Connect Copy

Subtitle
Description
Keywords
Promotional text.

---

### 4️⃣ Upload Build

Archive
Upload
Process.

---

### 5️⃣ Invite Testers

Start with:

**3–5 testers first**, then expand to 10.

---

# One Strategic Observation

Your roadmap is very intentional about this phase being **observation, not growth**. 

That means the most valuable outcome of this step is **not downloads**.

It is discovering:

* where people hesitate
* where instructions are unclear
* whether the advisory model makes sense to outsiders.

Your onboarding and help system being complete already puts you in a **strong position for this phase**.

---

✅ **Recommended next step**

We should now create:

**1️⃣ External Tester Brief**
**2️⃣ TestFlight “What to Test” text**

Those two artifacts will shape how the trial actually unfolds.
