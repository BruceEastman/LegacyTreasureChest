# LTC Category Disposition Spec — Clothing (v1)

schemaVersion: 1  
Status: Draft (authoritative for implementation)  
Applies to: Item + Set scopes  
Primary Set Pattern: **Closet Lot as Set** (`setType = closetLot`)

## 0) Purpose and Non-Goals

### Purpose
Provide consistent, executor-grade advice for Clothing that:
- avoids “false local optimism” in secondary markets
- routes **Luxury/Designer** clothing to **specialist hub channels** by default
- routes **Non-luxury** clothing to **local convenience pathways** (donation / local resale) without thrash
- supports **lots** (a closet) without itemizing each garment

### Non-Goals
- No marketplace automation.
- No requirement to perfectly predict resale value; we prioritize correct channel selection + clear next steps.

---

## 1) Category and Scopes

### Canonical category string (from iOS)
- `category = "Clothing"`

### Supported scopes
- `LiquidationScope.item`
- `LiquidationScope.set` (primary for clothing “closet lots”)

### Default unit of work
- **Luxury/Designer:** item **or** lot (set) depending on volume.
- **Non-luxury:** lot (set) is default.

---

## 2) Clothing subtypes (for reasoning, not necessarily UI v1)

These subtypes guide the Brief/Plan reasoning. UI can stay simple v1; subtype can be inferred from notes/brands/photos.

- `mens_tailoring` (suits, sport coats, overcoats)
- `mens_shirts` (dress shirts, polos)
- `womens_apparel` (dresses, coats, separates)
- `footwear` (shoes, boots)
- `outerwear` (coats, leather jackets)
- `accessories` (scarves, belts, ties) — *note: handbags are often “Luxury Personal Items,” not Clothing*

---

## 3) Quality bands and thresholds (decision rails)

### 3.1 Condition band (required for closetLot)
- `LikeNew` (no visible wear, current season possible)
- `Good` (minor wear)
- `Fair` (visible wear, but usable)
- `Poor` (stains, tears, heavy wear)

**Condition floor**
- If `Poor`: default path is **donate/trash** unless brand is Tier 1 and the defect is minor/repairable.

### 3.2 Brand/value band (v1 heuristic)
We classify by “channel reality,” not hype.

**Tier 1 (Luxury/Designer)**
- Brands that have consistent resale demand and are best served by hub channels.
- Examples: Gucci, Brunello Cucinelli, Chanel, Dior, Prada, Saint Laurent, Loro Piana, Hermès, etc.

**Tier 2 (Better contemporary)**
- Good brands but not “hub-required”; can work with mail-in aggregators or selective local resale in some markets.
- Examples: Theory, Vince, Rag & Bone, A.P.C., etc.

**Tier 3 (Mainstream)**
- Gap/Old Navy/Title Nine equivalents; local resale/donation is the reality.

> Implementation note: v1 can infer “Tier” from brandHints (from user, from item analysis, or from lot metadata). Brand authority tables can come later.

---

## 4) Closet Lot as Set (`closetLot`) — required inputs

### 4.1 Model impact (minimal, additive)
Add a new SetType:
- `closetLot = "Closet Lot"`

This is required to gate the right UI fields and prompt variant selection.

### 4.2 Minimum lot metadata (UI capture)
For `setType = closetLot`, capture:

- `approxItemCount` (range ok: 20–40)
- `sizeBand` (e.g., “Men’s 42R / L”, “Women’s M”, “Mixed”)
- `conditionBand` (`LikeNew | Good | Fair | Poor`)
- `brandList` (0–12 brands; free text)
- `notes` (tailoring/alterations, storage, smoke/pets, original receipts, etc.)
- `splitInstruction` (default): **Allow split into Luxury vs Non-luxury piles**

### 4.3 Required photos (representative)
- `rail_or_pile_overview` (context)
- `label_collage` (5–12 labels if possible)
- `hero_examples` (1–3 representative “best items”)
- Optional: `wear_issues` (stains/heels/tears) if condition is Fair/Poor

---

## 5) Allowed disposition paths (Clothing)

### 5.1 Luxury/Designer (Tier 1) — default = hub-first
Primary:
- **Hub/National mail-in resale (specialist-first)**  
  PartnerType: `luxury_hub_mailin`

Secondary (only if user explicitly chooses local convenience / has a trusted local specialist):
- Local designer consignment (rare in secondary markets)

### 5.2 Better contemporary (Tier 2)
- Selective mail-in resale / aggregator  
- Local resale only if the market supports it (not assumed)

### 5.3 Mainstream (Tier 3)
- Donation with receipts
- Local thrift donation
- Local resale only if LikeNew and user wants time tradeoff

### 5.4 Always-available exit
- Donate / discard if condition floor is not met

---

## 6) Brief requirements (output contract)

### 6.1 Brief must include
- `valueRangeNetOfFees`: low / likely / high (coarse for lots)
- `effortLevel`: Low / Medium / High
- `timeToCash`: fast / moderate / slow
- `confidenceScore`: 0.1–1.0 (based on evidence quality)
- `missingDetails`: what would materially change the path (brands, labels, condition)
- `channelRecommendation`:
  - `hubFirst = true` for Tier 1, even in major cities
  - include rationale: “specialist buyer pool + authentication + logistics beats local browsing”

### 6.2 Brief “warnings / rails” (executor-facing copy)
- “Secondary markets rarely have true luxury resale capability. Default to hub specialists.”
- “Shipping can be faster than driving even in major cities; prioritize intake workflow quality.”
- “Do not donate until luxury potential is ruled out.”

---

## 7) Plan checklist blocks (reusable + clothing-specific)

### Block A: Split the lot (mandatory for closetLot)
- Separate into piles:
  1) Luxury/Designer
  2) Better contemporary
  3) Mainstream / donate
- Put “maybe” items in a hold pile until labels are checked.

### Block B: Create a simple manifest (lot-level)
- Count by pile
- List top brands by pile
- Note condition band and any standout items

### Block C: Photo package
- Overview + label collage + hero items
- Add close-ups for any Tier 1 items

### Block D: Choose channel
- Luxury pile → `luxury_hub_mailin`
- Contemporary → mail-in or selective local (if user insists)
- Mainstream → donation/local thrift

### Block E: Execute outreach / submission
- Use Disposition Engine “Execute Plan”
- Follow intake instructions
- Track status: NotStarted → InProgress → Completed

---

## 8) Disposition Engine execution (gated by Plan exists)

### 8.1 Partner types
For Clothing luxury plans:
- `luxury_hub_mailin` (curated results, not Places)
Optional for non-luxury plans:
- `donation`
- (future) `local_resale` (not required v1)

### 8.2 Trust model (important constraint)
- Google Places does not provide sufficient evidence for “luxury competence.”
- For `luxury_hub_mailin`, trust is:
  - “curated channel” + clear questions to ask
  - not “verified by snippets”

### 8.3 Search terms and query logic
- For `luxury_hub_mailin`: no search; return curated list
- For donation/local: normal Places search is acceptable

---

## 9) Minimum documentation package (for hub intake)
- Photos: overview + label collage + hero items
- Lot metadata: item count, condition band, size band, brand list
- Notes: alterations, receipts, provenance (if any)

---

## 10) Architecture impact assessment

### Required (minimal, additive)
- Add `SetType.closetLot`

### Optional (phase 2)
- Add structured fields on Set for:
  - `approxItemCount`, `sizeBand`, `conditionBand`, `brandList`, `tailoringNotes`
  - These can be stored as a dictionary/JSON blob initially if you want to avoid schema churn.

### Backend
- Prompt variants for `scope=set` + `setType=closetLot` (Brief + Plan)
- Disposition Engine: partnerType `luxury_hub_mailin` (already implemented)

### iOS UI
- When SetType = closetLot, show the minimal capture fields + photo expectations

---

## 11) Regression checklist (v1)

- Existing categories still match and return results.
- Brief → Plan → Checklist flows unchanged for Items and existing Sets.
- Disposition Engine still returns Places-based results for non-curated partner types.
- Clothing luxury scenario returns `luxury_hub_mailin` and does not call Places.
- Outreach compose still works (email/web/phone selection).
