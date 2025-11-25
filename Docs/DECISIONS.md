# Legacy Treasure Chest - Architecture Decision Records (ADR)

**Last Updated:** 2025-01-14  
**Status:** ACTIVE  
**Version:** 1.0.0

## Overview

This document tracks key architectural and technical decisions made during development. Each entry follows the ADR format: Context, Decision, Rationale, Alternatives Considered, Consequences.

---

## ADR-001: iOS 18+ Target Platform

**Date:** 2025-01-14  
**Status:** COMMITTED  
**Category:** Platform

### Context
Starting fresh after 10-month hiatus. Need to choose minimum iOS version for target audience (Boomers).

### Decision
Target iOS 18.0+ exclusively. No backward compatibility with iOS 17 or earlier.

### Rationale
- Apple Intelligence requires iOS 18+
- Target demographic typically has newer iPhones
- Eliminates complexity of feature detection and fallbacks
- SwiftData + CloudKit integration is mature in iOS 18
- By launch (5+ weeks), iOS 18 adoption will be 65-70%

### Alternatives Considered
- **iOS 17+**: Would reach 15% more users but lose Apple Intelligence
- **iOS 16+**: Maximum reach but would require Core Data instead of SwiftData

### Consequences
✅ Can use latest Apple Intelligence features  
✅ Simpler codebase (no version checks)  
✅ Better performance (latest APIs)  
❌ Excludes iPhone XR, XS, 11 users  
❌ Smaller initial market

---

## ADR-002: SwiftData over Core Data

**Date:** 2025-01-14  
**Status:** COMMITTED  
**Category:** Data Persistence

### Context
Need persistent local storage for items, audio, beneficiaries. Core Data is mature but complex. SwiftData is new but modern.

### Decision
Use SwiftData exclusively for local persistence.

### Rationale
- Modern Swift syntax with @Model macro
- Better CloudKit integration
- Simpler relationship management
- Less boilerplate code
- Apple's recommended approach for new projects

### Alternatives Considered
- **Core Data**: More mature, but more complex
- **Realm**: Third-party dependency, less iOS-native
- **Custom SQLite**: Unnecessary complexity

### Consequences
✅ Cleaner, more maintainable code  
✅ Built-in CloudKit sync support  
✅ Faster development  
❌ Less mature than Core Data  
❌ Requires iOS 17+ (acceptable since we target iOS 18+)

---

## ADR-003: File System Storage for Media

**Date:** 2025-01-14  
**Status:** COMMITTED  
**Category:** Data Architecture

### Context
Need to store images (potentially hundreds), audio recordings, and documents. SwiftData can store binary data but isn't optimized for large files.

### Decision
Store media files on file system (Application Support directory). Store only file paths in SwiftData.

### Rationale
- Better performance (smaller database)
- Faster queries (metadata only)
- Easier backup/restore
- Standard iOS pattern
- CloudKit can handle file assets separately

### Alternatives Considered
- **Store in SwiftData**: Would bloat database, slow queries
- **Store in CloudKit only**: No offline access
- **Hybrid (thumbnails in DB)**: Added complexity

### Consequences
✅ Smaller database size  
✅ Faster queries  
✅ Easier media management  
❌ Need to manage orphan file cleanup  
❌ Two-step delete process (DB + file)

---

## ADR-004: Apple Intelligence First, Gemini Optional

**Date:** 2025-01-14  
**Status:** COMMITTED  
**Category:** AI Strategy

### Context
Need AI for transcription, descriptions, and marketplace features. Multiple options available.

### Decision
Primary: Apple Intelligence (on-device)  
Secondary: Gemini 2.0 Flash (cloud, feature-flagged)

### Rationale
- **Privacy**: On-device AI doesn't send data to cloud
- **Cost**: Apple Intelligence is free
- **Latency**: On-device is instant
- **Gemini**: 30x cheaper than Claude, better image recognition
- **User Control**: Feature flags let users opt-in to cloud AI

### Alternatives Considered
- **Claude only**: Better writing but 30x more expensive
- **OpenAI GPT-4**: More expensive, API rate limits
- **Gemini only**: No on-device option

### Consequences
✅ Privacy-first architecture  
✅ Low/no AI costs for primary features  
✅ User control over cloud data  
❌ Some features require device with Apple Intelligence  
❌ Need to maintain two AI code paths

---

## ADR-005: Sign in with Apple Exclusive

**Date:** 2025-01-14  
**Status:** COMMITTED  
**Category:** Authentication

### Context
Need user authentication for data ownership and future sync.

### Decision
Use Sign in with Apple exclusively. No email/password, no other providers.

### Rationale
- Eliminates password management complexity
- Better security (Passkeys support)
- Required by Apple for social login apps
- Target audience already has Apple ID
- Seamless UX for iPhone users

### Alternatives Considered
- **Email/password**: Security burden, forgot password flows
- **Multiple providers**: Added complexity, more dependencies
- **No auth**: Can't enable sync or sharing features

### Consequences
✅ Simple, secure authentication  
✅ No password storage  
✅ Passkeys future enhancement  
❌ iOS/macOS only (acceptable for iOS-only app)  
❌ Requires Apple Developer account

---

## ADR-006: Test User for Development

**Date:** 2025-01-14  
**Status:** TEMPORARY  
**Category:** Development

### Context
Sign in with Apple requires physical device and full Apple ID. Simulator testing is limited.

### Decision
Implement createTestUser() method for Simulator development. Keep alongside real Sign in with Apple.

### Rationale
- Faster iteration in Simulator
- No need to sign in/out repeatedly during development
- Can test with consistent data
- Easy to remove for production

### Alternatives Considered
- **Simulator only**: Would block development
- **Mock authentication**: More complex, less realistic
- **Always require device**: Slows development

### Consequences
✅ Faster Simulator development  
✅ Consistent test data  
❌ Must remember to test real auth on device  
❌ Extra code to maintain (can remove at launch)

---

## ADR-007: Local-First, CloudKit Later

**Date:** 2025-01-14  
**Status:** COMMITTED  
**Category:** Sync Strategy

### Context
Users need multi-device sync (husband + wife scenario). CloudKit adds complexity.

### Decision
Build fully functional local-first app (Weeks 1-4). Add CloudKit sync in Week 5.

### Rationale
- Validate core features without sync complexity
- Easier debugging (one device, one data store)
- Learn SwiftData patterns first
- CloudKit is additive (doesn't require refactoring)

### Alternatives Considered
- **CloudKit from day 1**: Too much complexity early
- **No sync ever**: Doesn't meet user needs
- **Third-party sync**: Additional dependency, cost

### Consequences
✅ Faster initial development  
✅ Core features validated first  
✅ Simpler debugging  
❌ Users can't sync until Week 5  
❌ Need to test sync carefully when added

---

## ADR-008: Feature Flags for Optional AI

**Date:** 2025-01-14  
**Status:** COMMITTED  
**Category:** Configuration

### Context
Not all users will want cloud AI features. Some may prefer privacy. Need ability to toggle features.

### Decision
Use @AppStorage-backed FeatureFlags for runtime toggles:
- enableMarketAI (default: OFF)
- enableCloudKit (default: OFF until Phase 1E)
- enableHouseholds (default: OFF until Phase 2)

### Rationale
- User control over privacy
- Easy A/B testing
- Can disable features if APIs fail
- Simple implementation with @AppStorage

### Alternatives Considered
- **Build-time flags**: Less flexible
- **Remote config**: Added complexity, dependency
- **No flags**: All or nothing, bad UX

### Consequences
✅ User privacy control  
✅ Easy testing/debugging  
✅ Can disable broken features quickly  
❌ Need to test all flag combinations

---

## ADR-009: Gemini 2.0 Flash over Claude

**Date:** 2025-01-14  
**Status:** COMMITTED  
**Category:** AI Provider

### Context
Need cloud AI for marketplace features. Multiple LLM providers available.

### Decision
Use Gemini 2.0 Flash for MarketAI features.

### Rationale
- **Cost**: $0.10/1M tokens vs Claude's $3/1M (30x cheaper)
- **Image recognition**: Superior to alternatives
- **Context window**: 1M tokens vs Claude's 200K
- **Quality**: Good enough for marketplace content
- **Free tier**: 15 req/min during development

### Alternatives Considered
- **Claude 3.5 Sonnet**: Better creative writing, but 30x cost
- **OpenAI GPT-4**: Middle ground, but more expensive than Gemini

### Consequences
✅ Extremely low API costs  
✅ Excellent image analysis  
✅ Large context for complex items  
❌ Slightly less creative writing than Claude  
❌ Need to manage API key securely

---

## ADR-010: Households Deferred to Phase 2

**Date:** 2025-01-14  
**Status:** COMMITTED  
**Category:** Scope

### Context
Household sharing is important for couples, but adds complexity (roles, permissions, conflicts).

### Decision
Defer household features to Phase 2 (Weeks 6-8). MVP is single-user with CloudKit personal sync.

### Rationale
- Reduces MVP complexity
- Allows validation of core features first
- CloudKit sharing is complex and needs dedicated time
- Single-user with multi-device sync serves initial use case

### Alternatives Considered
- **Build households from start**: Too much complexity for MVP
- **Never add households**: Doesn't serve couples use case

### Consequences
✅ Simpler MVP  
✅ Faster time to initial launch  
❌ Couples can't share inventory in v1  
❌ Need to design household architecture carefully to add later

---

## Template for New ADRs
```markdown
## ADR-XXX: [Title]

**Date:** YYYY-MM-DD  
**Status:** [PROPOSED | ACCEPTED | COMMITTED | DEPRECATED]  
**Category:** [Platform | Architecture | Implementation | Process]

### Context
[What is the issue/situation/problem?]

### Decision
[What are we doing?]

### Rationale
[Why this decision?]

### Alternatives Considered
- **Option A**: [Why not chosen]
- **Option B**: [Why not chosen]

### Consequences
✅ [Positive consequence]  
❌ [Negative consequence/trade-off]
```

---

## Change Log

- **2025-01-14:** Initial ADR document with 10 foundational decisions