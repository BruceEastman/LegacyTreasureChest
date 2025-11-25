# Legacy Treasure Chest
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

