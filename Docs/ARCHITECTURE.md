# Legacy Treasure Chest - Architecture

**Last Updated:** 2025-01-14  
**Status:** ACTIVE  
**Version:** 1.0.0 (Phase 1A)  
**Target:** iOS 18.0+

## Overview

Legacy Treasure Chest is an iOS 18+ application that helps users catalog valuable possessions, record family stories through audio, and designate beneficiaries for legacy planning.

**One-sentence summary:** A privacy-first iOS app using SwiftData and Apple Intelligence to help Boomers preserve family legacies through cataloged items with audio storytelling.

---

## Technology Stack

### Platform
- **iOS:** 18.0+ (Apple Intelligence required)
- **Language:** Swift 6 (strict concurrency)
- **UI Framework:** SwiftUI
- **Architecture Pattern:** MVVM with service layer

### Data & Persistence
- **Local Storage:** SwiftData (primary)
- **Media Storage:** File system (Application Support)
- **Cloud Sync:** CloudKit (Phase 1B, Week 5)
- **File Strategy:** Store metadata in SwiftData, large media as files

### AI Integration
- **On-Device (Primary):** Apple Intelligence
  - Description enhancement (Writing Tools)
  - Audio transcription (Speech)
  - Image understanding (Vision)
- **Cloud (Optional):** Gemini 2.0 Flash
  - Marketplace listing generation
  - Market research and pricing
  - Feature flag controlled (OFF by default)

### Authentication
- **Sign in with Apple** (exclusive)
- No passwords stored
- Keychain for sensitive data

---

## Architecture Diagram
```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI Views                     │
│  (Authentication, Item Detail, Audio Recording, etc) │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────┐
│                   ViewModels                         │
│          (@Observable, business logic)               │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────┐
│                  Service Layer                       │
│  ┌──────────────────────────────────────────────┐   │
│  │ AuthService │ ItemService │ AudioService     │   │
│  │ AIService   │ MarketAI    │ Transcription   │   │
│  └──────────────────────────────────────────────┘   │
└────────────────┬────────────────────────────────────┘
                 │
         ┌───────┴───────┐
         ▼               ▼
┌─────────────────┐ ┌──────────────────┐
│   SwiftData     │ │  File System     │
│  (metadata,     │ │  (images, audio, │
│  relationships) │ │   documents)     │
└─────────────────┘ └──────────────────┘
         │
         ▼
┌─────────────────┐
│   CloudKit      │
│  (Phase 1B+)    │
└─────────────────┘
```

---

## Module Structure

### App Layer
- **LegacyTreasureChestApp.swift:** App entry point, DI setup
- **DependencyContainer.swift:** Service injection and configuration

### Core Layer
- **Protocols/:** Service interfaces (ServiceRegistry, FeatureFlags)
- **Utilities/:** Helpers (AppError, AIAvailability)
- **Extensions/:** Swift/Foundation extensions

### Data Layer
- **SwiftData/:** Models and ModelContainer setup
- **Storage/:** Media file management (MediaStorage, MediaCleaner)

### Features Layer
- **Authentication/:** Sign in with Apple flow
- **Items/:** Item cataloging and management (Phase 1B)
- **Audio/:** Recording and transcription
- **Beneficiaries/:** Legacy designation (Phase 1B)

### UI Layer
- **Components/:** Reusable UI elements
- **Resources/:** Assets, colors, localization

---

## Data Flow Examples

### Creating an Item with Audio
```
1. User taps "Record Story"
2. RecordAudioView → RecordAudioViewModel
3. ViewModel calls AudioService.startRecording()
4. AudioService saves to MediaStorage
5. On stop: TranscriptionService.transcribe()
6. ViewModel creates AudioRecording entity
7. SwiftData persists metadata (file path)
8. CloudKit syncs (if enabled)
```

### Sign in with Apple
```
1. User taps "Sign in with Apple"
2. AuthenticationView → AuthenticationViewModel
3. ViewModel calls AuthService.signInWithApple()
4. Apple ID credential received
5. LTCUser entity created/fetched
6. SwiftData persists user
7. DependencyContainer sets currentUserId
8. Navigate to HomeView
```

---

## Key Design Decisions

### 1. SwiftData over Core Data
**Rationale:** Modern API, simpler syntax, better CloudKit integration  
**Trade-off:** Requires iOS 17+, less mature than Core Data  
**Decision:** Acceptable since we target iOS 18+ only

### 2. File System for Media
**Rationale:** SwiftData handles relationships, file system handles large files  
**Benefits:** Better performance, easier backup, smaller database  
**Implementation:** Store relative paths in SwiftData entities

### 3. Apple Intelligence First
**Rationale:** On-device = privacy, no API costs, better latency  
**Trade-off:** Limited to newer devices  
**Decision:** Acceptable since target audience typically has newer iPhones

### 4. Optional Gemini MarketAI
**Rationale:** Superior image recognition, 30x cheaper than alternatives  
**Implementation:** Behind feature flag, OFF by default, user opt-in required  
**Privacy:** Send only structured data, never raw media

### 5. Sign in with Apple Only
**Rationale:** Eliminates password management, better UX, Apple ecosystem integration  
**Trade-off:** Apple-only (acceptable for iOS-only app)  
**Security:** Uses Keychain, supports Passkeys future enhancement

---

## Performance Considerations

### Optimizations
- Lazy loading of images/audio
- Background transcription
- Optimistic UI updates
- Image compression (80% JPEG quality)
- Audio format: AAC-LC (efficient)

### Limits (to be tuned)
- Max image size: TBD
- Max audio duration: TBD
- Media cleanup: On app launch + manual Settings option

---

## Security & Privacy

### Data Protection
- All data encrypted at rest (iOS default)
- Keychain for sensitive tokens
- No passwords stored in app
- Apple Intelligence processes on-device

### User Controls
- "Use Cloud AI" toggle (Settings)
- Export My Data
- Delete My Data
- Clear explanation of data usage

### Cloud Data
- MarketAI: Only send item attributes, not raw media
- CloudKit: End-to-end encrypted (when enabled)
- No third-party analytics

---

## Testing Strategy

### Phase 1A (Current)
- Build verification
- Basic navigation
- SwiftData persistence

### Phase 1B (Week 3-5)
- Audio recording/playback
- Transcription accuracy
- Multi-device sync
- Conflict resolution

### Phase 2 (Weeks 6+)
- Household collaboration
- Two-device concurrent edits
- Permission enforcement

---

## Future Enhancements (Post-MVP)

1. **Video recordings** (similar to audio)
2. **Marketplace integrations** (eBay, Craigslist APIs)
3. **Estate planning export** (PDF reports)
4. **Siri Shortcuts** ("Add item from photo")
5. **Apple Watch** companion app
6. **iPad** optimized layouts

---

## Related Documents

- [DATA-MODEL.md](DATA-MODEL.md) - SwiftData entity definitions
- [SERVICES.md](SERVICES.md) - Service layer protocols
- [AI-LAYER.md](AI-LAYER.md) - AI integration details
- [MVP-SCOPE.md](MVP-SCOPE.md) - Development timeline

---

## Change Log

- **2025-01-14:** Initial architecture document (Phase 1A)
  - Foundation code complete
  - SwiftData models defined
  - Media storage configured
  - Feature flags implemented