** First list:
- onboarding abrupt transition
- luxury handbag routing logic
- AI latency tuning
- Google Places update
- Google models update promoting 3.1 flash

My recommendation:

* use a **standard master bootstrap prompt** in every new debugging/build conversation
* include the **specific issue block** for that conversation
* only attach/paste the latest README when the issue is:

  * cross-cutting
  * tied to recent changes
  * likely affected by release/testflight/cloud/config work
  * or when you want me to update project status/documentation at the end

Why I would not load README every time:

* it consumes context unnecessarily for narrow bug fixes
* many issues only need 1–3 files plus the symptom description
* too much background can dilute the shortest-path diagnostic work

Why README is still valuable:

* it is your best project history / status source
* it is very useful at the start of a new major phase
* it is useful when a bug may be related to recent feature-flag, release, AI, or architecture changes
* it is useful when you want continuity on what has already been fixed

So the practical rule I would use is:

* **narrow UI bug**: use master bootstrap prompt only, no README unless needed
* **workflow bug / regression / release issue / architecture-sensitive issue**: use master bootstrap prompt + relevant README excerpt or latest README
* **planning or status conversation**: include README

Here is a stronger reusable bootstrap prompt you can keep and use for new LTC conversations.

```md
Bootstrap Prompt — Legacy Treasure Chest Debug / Build Session

Project
I am working on Legacy Treasure Chest (LTC), an AI-native iPhone app for physical estate planning, inventory, valuation, beneficiary assignment, and liquidation guidance. The app is being built for real-world use, not as a throwaway MVP. I am the primary and currently only user, on my local iPhone and on my wife's iPhone through TestFlight releases. I am testing it thoroughly before broader external rollout. For quick testing, I build locally on my iPhone before building for TestFlight users. 

Primary architecture
- Front end: Swift / SwiftUI
- Local persistence: SwiftData
- Backend AI gateway: FastAPI
- AI usage: backend-first for key AI flows
- Current work often involves local builds, Release-style testing, and TestFlight validation

Product philosophy
- AI-native app where AI provides the main value
- Advisor, not operator
- Practical, production-quality behavior over shortcuts
- Conservative, trustworthy UX for real household / estate use

How we work
Please follow this working style:
- Keep responses short, practical, and diagnostic
- Work step-by-step
- Inspect existing code before proposing changes
- Ask for the smallest relevant snippets first
- For large files, request only anchored sections
- Do not redesign architecture unless clearly necessary
- Prefer the shortest path to identifying the real cause
- When code changes are needed:
  - for small files, provide the complete updated file
  - for large files, provide a minimal diff with clear anchors
- Keep compile-safe, incremental changes
- Assume I am technically knowledgeable, but not a hands-on programmer
- Help me avoid false paths and unnecessary work

Project continuity
README is my main running project history / source of truth for status and recent changes. Use it when relevant, especially for regressions, release issues, recent feature changes, or cross-cutting fixes.

Current conversation goal
I need help with one specific issue.

Problem
[describe exact observed behavior]

Expected behavior
[describe what should happen]

Where it occurs
[screen / flow / item vs set / local build vs Release vs TestFlight]

What has already been confirmed
- [fact 1]
- [fact 2]
- [fact 3]

Most likely files
- [file 1]
- [file 2]
- [file 3]

What I want you to do first
Start with the minimum code inspection needed to identify the cause. Tell me the exact anchored snippets to paste first.
```

And here is the lighter version for smaller UI bugs where you do not want extra context overhead:

```md
Bootstrap Prompt — LTC Focused Debug Session

I need to debug one specific issue in Legacy Treasure Chest.

Working style
- Keep responses short and diagnostic
- Work step-by-step
- Inspect existing code first
- Ask for the smallest relevant snippets
- For large files, request anchored sections only
- Do not redesign architecture unless necessary

Problem
[exact observed behavior]

Expected behavior
[expected result]

Where it occurs
[screen / flow / local build / TestFlight]

Most likely files
- [file 1]
- [file 2]

Start with the minimum code inspection needed and tell me the exact anchored snippets to paste first.
```

My recommendation is to save both:

* a **full bootstrap** for serious debugging / release / regression conversations
* a **light bootstrap** for single-screen UI issues

For your current stage of work, that will likely give you the best balance of continuity and speed.

For the README question, my practical answer is:
**use it selectively, not automatically in every conversation.**

A good compromise is to include one line in your bootstrap such as:

> “README is the running source of truth; I can paste relevant sections if needed.”

That keeps the context available without paying the token cost every time.
