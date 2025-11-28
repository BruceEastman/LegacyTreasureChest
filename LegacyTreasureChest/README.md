# Legacy Treasure Chest
## Beneficiaries Module (Item-Level Assignment)

**Status:** Implemented and working in the iOS app.

The Beneficiaries module allows an LTCUser to define people who will receive specific items and to configure when and how those people gain access.

### Data Model

- `LTCUser`
  - Owns `beneficiaries: [Beneficiary]`
- `Beneficiary`
  - Core fields: `name`, `relationship`, optional `email`, optional `phoneNumber`
  - Optional contact linkage via `contactIdentifier` and `isLinkedToContact`
  - Back-link to item links via `itemLinks: [ItemBeneficiary]`
- `LTCItem`
  - Owns `itemBeneficiaries: [ItemBeneficiary]`
- `ItemBeneficiary` (junction model)
  - Links `LTCItem` ↔ `Beneficiary`
  - Stores:
    - `accessPermission: AccessPermission`  
      - `.immediate`, `.afterSpecificDate`, `.uponPassing`
    - Optional `accessDate`
    - Optional `personalMessage`
    - `notificationStatus: NotificationStatus`
      - `.notSent`, `.sent`, `.accepted`

This keeps Beneficiary as the canonical LTC record, with ItemBeneficiary holding per-item rules.

### UI / UX

All UI is Theme-driven (`Theme.swift`) and integrated into `ItemDetailView`:

- **ItemDetailView**
  - Hosts the Beneficiaries section alongside Photos, Documents, and Audio.
  - Owns presentation for:
    - Beneficiary picker/creator sheet
    - Beneficiary link editor sheet
  - Supports:
    - Add Beneficiary to item
    - Edit link (access rules + message)
    - Remove link (swipe-to-delete)

- **ItemBeneficiariesSection**
  - Shows an empty state when there are no linked beneficiaries:
    - Explanation of purpose
    - Themed “Add Beneficiary” button
  - When links exist:
    - Card-style list of beneficiaries
    - Displays:
      - Beneficiary name and relationship
      - Access permission summary (Immediate / After date / Upon passing)
      - Notification status badge
    - Tapping a row opens the editor; swipe-to-delete removes the link.

- **BeneficiaryPickerSheet**
  - Presented from `ItemDetailView` on “Add Beneficiary”.
  - Shows:
    - Existing beneficiaries for the current `LTCUser`
    - A form to create a new beneficiary (name, relationship, optional email/phone)
  - Selecting or creating a beneficiary:
    - Creates a new `ItemBeneficiary` with default `.immediate` access
    - Attaches it to the current item
    - Associates new Beneficiaries with the user so they are available for other items

- **ItemBeneficiaryEditSheet**
  - Allows editing an existing `ItemBeneficiary` link:
    - Picker for `accessPermission`
    - Date picker for `accessDate` when `.afterSpecificDate` is chosen
    - Card-style `TextEditor` for `personalMessage`
    - Read-only display of `notificationStatus`
  - Changes are saved back to the linked `ItemBeneficiary` when the user taps “Done”.

### Future Enhancements (Planned)

- Integrate with device Contacts:
  - Import a contact to create or link a `Beneficiary`
  - Populate `contactIdentifier` and `isLinkedToContact`
- Notification workflows:
  - Use `notificationStatus` to track outbound messages and acknowledgements
- Dedicated Beneficiaries management screen:
  - View and manage all Beneficiaries independent of items
- AI assistance:
  - Suggest likely beneficiaries for items
  - Draft personal messages based on item history and user preferences

# 📌 Milestone Update — Audio Stories Module Implemented (Nov 2025)

The **Audio Stories** module for Legacy Treasure Chest is now fully implemented and integrated into the Item Detail flow. This brings audio recording, playback, and management capabilities to each item in the catalog.

### ✔️ Completed in this milestone

- **Audio Recording**
  - Microphone permission request via `NSMicrophoneUsageDescription`
  - AVAudioRecorder-based recording with proper session configuration
  - Accurate duration capture before stopping the recorder
  - Audio files stored under `Media/Audio` using MediaStorage

- **Playback & Audio Management**
  - Inline play/pause with `AVAudioPlayer`
  - Single-playback enforcement (starting one stops another)
  - Stable handling of playback completion and session transitions
  - Clear user feedback and safe fallbacks

- **SwiftData Integration**
  - New `AudioRecording` model linked to each `LTCItem`
  - SwiftData persistence for file path, duration, timestamps
  - Automatic updatedAt propagation to parent item

- **UI/UX Implementation**
  - Fully themed with `Theme.swift` (colors, typography, spacing)
  - Integrated into ItemDetailView with correct section header styling
  - Empty-state messaging + “Record Story” CTA
  - List of audio stories with titles, timestamps, and durations
  - Playback icons and deletion controls consistent with Photos/Documents

- **Deletion Workflow**
  - SwiftData removal of `AudioRecording` objects
  - File cleanup via MediaStorage with soft-fail safety
  - Stopping playback when deleting the active recording

### 🔒 Architecture & Safety
All audio interactions follow the existing architectural patterns:
- Media files stored on disk, metadata stored in SwiftData
- AVAudioSession properly activated/deactivated
- Structured recording and playback lifecycle to avoid race conditions
- No global singletons — AudioManager is isolated per view instance

This completes full media support (Photos, Documents, Audio) for each item.
Next milestone: **Beneficiaries module implementation**.

## 📌 Update — Documents Module v1 Complete (2025-11-25)

This milestone completes the first working version of the **Documents Module** and brings the app to a solid baseline:

- App launches successfully with SwiftData `ModelContainer` and `ModelContext` initialized.
- Core models exist and compile: `LTCUser`, `LTCItem`, `ItemImage`, `AudioRecording`, `Document`, `Beneficiary`, `ItemBeneficiary`.
- Items persist correctly across launches.
- `MediaStorage` is implemented and working for:
  - Images under `Media/Images`
  - Audio under `Media/Audio`
  - Documents under `Media/Documents`
- `MediaCleaner` exists (not yet wired into the main flows).

### Authentication

- Sign in with Apple implemented and stable via:
  - `AuthenticationService`
  - `AuthenticationViewModel`
  - `AuthenticationView`
- Simulator sign-in override available.
- `HomeView` shows correctly after successful sign-in.

### Items Flow

- `ItemsListView` uses `@Query` sorted by `createdAt`.
- Search works on item `name` and `description`.
- **Add Item**
  - `AddItemView` is pushed via `NavigationLink`.
  - Fields: `name`, `description`, `category` (Picker), `value` (currency).
  - Saves a new `LTCItem` into SwiftData and returns to the list.
- **Item Detail**
  - `ItemDetailView` uses `@Bindable var item: LTCItem`.
  - Editing name/description/category/value auto-saves via SwiftData.
  - Returning to the list immediately reflects updates.
- **Delete**
  - Swipe-to-delete in `ItemsListView` removes items using SwiftData.

### Photos Module (Working)

- `ItemPhotosSection`:
  - Uses `PhotosPicker` to add one or more images.
  - Persists images via `MediaStorage.saveImage` under `Media/Images`.
  - `ItemImage` model is linked to `LTCItem.images`.
- Thumbnails:
  - Grid of square thumbnails with delete and context menu.
- Preview:
  - `ItemDetailView` owns a sheet with full-screen zoomable/pannable preview (`ZoomableImageView`).
- Deletion:
  - Removes `ItemImage` from SwiftData.
  - Attempts to delete underlying file via `MediaStorage.deleteFile`.
- Behavior is stable (no presentation/state warnings).

### Documents Module (Working v1)

- `ItemDocumentsSection`:
  - Uses `fileImporter` to attach PDFs and images from Files / iCloud Drive.
  - Persists documents via `MediaStorage.saveDocument` under `Media/Documents`.
  - `Document` model linked to `LTCItem.documents`.
  - Stores `documentType` (e.g., PDF, IMAGE, UTI) and `originalFilename`.
- Display:
  - List view with icon, filename, type, and size (e.g., `PDF · 322 KB`).
  - Shows a clean filename (original name, not UUID prefix).
- Preview:
  - `ItemDetailView` sheet:
    - Uses `ZoomableImageView` for image documents.
    - Uses QuickLook for PDFs/other types.
    - Includes **Done** and **Share** controls.
- Share:
  - Uses `UIActivityViewController` (via `ActivityView`) to share/open documents.
- Deletion:
  - Removes `Document` from SwiftData.
  - Attempts to delete underlying file via `MediaStorage.deleteFile`.
- File size guard:
  - Simple upper limit (e.g., 50 MB) with a user-facing error if exceeded.

### Other Sections (Placeholders)

- `ItemAudioSection` – placeholder for future audio stories.
- `ItemBeneficiariesSection` – placeholder for future beneficiary management.

---


Legacy Treasure Chest is an iOS app designed to help households organize, catalog, and document personal items, including photos, documents, audio notes, and beneficiary designations. It focuses on making downsizing, estate planning, and family communication easier for Boomers and their families.

## Features (in progress)
- Item catalog with photos, documents, and audio sections
- SwiftData-backed local storage
- Clean SwiftUI architecture
- Authentication (Sign in with Apple planned)
- Future: AI-assisted photo/document analysis
- Future: CloudKit sync and family sharing

## Project Structure
- `LegacyTreasureChest/` — SwiftUI code for app features
- `Docs/` — architectural notes and project documentation

## Technology
- Swift 6
- SwiftUI
- SwiftData
- Xcode 16+
- iOS 18+ target planned

