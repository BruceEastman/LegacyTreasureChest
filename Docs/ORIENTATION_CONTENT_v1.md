# Legacy Treasure Chest

# Orientation Content v1

**Purpose:**
Provide users with a clear mental model of the Legacy Treasure Chest system and its capabilities.

The orientation content explains:

* what the system does
* how the process works
* what outcomes users can expect

It is **not a tutorial**.
It is a **capability overview and conceptual guide**.

---

# Core Concept

Legacy Treasure Chest helps users work through the physical estate using a simple journey.

```
Capture → Understand → Decide → Execute → Document
```

During this journey the system helps answer four questions:

* What do we have?
* What is it worth?
* What should happen to it?
* What does the executor need?

This conceptual model forms the foundation of the onboarding experience.

---

# Orientation Architecture

Orientation consists of two components.

## 1. Start Here (First Launch)

Shown when the app launches for the first time.

Purpose:

* introduce the mental model
* explain the four questions
* show the estate journey

This screen sequence is **skippable** and **always accessible later** in the How It Works section.

---

## 2. How It Works (Permanent Orientation Library)

Accessible from the Help section of the app.

Structure:

```
How It Works
   Start Here
   The Estate Journey
   Building Your Inventory
   Legacy & Beneficiaries
   Selling & Liquidating
   Estate Reports
   Privacy
```

Each section is designed to be **read in under 45 seconds**.

---

# Start Here (First Launch)

## Screen 1 — The Situation

**Heading**
What happens to everything in your home?

**Body**

Most households accumulate a lifetime of possessions — furniture, collections, jewelry, tools, clothing, and thousands of everyday items.

When the time comes to downsize or settle an estate, families are often left guessing:

* what exists
* what items are worth
* who should receive them
* how they should be sold

Legacy Treasure Chest brings structure and clarity to the physical estate.

---

## Screen 2 — Four Questions

**Heading**
Four questions we help you answer.

**Body**

**What do we have?**
Capture possessions using photos and simple notes.

**What is it worth?**
Receive advisory resale value ranges based on real-world markets.

**What should happen to it?**
Choose whether items stay in the family or are sold.

**What does the executor need?**
Generate clear reports for family members, executors, and professionals.

---

## Screen 3 — The Journey

**Heading**
From Inventory to Action

**Body**

Legacy Treasure Chest guides you through a simple process:

```
Capture → Understand → Decide → Execute → Document
```

Everything remains privately stored on your device.

The system acts as an **advisor**, not an operator.

---

# How It Works Library

---

# The Estate Journey

Legacy Treasure Chest helps you move through a clear process for understanding and planning the future of your possessions.

### Capture

Photograph and record items in your household.

### Understand

AI helps identify items and provides resale-oriented value ranges.

### Decide

Choose whether items are:

* kept in the estate
* given to beneficiaries
* liquidated or donated

### Execute

Follow practical checklists to carry out liquidation plans or organize distributions.

### Document

Generate clear reports that make the estate easier for others to understand and manage.

---

# Building Your Inventory

The inventory is the foundation of the system.

Start by photographing items and adding brief descriptions.

The system can help suggest categories and estimated resale ranges.

Items can be organized into groups such as:

* collections
* room groupings
* sets of related objects

You can also attach:

* documents such as receipts or appraisals
* additional photos
* **audio recordings explaining the history or meaning of an item**

These details help preserve context that may otherwise be lost.

---

# Legacy & Beneficiaries

Some possessions belong with specific people.

Legacy Treasure Chest allows you to assign beneficiaries to items or collections so that your intentions are clearly recorded.

You can include notes or **record audio messages in your own voice** describing the story or significance of the item.

This helps turn a simple inventory into meaningful guidance for the next generation.

---

# Selling & Liquidating

If you decide to sell an item, Legacy Treasure Chest helps determine the most practical way to do it.

For many items, the best approach is simply to **sell the item yourself locally or online**.

The system can help you organize the steps required to complete the sale.

For higher-value or specialized items, other strategies may be more appropriate, including:

* dealers or consignment shops
* auction houses
* estate sale groupings

Once you choose a strategy, the system generates a checklist to help you carry it out.

If you prefer professional assistance, the app can also help identify local businesses to contact.

---

# Estate Reports

As your inventory grows and decisions are made, the system can generate organized documentation describing the physical estate.

These reports help others understand the estate clearly and may include:

* estate summaries
* detailed inventories
* beneficiary reports
* outreach packets for dealers or auction houses
* executor documentation

These exports help reduce confusion when the estate must eventually be settled.

---

# Privacy

Legacy Treasure Chest is designed as a **private advisory system**.

Your inventory remains stored on your device.

The application does not operate as a marketplace and does not manage transactions.

When AI assistance is used, only the information required for that request is sent for analysis according to the provider’s data handling policies.

The goal is to help you organize and understand your household possessions while keeping control of your information.

---

# Implementation Notes

Start Here

```
StartHereView
```

Persistent library

```
HowItWorksView
```

Page model

```
OrientationPage
```

First launch tracking

```
@AppStorage("hasSeenStartHere")
```

---

# Next Step

Now that the orientation content is locked:

**Next step:**

Load the current file:

```
HelpView.swift
```

Then we will implement:

* `StartHereView`
* `HowItWorksView`
* Orientation page model
* First-launch presentation logic

All integrated into your existing Help system.
