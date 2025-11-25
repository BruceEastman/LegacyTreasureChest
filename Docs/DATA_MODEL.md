# Legacy Treasure Chest - Data Model

**Last Updated:** 2025-01-14  
**Status:** ACTIVE  
**Version:** 1.0.0 (Phase 1A)

## Overview

SwiftData-based data model for iOS 18+. Metadata stored in SwiftData, large media files stored on file system with relative path references.

---

## Entity Relationship Diagram
```
LTCUser
  │
  ├──[1:N]──> LTCItem
  │              │
  │              ├──[1:N]──> ItemImage (file path)
  │              ├──[1:N]──> AudioRecording (file path + transcription)
  │              ├──[1:N]──> Document (file path)
  │              └──[1:N]──> ItemBeneficiary
  │                             │
  └──[1:N]──> Beneficiary ◄─[N:1]┘
```

---

## Entities

### LTCUser

**Purpose:** Represents an authenticated user (Sign in with Apple)
```swift
@Model
public final class LTCUser {
    @Attribute(.unique) var userId: UUID
    @Attribute(.unique) var appleUserIdentifier: String
    var email: String?                    // Optional: may use Private Relay
    var name: String?                     // Optional: user can update
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship(deleteRule: .cascade) var items: [LTCItem]
    @Relationship(deleteRule: .cascade) var beneficiaries: [Beneficiary]
}
```

**Validation Rules:**
- `userId`: Unique, auto-generated
- `appleUserIdentifier`: Unique, stable across devices, required
- `email`: Valid format if provided
- `name`: No restrictions, user-editable

**Notes:**
- No `passwordHash` - Sign in with Apple only
- `email` may be Private Relay address
- User can update `name` after initial setup

---

### LTCItem

**Purpose:** Represents a cataloged physical item
```swift
@Model
public final class LTCItem {
    @Attribute(.unique) var itemId: UUID
    @Attribute(.indexed) var name: String
    var itemDescription: String
    var category: String
    var value: Decimal
    var createdAt: Date
    var updatedAt: Date
    
    // AI-generated (optional)
    var llmGeneratedTitle: String?
    var llmGeneratedDescription: String?
    var suggestedPriceNew: Decimal?
    var suggestedPriceUsed: Decimal?
    
    @Relationship(inverse: \LTCUser.items) var user: LTCUser?
    @Relationship(deleteRule: .cascade) var images: [ItemImage]
    @Relationship(deleteRule: .cascade) var audioRecordings: [AudioRecording]
    @Relationship(deleteRule: .cascade) var documents: [Document]
    @Relationship(deleteRule: .cascade) var itemBeneficiaries: [ItemBeneficiary]
}
```

**Validation Rules:**
- `name`: Required, 1-200 characters
- `itemDescription`: 0-10,000 characters
- `category`: Required, selected from predefined list
- `value`: >= 0

**Notes:**
- `user` is optional to avoid creation crashes (set after init)
- Child collections use `.cascade` delete rule
- AI fields populated asynchronously

---

### ItemImage

**Purpose:** Links items to image files
```swift
@Model
public final class ItemImage {
    @Attribute(.unique) var imageId: UUID
    var filePath: String              // "Media/Images/{uuid}.jpg"
    var createdAt: Date
    
    @Relationship(inverse: \LTCItem.images) var item: LTCItem?
}
```

**Storage Strategy:**
- Image data: File system at `Application Support/LegacyTreasureChest/Media/Images/`
- Database: Only file path + metadata
- Format: JPEG (80% quality)
- Max size: TBD (compressed on save)

---

### AudioRecording

**Purpose:** Links items to audio recordings with transcription
```swift
@Model
public final class AudioRecording {
    @Attribute(.unique) var audioRecordingId: UUID
    var filePath: String              // "Media/Audio/{uuid}.m4a"
    var duration: Double              // Seconds
    var transcription: String?        // Apple Intelligence transcription
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship(inverse: \LTCItem.audioRecordings) var item: LTCItem?
}
```

**Storage Strategy:**
- Audio data: File system at `Application Support/LegacyTreasureChest/Media/Audio/`
- Database: File path + duration + transcription
- Format: AAC-LC (.m4a)
- Transcription: Generated on-device after recording

**Notes:**
- Multiple recordings per item supported
- Transcription searchable via SwiftData queries
- Duration calculated during recording

---

### Document

**Purpose:** Links items to PDF/document files
```swift
@Model
public final class Document {
    @Attribute(.unique) var documentId: UUID
    var filePath: String              // "Media/Documents/{uuid}.pdf"
    var documentType: String          // MIME type
    var createdAt: Date
    
    @Relationship(inverse: \LTCItem.documents) var item: LTCItem?
}
```

**Storage Strategy:**
- Document data: File system at `Application Support/LegacyTreasureChest/Media/Documents/`
- Database: File path + type
- Supported: PDF, JPEG, PNG (receipts, certificates)

---

### Beneficiary

**Purpose:** Represents a person designated to receive items
```swift
@Model
public final class Beneficiary {
    @Attribute(.unique) var beneficiaryId: UUID
    @Attribute(.indexed) var name: String
    var relationship: String
    var email: String?
    var phoneNumber: String?
    var contactIdentifier: String?    // CNContact ID (advisory)
    var isLinkedToContact: Bool       // True if imported from Contacts
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship(inverse: \LTCUser.beneficiaries) var user: LTCUser?
    @Relationship(deleteRule: .cascade) var itemLinks: [ItemBeneficiary]
}
```

**Validation Rules:**
- `name`: Required, 1-100 characters
- `relationship`: Required (e.g., "Daughter", "Son", "Friend")
- At least one of `email` or `phoneNumber` required
- `contactIdentifier`: Advisory only, may change

**Notes:**
- Can be created manually or imported from Contacts
- Contact import is one-time copy (not synced)
- Multiple beneficiaries per item supported

---

### ItemBeneficiary

**Purpose:** Links items to beneficiaries with access conditions
```swift
@Model
public final class ItemBeneficiary {
    @Attribute(.unique) var itemBeneficiaryId: UUID
    var accessPermissionRaw: String
    var accessDate: Date?
    var personalMessage: String?
    var notificationStatusRaw: String
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship(inverse: \LTCItem.itemBeneficiaries) var item: LTCItem?
    @Relationship(inverse: \Beneficiary.itemLinks) var beneficiary: Beneficiary?
    
    // Computed properties
    var accessPermission: AccessPermission { get set }
    var notificationStatus: NotificationStatus { get set }
}
```

**Enums:**
```swift
enum AccessPermission: String {
    case immediate             // Beneficiary can access now
    case afterSpecificDate     // Access granted on accessDate
    case uponPassing           // Access after user verification
}

enum NotificationStatus: String {
    case notSent
    case sent
    case accepted
}
```

**Validation Rules:**
- `accessPermission`: Required
- `accessDate`: Required if `accessPermission == .afterSpecificDate`
- `accessDate`: Must be future date if specified
- `personalMessage`: 0-5,000 characters

---

### Household (Phase 2)

**Purpose:** Groups users for collaborative item management
```swift
@Model
public final class Household {
    @Attribute(.unique) var householdId: UUID
    var householdName: String
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship(deleteRule: .cascade) var items: [LTCItem]
}
```

**Status:** Deferred to Phase 2 (Weeks 6-8)

---

## Relationship Guidelines

### Parent → Child
- Use `@Relationship(deleteRule: .cascade)`
- Children deleted when parent deleted
- Example: Deleting `LTCItem` deletes all its `ItemImage` records

### Child → Parent
- Use `@Relationship(inverse: \Parent.children)`
- Make reference **optional** (`var parent: Parent?`)
- Prevents creation-time crashes

### Many-to-Many
- Use junction entity (`ItemBeneficiary`)
- Both sides reference junction with `.cascade` delete

---

## Indexes
```swift
@Attribute(.unique)  // Enforces uniqueness
@Attribute(.indexed) // Optimizes queries
```

**Indexed Fields:**
- `LTCUser.userId` (unique)
- `LTCUser.appleUserIdentifier` (unique)
- `LTCItem.name` (indexed for search)
- `Beneficiary.name` (indexed for search)

---

## Data Versioning

### Current Version: 1.0.0

**Schema Changes:**
- **Lightweight migrations:** SwiftData handles automatically
- **Complex migrations:** Require manual migration code

**Versioning Strategy:**
1. Test migrations in development
2. Document schema changes in CHANGELOG
3. Provide fallback if migration fails

---

## Models Changelog

### Version 1.0.0 (2025-01-14) - Initial Release
- Created all base entities
- Established relationship patterns
- Configured file-path storage strategy
- Defined validation rules

---

## File System Layout
```
Application Support/LegacyTreasureChest/
├── Media/
│   ├── Images/
│   │   └── {uuid}.jpg
│   ├── Audio/
│   │   └── {uuid}.m4a
│   └── Documents/
│       └── {uuid}.pdf
└── [SwiftData store files]
```

**Strategy:**
- SwiftData stores: Metadata + relationships
- File system stores: Binary data
- Relative paths in database: `"Media/Images/{uuid}.jpg"`

**Benefits:**
- Smaller database size
- Faster queries
- Easier backup/restore
- Better performance

---

## Orphan File Cleanup

**MediaCleaner** runs:
- On app launch (background)
- User-initiated (Settings)
- After data export/delete

**Process:**
1. Query all `filePath` values from SwiftData
2. List all files in Media directories
3. Delete files not in SwiftData

---

## CloudKit Sync (Phase 1B)

**Configuration:**
- Enable `isCloudKitContainerEnabled` in ModelConfiguration
- Use private database
- Automatic conflict resolution: Last-writer-wins
- Manual sync trigger available

**Conflict Strategy:**
- SwiftData handles automatically
- Log conflicts in ActivityLog (Phase 2)
- User notified of significant conflicts

---

## Testing Recommendations

### Unit Tests
- Entity creation/deletion
- Relationship integrity
- Validation rules
- File path generation

### Integration Tests
- SwiftData queries
- Media file storage/retrieval
- Orphan cleanup
- CloudKit sync (Phase 1B)

---

## Related Documents

- [ARCHITECTURE.md](ARCHITECTURE.md) - System overview
- [SERVICES.md](SERVICES.md) - Service layer accessing data
- [SECURITY.md](SECURITY.md) - Data encryption and privacy

---

## Change Log

- **2025-01-14:** Initial data model documentation
  - All entities defined
  - Relationships established
  - File storage strategy documented