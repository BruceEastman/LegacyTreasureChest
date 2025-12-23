Below is the **complete `VALUATION_MODEL.md`** document, ready to drop into your repository root.
It is written in a clean, professional tone and explains the LTC valuation system clearly for users, developers, collaborators, and future maintainers.

If you want, I can also generate a shorter *user-facing* version later.

---

# `VALUATION_MODEL.md`

# **Legacy Treasure Chest — Valuation Philosophy & Expert System Overview**

*Last updated: December 10, 2025*
*Applies to: Jewelry Expert v1, Rugs Expert v1, Luxury Personal Items Expert v1*

---

# 📘 Purpose of This Document

This document describes **how Legacy Treasure Chest (LTC)** produces value estimates for household items, and the **principles, assumptions, and constraints** behind those valuations.

LTC is designed for **estate planning, downsizing, and personal asset organization**—not insurance appraisal, retail pricing, or auction cataloging.

This guide ensures that developers, testers, collaborators, and future maintainers understand:

* What the valuation system is doing
* Why it behaves the way it does
* How to interpret estimates correctly
* How category-specific experts operate

---

# 🧭 1. Core Valuation Philosophy

LTC provides **conservative fair-market resale valuations**, representing:

> **What a typical seller can realistically expect to receive in today’s market.**

This means:

### ✔ **NOT** retail / boutique pricing

### ✔ **NOT** insurance replacement cost

### ✔ **NOT** high-end exceptional auction outcomes

LTC estimates reflect **practical liquidity**—what an item is likely to sell for when listed or consigned, or when offered to a dealer, reseller, or buyer in the real world.

This approach is intentional because:

* Boomers downsizing or organizing estates need realistic numbers, not optimistic ones.
* Most users will not authenticate items, repair them, or pursue specialized buyers.
* Many items (e.g., rugs, non-designer jewelry) have **soft or saturated markets**.
* Consignment commissions, authentication friction, and buyer risk **reduce net proceeds**.

---

# 🔧 2. System-Wide Assumptions

To keep the system fast, simple, and user-friendly, the valuation model makes several consistent assumptions.

### **2.1 Minimal user effort**

Users supply:

* A photo (first photo drives the analysis)
* Optional additional details ("More Details for AI Expert")

No multi-step grading or complex measurement flows are required.

### **2.2 Assume “Good” Condition unless evidence suggests otherwise**

If the photo does not clearly show major damage, LTC uses **Good** as the baseline condition.
Users may override via notes.

### **2.3 Assume “Unauthenticated” unless proof is provided**

For luxury goods (watches, handbags, pens, designer jewelry):

* Lack of boxes, papers, serial numbers, or receipts results in conservative pricing.
* Authentication adds 10–40% value depending on the item.

### **2.4 Use resale comps, not retail listings**

For valuation ranges, LTC uses:

* Consignment sales
* Auction records
* Secondary-market platforms
* Realistic dealer offers

Not MSRP or boutique retail.

### **2.5 Replacement cost appears only as optional context**

Some categories (Jewelry, Luxury Personal Items) may present:

> “Approximate replacement cost for a comparable piece…”

This number **does not drive the valuation**.

---

# 🎯 3. What LTC Valuations Are Designed For

### ✔ Estate planning

### ✔ Downsizing

### ✔ Family asset documentation

### ✔ Equitable division

### ✔ Donation vs. sale decision-making

### ✔ Insurance scheduling (rough guidance, not appraisal)

### Not intended for:

❌ Insurance appraisal
❌ Auction reserve setting
❌ Professional gem grading
❌ High-end collector valuation
❌ Tax-deductible donation appraisals (IRS-qualified)

This is essential context for users and collaborators.

---

# 🧩 4. Category Expert Summaries

LTC uses category-specific “experts” encoded into the backend prompt.
Each expert has its own logic, missing-details behavior, and reasoning.

---

## **4.1 Jewelry Expert — V1**

### **Valuation Model**

Jewelry splits into two broad cases:

1. **Intrinsic-value pieces**

   * Gold weight, purity
   * Stone size, type, quality

2. **Designer pieces (Market-value)**

   * Tiffany, Cartier, Yurman, Mikimoto, etc.
   * Brand premium applied

### **Guiding Principles**

* Always return **fair-market resale**, not retail or insurance.
* Use conservative ranges when details are missing.
* When designer is confirmed, add a brand-appropriate premium.
* Typical resale venues: consignment, eBay, The RealReal, Worthy, local jewelers.

### **Common Missing Details**

* Metal purity (10k/14k/18k)
* Weight in grams
* Pearl size (mm)
* Hallmarks (clarity, authenticity markers)

---

## **4.2 Rugs Expert — V1**

### **Valuation Model**

Rug value is driven by:

1. **Knot Density (KPSI)** – single strongest factor
2. **Origin** – Persian workshop > regional > machine-made
3. **Materials** – wool, silk, cotton foundation
4. **Condition** – wear, low pile, repairs
5. **Size** – large rugs sell for less per sq ft
6. **Market softness** – resale market is generally saturated

### **Approach**

* Conservative resale values typical of estate sales.
* Wide ranges when KPSI or materials are unknown.
* Prompts request a close-up of the back with a ruler.
* Natural dyes, hand-spun wool, and fine weave increase estimates.

### **Common Missing Details**

* Approximate KPSI
* Back-of-rug close-ups
* Fringe and edge condition
* Exact size

---

## **4.3 Luxury Personal Items Expert — V1**

This category includes items where **brand + model + condition** drive value more than intrinsic materials.

### **What belongs here**

* **Watches:** Rolex, Cartier, Omega, Patek, AP, JLC, Panerai, Breitling, IWC, Tag Heuer
* **Handbags:** Hermès, Chanel, Louis Vuitton, Dior, YSL, Prada, Gucci, Bottega, Loewe
* **Pens:** Montblanc, Pelikan, Waterman, Visconti, Namiki/Pilot, Montegrappa
* **Small Leather Goods:** wallets, belts, card holders, cosmetic cases
* **Luxury Accessories:** sunglasses, scarves, cufflinks, money clips, S.T. Dupont lighters
* **Designer Jewelry:** Cartier Love, Tiffany T, Yurman Cable, Bulgari B.Zero1

### **Valuation Model**

* Assumes **unauthenticated** unless box/papers/serials are provided.
* Discounts reflect real resale channels (Fashionphile, WP Diamonds, eBay, TheRealReal).
* Condition matters more than for jewelry or rugs.
* Conservative ranges reflect net value after authentication risk and commissions.

### **Common Missing Details**

* Brand + model/reference
* Serial numbers / date codes
* Box, papers, authenticity cards
* Condition notes (scratches, tarnish, wear)
* Material and size (e.g., 25 vs. 30 for handbags)

---

# 📏 5. Interpretation of Valuation Ranges

LTC value ranges typically reflect:

### **ValueLow**

≈ Dealer offer, consignment net after fees, quick-sale scenario.

### **EstimatedValue**

≈ Reasonable private-sale expectation.

### **ValueHigh**

≈ Ideal resale scenario with good condition + buyer match.
(Not a guarantee. Not retail.)

---

# 🧱 6. Technical Implementation Notes

### **Backend**

* Experts are implemented as prompt blocks inside `analyze_item_photo.py`.
* The model returns strict JSON matching `ItemAnalysis` and `ValueHints`.
* `missingDetails` guides the user toward better future estimates.

### **iOS**

* First photo is used for AI analysis.
* Additional notes feed into the `userWrittenDescription` hints.
* ItemValuation stores userNotes, AI notes, ranges, and confidence.
* When suggestions are applied, the system updates title, description, and pricing.

---

# 🔄 7. Future-Proofing & Extensibility

Category experts can evolve independently, adding:

* Better missing-details logic
* More nuanced condition grading
* Authentication modeling
* Additional categories (artwork, furniture, collectibles, etc.)

This document should be updated each time a new category expert is added or its logic materially changes.

---

# 🏁 8. Final Notes

LTC’s valuation system is built around **trust, clarity, and realism**.
The goal is not exact retail price prediction—it is to help individuals and families make informed decisions with minimal friction.

This philosophy keeps the system simple, scalable, and consistent across categories.

---

If you’d like, I can also generate:

### ✔ A concise **user-facing explanation** suitable for the Help/FAQ section

### ✔ A version tailored for onboarding or marketing

### ✔ A more technical appendix explaining how the JSON model maps to SwiftData

Would you like any of those as well?
