# Legacy Treasure Chest - Project Overview

**Legacy Treasure Chest** is an iOS 18+ app that helps users catalog valuable possessions, record family stories through audio, and designate items for beneficiaries. The app leverages Apple Intelligence for on-device AI and optional Gemini cloud AI for marketplace features, providing a privacy-first approach to legacy planning.

## Core Vision

Empower users (primarily Boomers) to:
- Catalog treasured possessions with photos and audio stories
- Preserve family history and context through voice recordings
- Designate items to beneficiaries with personalized messages
- Optionally list items for sale with AI-generated marketplace content

## Technical Foundation

**Platform:**
- iOS 18.0+ (Apple Intelligence required)
- Swift 6 (strict concurrency)
- SwiftUI
- Architecture: MVVM with service layer

**Data & Storage:**
- SwiftData (local persistence)
- CloudKit (multi-device sync - Phase 1E)
- File system (media storage)
- Sign in with Apple (authentication)

**AI Integration:**
- **Apple Intelligence** (on-device, primary): Audio transcription, writing enhancement
- **Gemini 2.0 Flash** (cloud, optional): Image analysis, marketplace listings
- Privacy-first: User controls via feature flags

## Core Modules

### 1. **Authentication Module** ✅ COMPLETE
Handles Sign in with Apple authentication and user session management.
- Real Apple ID integration
- No password storage
- Biometric support
- Session persistence

### 2. **Audio Storytelling Module** ✅ COMPLETE
Records audio memories with automatic transcription.
- Audio recording (AVFoundation)
- On-device transcription (Apple Intelligence)
- Playback capabilities
- Links to items

### 3. **Item Cataloging Module** 📅 PHASE 1C
Manages physical item inventory with photos and details.
- Photo capture (PhotosPicker)
- AI image analysis (Gemini, optional)
- Item metadata (name, category, description, value)
- Document attachments
- Audio recording links

### 4. **Beneficiary Management Module** 📅 PHASE 1D
Designates items to beneficiaries with access controls.
- Beneficiary creation (manual + Contacts import)
- Item assignments
- Access permissions (immediate, scheduled, conditional)
- Personal messages

### 5. **CloudKit Sync Module** 📅 PHASE 1E
Enables multi-device synchronization.
- Automatic iCloud sync
- Conflict resolution (last-writer-wins)
- Multi-device support (iPhone, iPad, Mac)
- Encrypted storage

### 6. **Household Sharing Module** 🔄 PHASE 2
Collaborative inventory management (future).
- Household creation
- Member invitations
- Role-based permissions (Admin, Contributor)
- Activity logs

### 7. **Marketplace Integration Module** 🔄 PHASE 3
AI-powered listing generation and marketplace connections (future).
- Gemini-powered listing optimization
- eBay/Craigslist integration
- Pricing recommendations
- Listing management

### 8. **Media Storage Module** ✅ COMPLETE
Centralized file management for images, audio, and documents.
- File system storage (Application Support)
- Relative path references in SwiftData
- Orphan file cleanup
- Automatic directory creation

### 9. **Settings Module** 🔄 PHASE 2
User preferences and privacy controls.
- Feature flags (MarketAI, CloudKit, Households)
- Privacy settings
- Export/delete data
- Debug mode

## Key Features

### ✅ Implemented (Phase 1A-1B)
- Sign in with Apple authentication
- Audio recording with Apple Intelligence transcription
- SwiftData local persistence
- Media file management
- Feature flag system
- Secure API configuration (Gemini)

### 📅 In Progress (Phase 1C-1E)
- Photo-based item cataloging
- AI image analysis (Gemini)
- Beneficiary designation
- CloudKit multi-device sync

### 🔄 Planned (Phase 2+)
- Household collaboration
- Marketplace integrations
- Estate planning exports (PDF)
- Siri Shortcuts
- iPad optimization

## Key Technologies

**Apple Frameworks:**
- SwiftUI (UI framework)
- SwiftData (persistence)
- CloudKit (sync)
- AVFoundation (audio)
- Speech (transcription)
- PhotosUI (photo capture)
- AuthenticationServices (Sign in with Apple)

**Third-Party APIs:**
- Gemini 2.0 Flash (Google AI)
- eBay API (future)
- Craigslist integration (future)

**Development:**
- Xcode 16.1+
- macOS Tahoe 15.2.1
- Swift 6.0
- iOS 18.0+ deployment target

## Architecture Principles

1. **Privacy First**: On-device AI by default, optional cloud features
2. **User Control**: Feature flags for all cloud services
3. **Local First**: Full functionality without internet
4. **Service Layer**: Protocol-oriented design for testability
5. **MVVM Pattern**: Clear separation of concerns
6. **File-Based Media**: SwiftData for metadata, file system for binary data

## Development Status

**Current Phase:** 1B Complete (Foundation + Device Setup)  
**Next Phase:** 1C (Item Cataloging)  
**Target MVP:** 5 weeks (Phases 1A-1E)  
**Progress:** 40% complete

## Project Structure
```
LegacyTreasureChest/
├── App/                        # App entry + DI
├── Core/                       # Protocols + Utilities
│   ├── Protocols/              # Service interfaces
│   ├── Utilities/              # Helpers
│   └── Extensions/             # Swift extensions
├── Data/                       # Persistence layer
│   ├── SwiftData/              # Models + container
│   └── Storage/                # Media management
├── Features/                   # Feature modules
│   ├── Authentication/         # Sign in
│   ├── Audio/                  # Recording
│   ├── Items/                  # Cataloging (Phase 1C)
│   └── Beneficiaries/          # Designation (Phase 1D)
└── UI/                         # Shared UI
    ├── Components/             # Reusable views
    └── Resources/              # Assets
```

## Documentation

Complete documentation available in `/docs`:
- ARCHITECTURE.md - System design
- DATA-MODEL.md - SwiftData entities
- SERVICES.md - Service layer
- AI-LAYER.md - AI integration strategy
- MVP-SCOPE.md - Development timeline
- DECISIONS.md - Architecture decisions
- SECURITY.md - Privacy & security
- FEATURE-FLAGS.md - Feature toggles
- TESTING.md - Test strategy
- NAMING.md - Code conventions
- GLOSSARY.md - Domain terminology
- ENVIRONMENT.md - Setup guide

## Target Audience

**Primary:** Boomers (60+) managing estate items  
**Secondary:** Adult children helping parents  
**Use Cases:**
- Estate planning and inventory
- Family legacy preservation
- Item distribution planning
- Downsizing assistance
- Memory capture

## Competitive Advantages

1. **Audio Storytelling**: Unique focus on voice recordings with transcription
2. **Privacy**: On-device AI, no cloud required for core features
3. **Simplicity**: Boomer-friendly UX with large buttons, clear navigation
4. **Apple Ecosystem**: Native iOS, iCloud sync, Apple Intelligence
5. **Flexibility**: Works for legacy planning AND selling items

## Future Roadmap

**Post-MVP Enhancements:**
- Video recordings
- Apple Watch companion
- Widget support
- Siri integration
- Estate planning PDF exports
- Professional appraisal integration
- Expanded marketplace support
- Multi-language support

## Contact & Resources

- **Project Location:** `~/Documents/Legacy_Treasure_Chest/`
- **Bundle ID:** `com.bruceeastman.legacytreasurechest`
- **Organization:** Eastmancro LLC
- **Developer:** Bruce Eastman
- **Target Launch:** Q2 2025 (MVP)

---

**Last Updated:** 2025-01-14  
**Version:** 1.0.0 (Phase 1B Complete)  
**Status:** Active Development