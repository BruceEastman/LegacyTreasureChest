Smoke test: Disposition Engine — Local Help (Planned Capability)
curl -s http://127.0.0.1:8000/ai/disposition/partners/search \
  -H "Content-Type: application/json" \
  -d '{
    "schemaVersion": 1,
    "scope": "item",
    "chosenPath": "B",
    "scenario": {
      "category": "Furniture",
      "valueBand": "MED",
      "bulky": true,
      "goal": "balanced",
      "constraints": ["pickup_required"]
    },
    "location": {
      "city": "Boise",
      "region": "ID",
      "countryCode": "US",
      "radiusMiles": 25,
      "latitude": 43.6150,
      "longitude": -116.2023
    },
    "hints": {
      "keywords": ["Thomasville"],
      "notes": "Dining chair"
    }
  }' | python3 -m json.tool


# Disposition Engine — Local Help (Planned Capability)

**Status (as of 2026-01-01):** Planned / not implemented yet.  
**Depends on:** Stable single-item Liquidation Plan UX and persistence (Liquidate Milestone 2).  
**Role:** Advisor-only. The app prepares recommendations and outreach materials; the user performs contact and execution.

---

### Summary of how this fits your current plan

* **Conceptually, this “Disposition Engine” fits perfectly** with the Liquidate module as an *Advisor* (not an operator). It becomes the “last mile” that turns a liquidation recommendation into **real-world next steps** without you integrating with marketplaces.
* Architecturally, it should be a **backend-backed capability** that uses your existing inventory + valuation + set context to:

  1. recommend *which kind of local partner* to use (auction vs consignment vs donation vs estate-sale company), and
  2. produce *a short list of vetted local options* + a ready-to-send outreach packet.

---

## 1) Where this belongs in the Liquidate architecture

### It’s not a new module — it’s a Liquidate “capability”

Think of Liquidate as three layers:

1. **Decision Support (Brief + Plan)**

   * Path A/B/C/Donate, net proceeds vs effort, risks, plan checklist

2. **Execution Support (Disposition Engine)** ← your new concept

   * “Who locally can do this well?” (and why)
   * Contact workflow + inventory packet

3. **Tracking**

   * status, notes, outcomes, “who did I contact?”, “what did they say?”

This means your current plan stays intact: **LTCItem + LiquidationBrief + LiquidationPlan**, and we add a *partner-discovery + outreach* capability that the Plan can call into.

---

## 2) The “Disposition Matrix” is exactly right — with one refinement

Your proposed table is a great start: **Category → search query strategy → success filters**.

The refinement: don’t map only by *Category*. Map by **Disposition Scenario** (category is just one input). Example:

* Furniture + bulky + moderate value + user wants min effort → consignment / estate liquidator
* Tools + high brand likelihood + user wants maximize value → auction / specialty reseller
* Media + low value + user wants fast → donation / bulk buyer (if exists)
* Whole house + “deadline” + user wants minimal effort → bonded/insured estate sale + cleanout

So the Matrix input should be:

**(Category, Value band, Bulkiness, Set membership, User goal, Constraints, Location)** → **Partner Type + Query Templates + Filters**

That’s the “engine.”

---

## 3) How it leverages your estate inventory (your big advantage)

This is where your app becomes meaningfully differentiated:

### A) The inventory makes discovery *actionable*, not generic

When you send an estate sale company a typical “we have stuff” message, they assume chaos.

When you send:

* item counts by category
* highlight list (high value / high friction items)
* photos/notes for anchor items
* set groupings (dining room set, tool lot, rug collection)
* rough total value bands (conservative)

…you’re delivering *qualified inventory*.

That’s why your “handshake” idea is strong: it converts inventory into **credibility**.

### B) Sets become an outreach feature, not just valuation

Your “set of rugs” example is particularly good: it’s not about selling rugs individually; it’s about telling a *designer story*.

Disposition Engine can output:

* “Sell together preferred: yes”
* “One-page set summary”
* “Top 6 photos across the set”
* “Why this set is cohesive”

That’s exactly the kind of thing a local dealer/designer responds to.

---

## 4) Backend architecture that fits your current direction

You already have a backend AI gateway. The Disposition Engine can be another backend feature with two endpoints (v1):

### Endpoint A — Partner Discovery

**POST** `/liquidate/partners/search`

Inputs:

* category + subcategory hints (e.g., Tools → hand tools vs machinery)
* estimated value band (low/med/high)
* bulky flag
* user location (zip/city; keep it coarse for privacy)
* chosen path (A/B/C/Donate)
* optional keywords (brands: Snap-on, Waterford, Thomasville)

Outputs:

* ranked partner list with:

  * partnerType (consignment/auction/donation/estate sale)
  * name, address area, phone, website
  * “why we picked this”
  * trust signals found (e.g., “bonded/insured” mention)
  * confidence score
  * “what to ask them” checklist

Implementation note: You can do this with a Places provider (Google Places, Yelp Fusion, etc.) plus **post-filtering** with your keyword heuristics. (No marketplace APIs.)

### Endpoint B — Outreach Pack Builder

**POST** `/liquidate/outreach/compose`

Inputs:

* chosen partner
* selected inventory scope:

  * single item
  * set
  * whole estate summary
* optional: attach PDF id / generate summary PDF

Outputs:

* subject line
* email body
* attachment list (inventory PDF, set PDF, photos)
* follow-up prompts (e.g., “ask about cleanout, commission, timeline”)

This aligns with your “advisor” positioning: you’re not contacting anyone automatically; you’re **preparing the handshake**.

---

## 5) Trust filtering: your instincts are correct (and important)

Your “bonded insured” requirement is a great example of a **Trust Gate**.

I’d formalize this as:

* **Partner Type → Required Trust Gates**

  * Estate sale / whole-house liquidators: “bonded”, “insured”, “licensed” (as applicable), membership markers
  * Donation centers: “receipt”, “tax deduction”, accepted items list
  * Auctions: “business liquidation”, “estate auctions”, commission transparency
  * Consignment: “consignment”, “payout schedule”, “pickup available”

This matters because it avoids surfacing random results and protects credibility.

---

## 6) How it should show up in the UI

Inside your **Liquidation Plan**, add a section:

### “Local Help”

* Button: **Find local options**
* Results: 3–7 cards (ranked), each with:

  * “Best for: bulky + quick exit”
  * “Trust signals found”
  * “Questions to ask”
  * Actions:

    * Call
    * Open website
    * Compose email (pre-filled, attach inventory PDF)

You’ll get big perceived value from this without touching marketplaces.

---

## 7) One important caution

The specific Boise/Kuna business names you listed are useful as examples, but the *system* should treat them as **discoverable**, not hard-coded. Businesses change names, policies, and marketing copy. So build the engine around:

* query templates + filters + ranking
* cache results briefly
* show “why” and “verify details” language

---

## 8) Recommended next step (one decision)

Pick where the “Disposition Matrix” lives:

**Option 1 (recommended): Backend-configured matrix**

* store query templates + trust gates in backend config (JSON)
* app requests “partner suggestions” with context
* you can tune logic without shipping an iOS update

**Option 2: App-local matrix**

* faster to implement, but you’ll re-ship for every tuning pass

Given how often you’ll refine this, **Option 1 is the better fit**.

---

If you say “go,” the next thing I’ll produce is a tight spec for the backend-side **Disposition Matrix JSON** (schemas for query templates, trust gates, ranking weights) that cleanly plugs into your existing AI gateway style—without committing you to any specific vendor API yet.

---

## Implementation milestones (v1)

### Milestone DE-1 — Partner Discovery (backend)
**Endpoint:** `POST /liquidate/partners/search`  
**DoD**
- Accepts scenario inputs (category, value band, bulkiness, user goal, constraints, coarse location).
- Returns 3–7 ranked partners with:
  - partner type
  - why selected
  - trust signals found (trust gates)
  - confidence score
  - questions to ask

### Milestone DE-2 — Outreach Pack Builder (backend)
**Endpoint:** `POST /liquidate/outreach/compose`  
**DoD**
- Generates a subject + email body + attachment list
- Supports scope: single item (v1), set/batch (future)

### Milestone DE-3 — iOS “Local Help” section inside Liquidation Plan
**DoD**
- “Find local options” button
- Ranked cards
- Actions: Call, Website, Compose Email (prefilled)
- Copy clearly states: “Verify details; businesses change.”

---

## Explicit non-goals (v1)
- No hard-coded local businesses
- No auto-contacting or messaging on the user’s behalf
- No marketplace integrations
