# Legacy Treasure Chest
✅ AI Valuation UX & Data Model Update (Dec 9 2025)
This update summarizes recent improvements to the AI Valuation workflow, including how users provide additional details, how valuations are stored, and how the system now explains why an item is valued the way it is.
1. Unified Expert Valuation Experience
We refined the AI Analysis workflow so that every item—regardless of category—receives the same high-quality valuation experience.
Category-specific logic (e.g., jewelry vs. rugs vs. artwork) is handled by the backend Expert model, while the frontend presents a consistent, easy-to-understand interface.
Key principles:
One valuation snapshot per item, stored in ItemValuation.
No valuation history for now (keeps UX clean and avoids data clutter).
Users can re-run analysis anytime to generate an updated expert view.
2. “More Details for AI Expert” (User Notes)
We introduced a persistent notes field that lets users supply details that significantly improve valuation accuracy—such as:
Jewelry: weight, purity, chain length, certification
Rugs: knots per square inch, origin, age
Art: medium, dimensions, signed/original
These notes are:
Saved on the item (valuation.userNotes)
Reused automatically every time AI analysis is run
Included directly in the backend prompt to influence the valuation
Users no longer need to retype these details—this behaves like a conversational memory for the item.
3. Clear, Human-Readable Item Description
When users apply an AI analysis:
The summary and key attributes (materials, maker, style, condition, features) are merged into the item’s saved description.
This ensures the item record itself tells the story:
“This item, with these characteristics, is why the valuation range is what it is.”
The description now shows the defining traits that drive value and will remain visible even when not viewing the AI sheet.
4. Full AI Explanation Always Available (On-Demand)
We decided not to store the entire AI analysis structure long-term.
Instead:
The user can re-run Analyze with AI anytime to regenerate the full detailed analysis.
This is fast, always up-to-date, and uses their saved notes.
The saved summary + valuation snapshot is sufficient for everyday viewing.
This avoids expanding the data model prematurely while still giving users full transparency whenever they want it.
5. Backend Prompt Enhancements (Next Step)
To further improve valuation quality:
The backend will treat user notes as high-signal authoritative details.
The model will be asked to include optional “Approximate new replacement price” information in its explanation, when relevant.
This will appear in the AI Notes section (not as a stored numeric field).
This helps users understand both resale value and replacement cost when planning their estate or insurance needs.
Summary of Current Direction
Keep the valuation model simple (one snapshot).
Let users add meaningful details that persist with the item.
Let the AI regenerate full explanations when needed.
Ensure item descriptions clearly capture the characteristics that drive value.
Continue improving the backend Expert prompt to make the analysis more helpful.
✅ 1. README Update — Current Status (drop this into the top of README)
📌 Current Status — AI ValueHints v2 Integration December 8 2025
The Legacy Treasure Chest app now uses the updated ValueHints → ValueRange model across the entire AI pipeline. This includes:
Backend now returns the enriched value_hints block:
low, high, currency_code, confidence, sources[], and last_updated
Swift front-end updated to match the new model:
AIModels.ValueRange replaced old ValueHints
All views updated (AddItemWithAIView, BatchAddItemsFromPhotosView, ItemAIAnalysisSheet, AITestView)
Feature flag defaults updated to ensure AI is enabled by default (enableMarketAI = true)
SwiftData rebuild completed after schema updates (simulator reset required)
AI analysis now provides:
richer details (materials, maker, condition, features, extracted text)
improved valuation metadata
correct propagation of value estimates into LTCItem.value, suggestedPriceNew, suggestedPriceUsed
Next major milestone:
→ Design and implement ItemValuation.swift, allowing the app to store multiple valuation snapshots per item, with source/model/date/version fields.
✅ README Update (drop-in text block)
Add this as a new section near the top of your README under “Current Status” or “Recent Work Completed”.
(You can also keep it as a dated changelog entry.)
Beneficiaries Module — Completed Boomer-Side Functionality (2025-02)
The Beneficiaries module is now fully implemented for the primary “owner” (Boomer) workflow. The following features are complete:
Beneficiary Management
Create beneficiaries manually with name, relationship, email, and phone number.
Import beneficiaries directly from iOS Contacts using a custom ContactPicker.
Automatic deduplication: selecting a contact for an existing name merges the data rather than creating duplicates.
Beneficiaries imported from Contacts display a subtle “Linked to Contacts” badge in all views.
Edit Beneficiary screen allows updating:
name
relationship
email
phone
contact linkage (“Update from Contacts”)
Relationship Selector
Relationship field now uses a structured selector for consistent data:
Son, Daughter, Grandchild, Niece, Nephew, Sibling, Friend, Other
“Other / Custom…” opens a free-text field.
Beneficiary records always store a clean relationship value.
Assignment & Item Linking
Beneficiaries can be assigned to items through the ItemDetail screen using a picker.
Each assignment stores the access permission (immediate, upon passing, specific date).
Users can remove assignments or edit permissions at any time.
Beneficiary Overview Screen
“Your Beneficiaries” screen shows:
name + relationship
number of assigned items
total assigned value (using the item’s current estimated value)
a badge for Contacts-linked beneficiaries
Unassigned items appear in a separate section for quick distribution.
Beneficiary Detail View
Shows:
complete beneficiary information
Contact linkage indicator
assigned item list with thumbnails and permission details
total assigned value summary
Inline “Edit Beneficiary” button opens the edit sheet.
General Notes
This module is now feature-complete for the owner workflow and ready for TestFlight.
Future enhancements (Millennial/recipient workflow, shared claiming, CloudKit multi-user sync) can build on this foundation.
### 2025-11-28 — Beneficiaries Module & Contacts Integration

**Beneficiaries (Owner / Boomer view)**

- Implemented **YourBeneficiariesView** as the top-level entry point:
  - Shows each Beneficiary with relationship, number of items, and total assigned value (using current item values).
  - Displays a **“From Contacts”** badge for Beneficiaries linked to iOS Contacts.
  - Supports swipe-to-delete for Beneficiaries with no assigned items and prevents deletion when items are still linked (with an explanatory message).

- Implemented **BeneficiaryDetailView**:
  - Shows contact info (name, relationship, email, phone).
  - Shows total value of assigned items.
  - Lists assigned items with thumbnails, category, per-item value, and access rules, navigating into `ItemDetailView` on tap.

- Implemented **BeneficiaryFormSheet** (manual add):
  - Simple, theme-aligned sheet for manually adding Beneficiaries (name, relationship, email, phone).
  - New Beneficiaries appear in both Your Beneficiaries and the item-level Beneficiary picker.

- Implemented **ContactPickerView** + top-level Contacts integration:
  - “+” menu in Your Beneficiaries offers:
    - **Add from Contacts** — opens the system Contacts picker.
    - **Add Manually** — opens `BeneficiaryFormSheet`.
  - Selecting a contact will:
    - Reuse an existing Beneficiary linked to that contact if one exists.
    - Otherwise, try to **merge with an existing Beneficiary** by name/email (to avoid duplicates).
    - Only create a brand new Beneficiary when no reasonable match is found.
  - When merging, the app fills in missing email/phone but preserves any user-edited name.

- Item-level Beneficiary UX:
  - `ItemBeneficiariesSection` shows per-item Beneficiary links with access rules and notification status.
  - Users can:
    - Add a Beneficiary to an item via the Beneficiary picker.
    - Edit a link via `ItemBeneficiaryEditSheet` (access rules, date, personal message).
    - Remove a link (deletes the junction record, not the Beneficiary).

- **Unassigned Items**:
  - `YourBeneficiariesView` shows a dedicated **Unassigned Items** section listing items with no Beneficiaries.
  - Tapping an item navigates into `ItemDetailView` to assign Beneficiaries from there.

**Other sync / polish**

- Aligned category options across:
  - `ItemDetailView`
  - `AddItemView`
  - `AddItemWithAIView`
- Ensured Beneficiary-related views are fully Theme-driven (typography, colors, spacing) and integrated into the main navigation via Home → Beneficiaries.

## Status Update – AI Integration, Items UI, and Documents (2025-12-04)

### AI Integration

- AI item analysis now runs through the **LTC AI Gateway** backend:
  - iOS uses `AIService` with `BackendAIProvider`.
  - Backend is a FastAPI app that calls Gemini 2.0 Flash and returns strict JSON.
  - No Gemini API keys or secrets are present in the iOS app.
- The following flows are working end-to-end:
  - `AITestView` (internal lab) – single photo → ItemAnalysis.
  - Batch Add from Photos – multiple photos → multiple items with AI-filled details.
  - AI-assisted analysis on existing items via `ItemAIAnalysisSheet`.

### Items UI & Categories

- “Your Items” list now:
  - Shows a **thumbnail** for each item (first photo if available, placeholder otherwise).
  - Groups items by **Category** when not searching (Art, Jewelry, Rug, Luxury Personal Items, etc.).
  - Falls back to a flat thumbnail list while searching, for easier scanning of matches.
- Category options have been expanded and aligned with the AI backend, including:
  - `China & Crystal`
  - `Luxury Personal Items`
  - `Tools`
  - Plus existing categories like `Art`, `Furniture`, `Jewelry`, `Collectibles`, `Rug`, `Luggage`, `Decor`, `Other`.
- Existing items may still have older or legacy category values; these will be normalized over time as items are edited.

### Documents vs Photos – Current Decision

- **Documents**:
  - Currently optimized for PDFs and other files added via the system file picker (Files, Mail, etc.).
- **Photos**:
  - All camera-based images, including photos of receipts, appraisals, labels, and other “document-like” images, are managed in the Photos section.
- Intentional decision for this phase:
  - Documents = external files (especially PDFs).
  - Photos = all images, even when they represent documentation.
- Deferred enhancement:
  - In a future iteration, enhance the Documents module to:
    - Import images from Photos as `IMAGE` documents.
    - Add document-type metadata (e.g., Appraisal, Receipt, Warranty, Insurance Statement).

### Next Focus – Beneficiaries

- Upcoming work will focus on the **Beneficiaries** experience:
  - Confirm and polish the existing Item → Beneficiary linking (ItemBeneficiariesSection, BeneficiaryPickerSheet, ItemBeneficiaryEditSheet).
  - Introduce a “Your Beneficiaries” screen to view and manage beneficiaries.
  - Add a “Beneficiary detail” view to see all items associated with a given person (e.g., “What does Sarah get?”).
- AI features for beneficiary suggestions (`suggestBeneficiaries`) and personalized messaging (`draftPersonalMessage`) remain planned but are not yet implemented; current phase is about getting the core data model and UX flows solid.

## AI Integration Status (Local Backend + Gemini)

**Last Updated:** 2025-11-28

- The Legacy Treasure Chest iOS app now uses a **provider-agnostic AI layer**:
  - `AIProvider` protocol defines `analyzeItemPhoto`, `estimateValue`, `draftPersonalMessage`, and `suggestBeneficiaries`.
  - `AIService.shared` is the façade used by views and is initialized with `BackendAIProvider` by default.
- A separate **FastAPI backend** (`LTC_AI_Gateway`) runs on the Mac host and handles all calls to Gemini:
  - Endpoint: `POST http://127.0.0.1:8000/ai/analyze-item-photo`
  - Backend holds `GEMINI_API_KEY` and `GEMINI_MODEL` in `.env` and never exposes them to the iOS app.
  - Pydantic models mirror the Swift `ItemAIHints`, `ValueRange`, and `ItemAnalysis` types.
- `BackendAIProvider`:
  - Encodes item photos as Base64 JPEG (`imageJpegBase64`).
  - Sends `AnalyzeItemPhotoRequest` (image + optional `ItemAIHints`) to the backend.
  - Decodes the response into Swift `ItemAnalysis` using `JSONDecoder` with default camelCase keys.
- `AITestView`:
  - Uses `AIService.shared.analyzeItemPhoto(_:hints:)` end-to-end through the backend.
  - Confirmed working in the iOS Simulator with realistic test photos and optional hints.
- **Security**:
  - No Gemini API key or secret is present in the iOS app, Info.plist, or build settings.
  - All AI traffic from the app flows through the backend gateway.

**Next AI Front-End Tasks (Option B):**

1. Wire `AddItemWithAIView` to rely solely on `AIService` + `BackendAIProvider`.
2. Ensure `BatchAddItemsFromPhotosView` uses the backend for each photo in a batch.
3. Confirm `ItemAIAnalysisSheet` calls the backend for re-analysis on existing items.

✅ Legacy Treasure Chest — Project Status (Updated)
Last Updated: (November 28, 2025)
Milestone: AI Batch Add & Item-Level AI Analysis — Completed
App Version: Phase 1C+ (AI-Native Foundation Complete)
Target Platform: iOS 18+, SwiftUI, SwiftData, Apple Intelligence-enabled devices
🚀 Current High-Level Status
Legacy Treasure Chest now includes a fully functional personal inventory system with integrated AI-powered item analysis, batch import capabilities, media management, and beneficiary assignment.
The following modules are fully implemented and working end-to-end:
📦 Core Features — Complete
Authentication
Sign in with Apple (production-ready)
Simulator-friendly authentication override
User-specific data management (LTCUser)
Item Management
ItemsListView with search, sorting, deletion
AddItemView for manual entry
ItemDetailView with live SwiftData persistence
Categories, values, timestamps, descriptions
Media Modules
Photos
Add, view, pinch-to-zoom, delete, share
Documents
FileImporter, type detection, preview via QuickLook
Image/PDF support, share sheet
Audio
Recording, playback, deletion
Microphone permission handling (iOS 18)
MediaStorage
Unified file storage for images, documents, and audio
Beneficiaries
Create/manage beneficiaries
Item-level beneficiary assignment via junction model
Edit access rules and permissions
Sheet-based UI fully integrated into ItemDetailView
🤖 AI System — Complete & Extensible
AI Architecture
Provider-agnostic abstraction (AIProvider protocol)
Central AI façade (AIService)
Concrete Gemini provider (GeminiProvider)
Prompt templating + JSON structured return format
Full error handling with friendly messaging
Item-Level AI Analysis
Users can analyze any item’s primary image
AI suggests:
Improved title & description
Category
Value estimate & range
Attributes, materials, style, condition
Extracted text (OCR)
AI results displayed in a dedicated analysis sheet
“Apply to Item” writes results back to SwiftData
AI Test Lab
Standalone internal testing tool for prompt iteration
Allows image selection + optional hints + raw AI inspection
🖼️ Batch Add from Photos — Complete
A major user-facing feature:
User selects multiple photos from library
AI analyzes each image:
Title, description, category, value
Tags, attributes, features
Extracted OCR text
User reviews results in a scrolling list
User toggles which items to import
Items are created in SwiftData with associated images
Includes:
Error-safe design (per-image error display)
Graceful handling of decode failures
Immediate import into the system
Works well with large batches (3–10+ images)
🎨 Design System — Fully Integrated
All new UI uses Theme.swift colors, fonts, spacing
Custom branded section headers & cards
Uniform toolbar tinting
Consistent typography across modules
🧱 Architecture Summary
SwiftData: primary persistence layer
SwiftUI: complete UI layer
MediaStorage: file management for all media
Gemini Provider: first-class AI backend
Modular Feature Folders:
Items
Photos
Documents
Audio
Beneficiaries
AI (Models, Services, Views)
Authentication
Shared UI + Utilities
🏁 Current State Assessment
The app is now stable, modular, and ready for:
Extensive AI tuning
Adding fair market value confidence displays
Batch add improvements (retry, inline edits, etc.)
Later phases: CloudKit, Sharing, Marketplace integrations
This is a significant milestone:
Legacy Treasure Chest now has a complete AI-native foundation, allowing rapid expansion of capabilities without reworking the core architecture.
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

