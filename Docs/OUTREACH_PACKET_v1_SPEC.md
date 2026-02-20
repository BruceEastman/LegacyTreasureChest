
# Legacy Treasure Chest

# Outreach Packet v1 Specification

**Status:** Draft – Ready for Implementation
**Scope:** Audience-Specific Export (External Business)
**Export Model:** Bundle (PDF + optional assets)
**Generation:** On-device only
**Philosophy:** Advisory system, not operator

---

# 1. Purpose

The Outreach Packet enables the LTC user to initiate a professional evaluation or consignment discussion with an external business (dealer, auction house, estate sale company, luxury hub, etc.).

It is a curated, professional-grade export artifact derived from a specific **LiquidationTarget**.

It is:

* Informational
* Advisory
* Non-binding
* Standalone (no cloud dependency)

It is not:

* A contract
* A formal appraisal
* A checklist-enabled operational document

---

# 2. Audience Definition

**Audience Type:** External Business
**Internal Identifier:** `ExportTarget.partner`
**User-Facing Name:** Outreach Packet

Tone:

* Professional
* Neutral
* Transaction-ready
* Non-emotional

---

# 3. Export Model (Locked Architecture)

All exports generate a **Packet Bundle**.

```
OutreachPacket_[RecipientOrTarget]_[YYYY-MM-DD]/
 ├── Packet.pdf
 ├── /Audio (optional)
 ├── /Documents (optional)
 └── /Images (optional future use)
```

Even when no assets exist beyond the PDF, a bundle is generated.

No remote hosting. No links. No authentication required to open.

---

# 4. Scope Abstraction

The Outreach Packet is generated from a **LiquidationTarget**.

```
LiquidationTarget
  - batch(BatchID)
  - set(SetID)
  - item(ItemID) [future-compatible]
```

v1 supports:

* Batch (may contain multiple sets and loose items)
* Set (single set context)
* Multiple sets within a single batch are supported

---

# 5. Value Visibility Policy

External exports use:

**ValuePolicy: Range Only**

* No exact values displayed.
* Conservative value range shown per item/set.
* Conservative total range shown at packet level.

Disclaimer language required:

> Values shown are advisory estimates for discussion purposes and are not guarantees of sale price.

---

# 6. Asset Inclusion Policy

## 6.1 Photos

* Primary photo embedded in PDF Item Card.
* Additional photos may be embedded or included later if needed.
* Originals not required in v1.

## 6.2 Audio

Audio files are included in `/Audio` folder when present.

Each included audio file:

* Named with stable index prefix: `01_ItemName.m4a`
* Referenced clearly inside PDF.

### Audio Summary Policy (Locked)

* AI-generated summary created at **record time**
* Stored persistently with item
* 1–2 sentence summary maximum
* Used in PDF as contextual preview

PDF displays:

* Item title
* Recording duration
* “Owner’s Note (AI summary)”
* Filename reference

Full transcript not included.

## 6.3 Documents

If items contain attached documents (appraisals, certificates, receipts):

* Include original PDF files in `/Documents`
* Reference filename in Item Card
* Do not modify or rewrite documents

---

# 7. Packet Structure (PDF Layout)

## 7.1 Cover Page

Contains:

* Title: Outreach Packet
* LiquidationTarget name
* Owner name
* Generation date
* Advisory timestamp
* Professional disclaimer

### Packet Summary Block (Required)

Displays:

* Loose item count
* Set count
* Total conservative value range (entire packet)
* One-line orientation statement:

Example:

> This packet presents sets first, followed by individual items included in this liquidation target.

---

## 7.2 Sets Section (if applicable)

Each Set receives:

### Set Summary Card

* Representative photo
* Set name
* Brief description
* Item count within set
* Conservative value range (set-level rollup)

Member items follow as Item Cards.

---

## 7.3 Individual Items Section

Loose items not belonging to sets are displayed after sets.

---

## 7.4 Item Card Structure

Each item includes:

* Primary image
* Title
* Category
* Description (concise)
* Quantity
* Conservative value range
* Owner’s Note (AI summary) if audio exists
* Asset indicators:

  * “Audio included”
  * “Document included”

Explicitly omitted:

* LiquidationState
* Checklists
* Beneficiary assignments
* Executor notes
* Internal brief/plan content

---

## 7.5 Audio Appendix

Optional section listing:

* Item title
* Duration
* AI summary (repeated)
* Filename reference

Purpose:

* Allows PDF to stand alone if audio not opened
* Helps attorneys or evaluators skim

---

## 7.6 Documents Appendix

Optional listing:

* Item title
* Document filename
* Document type (if stored)

---

## 7.7 Advisory Footer (Every Page)

Footer includes:

* “Generated on-device from current catalog state”
* Generation timestamp
* Advisory language
* Page number

---

# 8. Call to Action Field

Each Outreach Packet includes a **Primary Call to Action** block.

Text template:

> Contact [Owner Name] at [Email / Phone] to discuss evaluation or consignment terms.

## Contact Source Policy (Locked)

* Default from Owner Profile
* Export-time override allowed
* Optional “Save as default” option if profile missing

---

# 9. Explicit Omissions (Guardrails)

The Outreach Packet must NOT include:

* Checklist state
* Readiness indicators
* Execution steps
* Partner recommendations
* Beneficiary assignments
* Internal liquidation strategy
* Historical version references

It is not an operational packet.

---

# 10. Non-Goals (v1)

* No embedded audio inside PDF
* No remote hosting links
* No cloud export
* No electronic signature workflow
* No auto-email sending
* No pricing negotiation tools

---

# 11. Architectural Components (Reusable)

This packet relies on shared export infrastructure:

* PacketComposer
* ValueBlock (Range mode)
* ItemCard component
* SetSummaryCard component
* AssetCollector
* BundleAssembler
* ShareSheet presenter

No packet-specific rendering engine.

---

# 12. Implementation Readiness Check

Before coding begins, confirm:

* Audio summaries exist as stored item metadata
* Owner Profile fields exist or are stubbed
* Range rollup function available for:

  * Item
  * Set
  * LiquidationTarget (aggregate)

---

# 13. Future Compatibility

This structure directly supports:

* Beneficiary Packet (different tone, different value policy)
* Consideration Packet (discussion-focused)
* Executor Master Packet (full estate view)
* Disposition Execution Packet (checklist-enabled)

No structural rewrite required.

---

## Status

Outreach Packet v1 is now fully specified.

---

