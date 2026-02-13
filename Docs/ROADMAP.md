# Legacy Treasure Chest — Roadmap to Production

**Last Updated:** 2026-01-30

This roadmap reflects the *actual state* of Legacy Treasure Chest today and defines a disciplined path from a proven single‑user system to a small, controlled external trial. It intentionally prioritizes **executor‑grade completion, clarity, and reversibility** over speed or monetization.

> **Core principle:** Advisor, not operator. Ship only what increases confidence for real people doing real estate work.

---

## Capability Spine (Locked)

The original capability spine has been followed closely and remains the organizing backbone of the product:

1. **Item (inventory + content)**
2. **Beneficiary association**
3. **Single‑item liquidation**

   * Brief (why / tradeoffs)
   * Plan (what to do)
   * Checklist (execution)
4. **Disposition Engine**

   * Local partner discovery
   * Outreach preparation
5. **Sets**

   * Sell‑together / lot logic
   * Set‑level summaries
6. **Estate Sale / Batch Exit**

   * Select items and sets
   * Lot grouping
   * Executor‑grade overrides

This spine is considered **complete through #6 (Batch v1)**.

---

## Production Gates (New)

To avoid scope creep and premature distribution, development now proceeds through **explicit production gates**. A gate must be completed and stable before moving to the next.

---

## Gate 1 — Execution Mode v1 (In Progress)

**Goal:** Enable a non‑technical executor to *finish* a prepared batch.

**Definition of done:**

* Execution is **lot‑centric**
* Each lot has a **standard, non‑configurable checklist**
* Checklist state is:

  * Lightweight
  * Reversible
  * Separate from planning
* A user can clearly answer: *“Which lots are done, and which are not?”*

**Explicit non‑goals:**

* No automation
* No partner handoff
* No pricing or listing changes
* No AI execution guidance

> Execution Mode v1 is the final internal‑use feature required before involving external users.

---

## Gate 2 — Externalization Readiness (Planned)

**Goal:** Make the system safe, predictable, and understandable for people who are not the original builder.

This phase is intentionally small and finite.

### Scope

* UX clarity sweep (no dead ends, clear empty states)
* Executor‑friendly warnings (advisory, not blocking)
* Failure tolerance verification (AI unavailable, partial data, abandoned flows)
* First‑run explanation:

  * What the app *does*
  * What it *does not do*
  * How it is meant to be used

**Outcome:**

* A trusted person can use the app without hand‑holding
* No irreversible actions
* No confusion about completion

---

## Gate 3 — Exports & External Views v1 (Planned)

**Goal:** Allow LTC to safely and clearly communicate *outward* once the physical estate is documented.

This is not sharing or collaboration. It is **controlled externalization** of read‑only information.

### Export Units (v1)

* **Item export**

  * Complete item record
  * Photos, documents, notes, valuation context
* **Set export**

  * Cohesive summary + member items
* **Batch / Lot export**

  * Executor‑ready packet
  * Lot grouping, handling notes, readiness state
* **Beneficiary summary export**

  * For attorneys or executors

### Format (v1)

* PDF or bundle‑based
* Purpose‑specific layout (dealer, executor, advisor)
* Designed for email or message attachment

**Non‑goals:**

* No portals
* No access control
* No two‑way sync

---

## Gate 4 — Controlled External Trial (TestFlight)

**Goal:** Learn how real people actually use the system.

### Characteristics

* 5–10 trusted users
* TestFlight distribution only
* No marketing
* No monetization
* No promises

### What We Observe

* Where users hesitate
* What they finish vs abandon
* Which exports they use
* Which parts create confidence

This gate informs *all* future decisions.

---

## Instrumentation (Plan, Not Enforcement)

Before or during the external trial, lightweight usage markers may be added:

* Has created items
* Has created a batch
* Has entered execution mode
* Has completed a batch

All instrumentation is:

* Local‑first
* Anonymous
* Observational only

---

## Monetization & Licensing (Intentionally Deferred)

No licensing, paywalls, or business logic will be implemented until:

* External usage patterns are observed
* Value is clearly demonstrated
* The buyer (owner vs executor) is understood

This is a **deliberate decision**, not an omission.

---

## Guiding Principle Going Forward

> Finish real work first. Then invite others.

This roadmap exists to protect focus, preserve trust, and ensure that Legacy Treasure Chest matures into a production‑quality, executor‑grade system before it ever asks anyone else to rely on it.

**Summary — recommended initiatives and sequencing**

You’re thinking about the right things at exactly the right time. The key is **not to let future distribution concerns distort the way you finish the system for yourself**. The sequencing below keeps the product *truthful*, while quietly laying rails for expansion.

High level:

1. **Finish your Physical Estate Plan the way you actually think**
2. **Harden the system under real use (you-only)**
3. **Prepare for controlled observation, not scale**
4. **Only then: TestFlight + cloud backend**
5. **Public-facing infrastructure last**

---
# Steps as of 2-05-2026 (ChatGPT)

## 1. Your usage model is exactly right (and important)

Your description of how you intend to work is *the* correct anchor:

* **Items first**
* **Sets when they naturally emerge**
* **Lots when you mentally group work**
* **Batches only when you would realistically sell or hand off together**

Dining room set + china + crystal + flatware is the canonical example of a **human-correct lot**.
Jewelry and luxury clothing becoming *separate, instruction-heavy lots* is also exactly right.

This confirms a crucial design truth:

> **Lots are cognitive groupings of work, not data constructs to be planned upfront.**

Your current architecture already supports this. The remaining work is *observational*, not structural.

---

## 2. Initiative A — Finish *your* Physical Estate Plan (Primary)

**Timeframe:** Now → ~2–3 weeks
**Environment:** Local Mac mini backend (stay local)

### What this actually means in practice

* Create Items opportunistically (real objects, real photos)
* Let Sets appear only when your brain says “these belong together”
* Let Lots appear only when you think “I’d handle these at once”
* Delay Batches until you can point to a real-world moment (“estate sale”, “consignment run”, “dealer outreach week”)

### What you are harvesting

Not data — **design signals**:

* When you hesitate
* When you invent notes outside the system
* When a checklist feels slightly wrong
* When you want to *say something to a future executor*

Those moments define:

* Gate 2 UX changes
* Execution Mode v1.1 tweaks
* Export semantics

**Do not rush to fix things.**
Keep a running “friction list” and let patterns emerge.

---

## 3. Initiative B — Backend stays local (for now)

You are absolutely right to **not** move the backend off your Mac yet.

### Why this is correct

* You are still *debugging semantics*, not scaling traffic
* Latency, retries, and quotas are not the current risk
* Moving too early creates:

  * DevOps noise
  * False urgency
  * Pressure to stabilize things that are still evolving

**Rule of thumb**

> Do not deploy until you would be embarrassed if the system went down for a day.

You’re not there yet — and that’s good.

---

## 4. Initiative C — Controlled observation > “users”

Your instinct to recruit **expert, tolerant, technically savvy users** is correct — but the framing matters.

These are **observers**, not customers.

### What you actually want from the first 5–10 people

* Different cities → test **Google Places**
* Different housing styles → test item diversity
* Different liquidation instincts → test advisory language

What you **do not** want yet:

* Feature requests
* Opinionated UX debates
* Emotional attachment to outcomes

### How to recruit them (when ready)

Think:

* Estate attorneys
* Professional organizers
* Downsizing consultants
* Senior technologists with aging parents

The pitch is not “try my app.”
The pitch is:

> “Help me validate whether this advice is sane.”

That framing keeps the signal clean.

---

## 5. Initiative D — TestFlight comes *after* friction stabilizes

You already have the Apple Developer membership — good.

But **Apple TestFlight** should be treated as a *delivery mechanism*, not a milestone.

### Correct trigger for TestFlight

* You can hand your phone to someone
* They can complete a small, real task
* You do not feel the need to narrate

Until then:

* Local builds are superior
* Distribution is a distraction

---

## 6. Initiative E — Website & support infrastructure (later than you think)

You are right that you’ll need:

* A website
* A way to track “others’ use”
* A place not to lose issues

But **not yet**.

### What to do now instead

* Keep a single, private “Field Notes” document
* Capture:

  * Confusion
  * Misinterpretations
  * Emotional reactions
* Do not categorize yet

When patterns repeat, *then* you design:

* FAQ
* Support flows
* Messaging
* Positioning

If you build the site first, you’ll encode assumptions that haven’t been earned.

---

## 7. Major risks you *are* already avoiding (good news)

You are already steering clear of the big traps:

* ❌ Premature multi-user support
* ❌ Automation pressure
* ❌ Marketplace coupling
* ❌ “MVP” thinking
* ❌ Letting Google Places dictate product shape

One subtle risk to keep an eye on:

> **Over-documenting before reality forces clarity**

Your discipline around “earned documentation” is exactly right. Keep it.

---

## Suggested sequencing (clean and realistic)

**Now**

* Use LTC to build your real Physical Estate Plan
* Stay local
* Capture friction, don’t fix immediately

**Next**

* Small UX and copy refinements (Gate 2)
* No new capabilities

**Then**

* First exports (only what *you* need to send)
* Still single-user

**Then**

* TestFlight with 5–10 observers
* Backend moves to cloud only when necessary

**Last**

* Website
* Support
* Public narrative

---

## One grounding check (optional)

As you work, periodically ask yourself:

> “If I were gone tomorrow, would this lot make sense to someone calm but uninformed?”

If the answer is “mostly,” you’re on exactly the right path.

If you want, next we can:

* Define a **“Field Notes” structure** for capturing friction without derailing work, or
* Walk through one concrete example (e.g., dining room + china lot) and pressure-test the current model.

**Short answer (so we anchor):**
No — you do **not** give observers access to your Mac mini.
You give them **controlled access to *a copy* of the system**, in stages, with the backend moved *just enough* off your machine to support observation — not scale.

Below is the clean way to think about this, without over-engineering.

---

## The core constraint (and why it matters)

Your system today has three realities:

1. **iOS app** — runs on *their* device
2. **Backend AI gateway** — currently runs on *your* Mac mini
3. **Observer goal** — validate advice quality, not infrastructure

Remote access to your Mac (VPN, exposed ports, shared dev box) fails on:

* Security
* Reliability
* Mental overhead
* Professional credibility

So: **that option is off the table** 👍

---

## The correct mental model for observers

Observers are not “using *your* system.”

They are using:

> **Their own local copy of the app + a shared, minimal backend environment**

That backend is:

* Stateless
* Disposable
* Cheap
* Not yet “production”

---

## The right sequencing (no big jumps)

### Phase 1 — You only (now)

* iOS app: local build
* Backend: Mac mini
* Purpose: correctness, semantics, friction discovery

✅ This is exactly where you are now.

---

### Phase 2 — Observer-ready backend (small move, big unlock)

When you are ready for **observers**, you do **one thing**:

> Move the backend AI gateway to a minimal cloud runtime.

This does **not** mean “production infrastructure.”

It means:

* A single deployed FastAPI service
* One environment
* No scaling logic
* No monitoring beyond logs

Good fits (pick later, not now):

* Google Cloud Run
* Fly.io
* Railway

(We’ll choose based on friction, not ideology.)

**Important:**
This backend exists *only* to let others run the app.

---

### Phase 3 — App distribution to observers

At this point, observers get:

* The app via:

  * Apple TestFlight
* Backend URL baked into:

  * A config flag
  * Or environment-based endpoint selection

They install.
They sign in.
They use the app.
They never touch your machine.

---

## What observers actually do (and don’t do)

### They DO:

* Add real items from their home
* Run liquidation advice
* See Google Places results in *their city*
* Create lots and batches
* Tell you where advice feels wrong or missing

### They do NOT:

* See your data
* Share data with each other
* Depend on uptime guarantees
* Expect polish
* Expect permanence

This is observation, not onboarding.

---

## Why this is still safe and aligned with your philosophy

This approach preserves all of your principles:

* ✔ Advisor, not operator
* ✔ No multi-user complexity
* ✔ No shared data model
* ✔ No irreversible actions
* ✔ No premature infrastructure work

You’re simply replacing:

> “backend runs on my desk”

with:

> “backend runs somewhere boring and quiet”

---

## A subtle but important point

You do **not** need:

* Accounts
* Teams
* Roles
* Sharing
* Collaboration
* Permissions

Each observer is still a **single-user system** — just like you.

The backend is shared.
The data is not.

---

## When *not* to do this yet

Do **not** move the backend until:

* You are mostly done changing prompt structure
* Execution Mode semantics feel stable
* You’re no longer constantly restarting the backend

If you’re still iterating daily → stay local.

---

## Recommended decision gate (simple and honest)

Ask yourself this:

> “If an observer used this for a week, would I learn more than I would from another week of solo use?”

When the answer is **yes**, you move the backend.

---

## Next logical follow-up (when you’re ready)

When you say “yes, let’s prep for observers,” the *next concrete steps* would be:

1. Define **observer scope** (what they should try)
2. Choose **one** backend host
3. Add a backend environment switch
4. Prepare a one-page observer brief

No more than that.

If you want, next we can:

* Sketch the **minimal observer architecture**, or
* Draft the **observer invitation brief** (which is more important than tech).
