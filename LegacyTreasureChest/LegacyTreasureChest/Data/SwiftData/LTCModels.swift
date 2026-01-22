//
//  LTCModels.swift
//  LegacyTreasureChest
//
//  SwiftData models for Legacy Treasure Chest.
//  iOS 18+, Swift 6.
//

import Foundation
import SwiftData

// MARK: - Enums (non-model types)

public enum AccessPermission: String, Codable, CaseIterable, Sendable {
    case immediate = "Immediate"
    case afterSpecificDate = "AfterSpecificDate"
    case uponPassing = "UponPassing"
}

public enum NotificationStatus: String, Codable, CaseIterable, Sendable {
    case notSent = "NotSent"
    case sent = "Sent"
    case accepted = "Accepted"
}

// MARK: - Liquidation Enums (non-model types)

// NOTE: This enum is your item-level disposition (Legacy vs Liquidate).
// We keep it as-is.
public enum ItemDisposition: String, Codable, CaseIterable, Sendable {
    case undecided = "Undecided"
    case legacy = "Legacy"
    case liquidate = "Liquidate"
}

public enum LiquidationStatus: String, Codable, CaseIterable, Sendable {
    case notStarted = "NotStarted"
    case hasBrief = "HasBrief"
    case inProgress = "InProgress"
    case completed = "Completed"
    case onHold = "OnHold"
    case notApplicable = "NotApplicable"
}

public enum LiquidationPath: String, Codable, CaseIterable, Sendable {
    case pathA = "PathA_MaximizePrice"
    case pathB = "PathB_DelegateConsign"
    case pathC = "PathC_QuickExit"
    case donate = "Donate"
    case needsInfo = "NeedsInfo"
}

// Legacy enum (used by v1 LiquidationBrief/LiquidationPlan)
public enum LiquidationScope: String, Codable, CaseIterable, Sendable {
    case item = "Item"
    case set = "Set"
}

public enum PlanStatus: String, Codable, CaseIterable, Sendable {
    case notStarted = "NotStarted"
    case inProgress = "InProgress"
    case completed = "Completed"
    case onHold = "OnHold"
}

// MARK: - Set Enums

public enum SetType: String, Codable, CaseIterable, Sendable {
    case diningRoom = "Dining Room"
    case bedroom = "Bedroom"
    case china = "China/Dinnerware"
    case crystal = "Crystal/Stemware"
    case flatware = "Flatware/Silverware"
    case rugCollection = "Rug Collection"
    case furnitureSuite = "Furniture Suite"
    case closetLot = "Closet Lot"
    case other = "Other"
}

public enum SellTogetherPreference: String, Codable, CaseIterable, Sendable {
    case togetherOnly = "TogetherOnly"
    case togetherPreferred = "TogetherPreferred"
    case splitPreferred = "SplitPreferred"
    case splitOnly = "SplitOnly"
}

public enum Completeness: String, Codable, CaseIterable, Sendable {
    case complete = "Complete"
    case mostlyComplete = "MostlyComplete"
    case partial = "Partial"
    case unknown = "Unknown"
}

// MARK: - NEW: Unified Liquidation Infrastructure (Pattern A)

public enum LiquidationOwnerType: String, Codable, CaseIterable, Sendable {
    case item = "Item"
    case itemSet = "ItemSet"
    case batch = "Batch"
}

/// Batch-level status (Estate Sale / Auction / Consignment event lifecycle)
public enum LiquidationBatchStatus: String, Codable, CaseIterable, Sendable {
    case draft = "Draft"
    case planned = "Planned"
    case active = "Active"
    case completed = "Completed"
    case cancelled = "Cancelled"
}

public enum LiquidationSaleType: String, Codable, CaseIterable, Sendable {
    case estateSale = "EstateSale"
    case auction = "Auction"
    case consignment = "Consignment"
    case dealerBuyout = "DealerBuyout"
    case mixed = "Mixed"
}

public enum VenueType: String, Codable, CaseIterable, Sendable {
    case onSite = "OnSite"
    case offSite = "OffSite"
    case online = "Online"
    case hybrid = "Hybrid"
}

/// IMPORTANT: This is NOT the same as item-level `ItemDisposition`.
/// This is the batch-specific override for an item *in a particular batch context*.
public enum BatchItemDisposition: String, Codable, CaseIterable, Sendable {
    case include = "Include"
    case exclude = "Exclude"
    case donate = "Donate"
    case trash = "Trash"
    case holdback = "Holdback"
    case undecided = "Undecided"
}

// MARK: - User

@Model
public final class LTCUser {
    @Attribute(.unique) public var userId: UUID
    @Attribute(.unique) public var appleUserIdentifier: String
    public var email: String?
    public var name: String?
    public var createdAt: Date
    public var updatedAt: Date

    // Relationships
    @Relationship(deleteRule: .cascade) public var items: [LTCItem] = []
    @Relationship(deleteRule: .cascade) public var beneficiaries: [Beneficiary] = []

    // Liquidate (legacy + new)
    @Relationship(deleteRule: .cascade) public var triageEntries: [TriageEntry] = []

    // LEGACY: prior set model (kept for migration/compat during transition)
    @Relationship(deleteRule: .cascade) public var sets: [LTCSet] = []

    // NEW: item sets + batches
    @Relationship(deleteRule: .cascade) public var itemSets: [LTCItemSet] = []
    @Relationship(deleteRule: .cascade) public var liquidationBatches: [LiquidationBatch] = []

    public init(
        userId: UUID = UUID(),
        appleUserIdentifier: String,
        email: String? = nil,
        name: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.userId = userId
        self.appleUserIdentifier = appleUserIdentifier
        self.email = email
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Item

@Model
public final class LTCItem {
    @Attribute(.unique) public var itemId: UUID
    public var name: String
    public var itemDescription: String
    public var category: String

    /// Unit value (per single item). Total value = unit value × quantity.
    public var value: Double

    /// Quantity of identical items represented by this entry. Minimum 1.
    public var quantity: Int = 1

    public var createdAt: Date
    public var updatedAt: Date

    // AI-generated fields (optional)
    public var llmGeneratedTitle: String?
    public var llmGeneratedDescription: String?
    public var suggestedPriceNew: Double?
    public var suggestedPriceUsed: Double?

    // Item-level “Legacy vs Liquidate” + minimal workflow state (kept)
    public var dispositionRaw: String = ItemDisposition.undecided.rawValue
    public var liquidationStatusRaw: String = LiquidationStatus.notStarted.rawValue
    public var selectedLiquidationPathRaw: String?

    public var disposition: ItemDisposition {
        get { ItemDisposition(rawValue: dispositionRaw) ?? .undecided }
        set { dispositionRaw = newValue.rawValue }
    }

    public var liquidationStatus: LiquidationStatus {
        get { LiquidationStatus(rawValue: liquidationStatusRaw) ?? .notStarted }
        set { liquidationStatusRaw = newValue.rawValue }
    }

    public var selectedLiquidationPath: LiquidationPath? {
        get {
            guard let raw = selectedLiquidationPathRaw else { return nil }
            return LiquidationPath(rawValue: raw)
        }
        set { selectedLiquidationPathRaw = newValue?.rawValue }
    }

    // Relationships (user is optional to avoid creation crashes)
    @Relationship(inverse: \LTCUser.items) public var user: LTCUser?
    @Relationship(deleteRule: .cascade) public var images: [ItemImage] = []
    @Relationship(deleteRule: .cascade) public var audioRecordings: [AudioRecording] = []
    @Relationship(deleteRule: .cascade) public var documents: [Document] = []
    @Relationship(deleteRule: .cascade) public var itemBeneficiaries: [ItemBeneficiary] = []

    /// Optional AI-driven valuation attached to this item (v1: single latest valuation).
    @Relationship(deleteRule: .cascade) public var valuation: ItemValuation?

    // NEW (Pattern A): unified liquidation state for this item
    // LiquidationState owns briefs/plans; LTCItem owns LiquidationState (cascade).
    @Relationship(deleteRule: .cascade)
    public var liquidationState: LiquidationState?


    // NEW: set membership via join (supports qty-in-set, roles, and future multi-set if needed)
    @Relationship(deleteRule: .cascade)
    public var setMemberships: [LTCItemSetMembership] = []


    // LEGACY: prior set membership (0/1) + briefs/plans (kept for transition/migration)
    @Relationship(inverse: \LTCSet.items) public var set: LTCSet?
    @Relationship(deleteRule: .cascade) public var liquidationBriefs: [LiquidationBrief] = []
    public var liquidationPlan: LiquidationPlan?

    public init(
        itemId: UUID = UUID(),
        name: String,
        itemDescription: String,
        category: String,
        value: Double = 0,
        quantity: Int = 1,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.itemId = itemId
        self.name = name
        self.itemDescription = itemDescription
        self.category = category
        self.value = value
        self.quantity = max(1, quantity)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - NEW: LiquidationState Hub (Pattern A)

@Model
public final class LiquidationState {
    @Attribute(.unique) public var stateId: UUID

    public var ownerTypeRaw: String
    public var statusRaw: String

    public var createdAt: Date
    public var updatedAt: Date

    // Exactly one of these should be non-nil (enforced in business logic / factories).
    @Relationship(inverse: \LTCItem.liquidationState) public var item: LTCItem?
    @Relationship public var itemSet: LTCItemSet?
    @Relationship public var batch: LiquidationBatch?

    // History (owned by LiquidationState)
    @Relationship(deleteRule: .cascade)
    public var briefs: [LiquidationBriefRecord] = []

    @Relationship(deleteRule: .cascade)
    public var plans: [LiquidationPlanRecord] = []


    public var ownerType: LiquidationOwnerType {
        get { LiquidationOwnerType(rawValue: ownerTypeRaw) ?? .item }
        set { ownerTypeRaw = newValue.rawValue }
    }

    public var status: LiquidationStatus {
        get { LiquidationStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    public var activeBrief: LiquidationBriefRecord? {
        briefs.first(where: { $0.isActive })
    }

    public var activePlan: LiquidationPlanRecord? {
        plans.first(where: { $0.isActive })
    }

    public init(
        stateId: UUID = UUID(),
        ownerType: LiquidationOwnerType,
        status: LiquidationStatus = .notStarted,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.stateId = stateId
        self.ownerTypeRaw = ownerType.rawValue
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - NEW: BriefRecord (immutable AI artifact, versioned JSON)

@Model
public final class LiquidationBriefRecord {
    @Attribute(.unique) public var briefRecordId: UUID

    public var createdAt: Date
    public var isActive: Bool

    /// For dedupe / reproducibility. (e.g., hash of key inputs)
    public var inputFingerprint: String?

    /// Version string for the JSON schema (e.g., "brief.v1")
    public var payloadVersion: String

    /// AI provider metadata
    public var aiProvider: String?
    public var aiModel: String?

    /// Opaque JSON payload containing the structured brief DTO.
    public var payloadJSON: Data

    @Relationship(inverse: \LiquidationState.briefs) public var state: LiquidationState?

    public init(
        briefRecordId: UUID = UUID(),
        createdAt: Date = .now,
        isActive: Bool = true,
        inputFingerprint: String? = nil,
        payloadVersion: String = "brief.v1",
        aiProvider: String? = nil,
        aiModel: String? = nil,
        payloadJSON: Data = Data()
    ) {
        self.briefRecordId = briefRecordId
        self.createdAt = createdAt
        self.isActive = isActive
        self.inputFingerprint = inputFingerprint
        self.payloadVersion = payloadVersion
        self.aiProvider = aiProvider
        self.aiModel = aiModel
        self.payloadJSON = payloadJSON
    }
}

// MARK: - NEW: PlanRecord (mutable execution plan, versioned JSON)

@Model
public final class LiquidationPlanRecord {
    @Attribute(.unique) public var planRecordId: UUID

    public var createdAt: Date
    public var updatedAt: Date
    public var isActive: Bool

    public var chosenPathRaw: String
    public var statusRaw: String

    /// Version string for the JSON schema (e.g., "plan.v1")
    public var payloadVersion: String

    /// AI provider metadata
    public var aiProvider: String?
    public var aiModel: String?

    /// Optional: link to the brief this plan was derived from
    public var derivedFromBriefRecordId: UUID?

    /// Opaque JSON payload representing checklist state (and any per-plan constraints snapshot).
    public var payloadJSON: Data

    @Relationship(inverse: \LiquidationState.plans) public var state: LiquidationState?

    public var chosenPath: LiquidationPath {
        get { LiquidationPath(rawValue: chosenPathRaw) ?? .needsInfo }
        set { chosenPathRaw = newValue.rawValue }
    }

    public var status: PlanStatus {
        get { PlanStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    public init(
        planRecordId: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isActive: Bool = true,
        chosenPath: LiquidationPath,
        status: PlanStatus = .notStarted,
        payloadVersion: String = "plan.v1",
        aiProvider: String? = nil,
        aiModel: String? = nil,
        derivedFromBriefRecordId: UUID? = nil,
        payloadJSON: Data = Data()
    ) {
        self.planRecordId = planRecordId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
        self.chosenPathRaw = chosenPath.rawValue
        self.statusRaw = status.rawValue
        self.payloadVersion = payloadVersion
        self.aiProvider = aiProvider
        self.aiModel = aiModel
        self.derivedFromBriefRecordId = derivedFromBriefRecordId
        self.payloadJSON = payloadJSON
    }
}

// MARK: - NEW: ItemSet (group of items)

@Model
public final class LTCItemSet {
    @Attribute(.unique) public var itemSetId: UUID

    public var name: String
    public var setTypeRaw: String
    public var story: String?
    public var notes: String?
    
    // Closet Lot metadata (Clothing v1) — optional, only used when setType == .closetLot
    public var closetApproxItemCount: String?
    public var closetSizeBand: String?
    public var closetConditionBandRaw: String?   // LikeNew | Good | Fair | Poor
    public var closetBrandList: String?          // comma-separated free text


    public var sellTogetherPreferenceRaw: String
    public var completenessRaw: String

    /// Optional premium estimate (e.g., 0.15 = +15%) when sold as a coherent set.
    public var estimatedSetPremium: Double?

    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(inverse: \LTCUser.itemSets) public var user: LTCUser?

    // Membership (join model)
    @Relationship(deleteRule: .cascade)
    public var memberships: [LTCItemSetMembership] = []


    // Set-level liquidation (Pattern A)
    @Relationship(deleteRule: .cascade, inverse: \LiquidationState.itemSet)
    public var liquidationState: LiquidationState?

    public var setType: SetType {
        get { SetType(rawValue: setTypeRaw) ?? .other }
        set { setTypeRaw = newValue.rawValue }
    }

    public var sellTogetherPreference: SellTogetherPreference {
        get { SellTogetherPreference(rawValue: sellTogetherPreferenceRaw) ?? .togetherPreferred }
        set { sellTogetherPreferenceRaw = newValue.rawValue }
    }

    public var completeness: Completeness {
        get { Completeness(rawValue: completenessRaw) ?? .unknown }
        set { completenessRaw = newValue.rawValue }
    }

    public init(
        itemSetId: UUID = UUID(),
        name: String,
        setType: SetType = .other,
        story: String? = nil,
        notes: String? = nil,
        closetApproxItemCount: String? = nil,
        closetSizeBand: String? = nil,
        closetConditionBandRaw: String? = nil,
        closetBrandList: String? = nil,
        sellTogetherPreference: SellTogetherPreference = .togetherPreferred,
        completeness: Completeness = .unknown,
        estimatedSetPremium: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.itemSetId = itemSetId
        self.name = name
        self.setTypeRaw = setType.rawValue
        self.story = story
        self.notes = notes
        self.closetApproxItemCount = closetApproxItemCount
        self.closetSizeBand = closetSizeBand
        self.closetConditionBandRaw = closetConditionBandRaw
        self.closetBrandList = closetBrandList
        self.sellTogetherPreferenceRaw = sellTogetherPreference.rawValue
        self.completenessRaw = completeness.rawValue
        self.estimatedSetPremium = estimatedSetPremium
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class LTCItemSetMembership {
    @Attribute(.unique) public var membershipId: UUID

    public var createdAt: Date

    /// Optional: role in set ("primary" vs "member") without locking to enum shape.
    public var role: String

    /// Optional: quantity of this item represented in the set context (can differ from item.quantity).
    public var quantityInSet: Int?

    @Relationship(inverse: \LTCItem.setMemberships) public var item: LTCItem?
    @Relationship(inverse: \LTCItemSet.memberships) public var itemSet: LTCItemSet?

    public init(
        membershipId: UUID = UUID(),
        createdAt: Date = .now,
        role: String = "member",
        quantityInSet: Int? = nil
    ) {
        self.membershipId = membershipId
        self.createdAt = createdAt
        self.role = role
        self.quantityInSet = quantityInSet
    }
}

// MARK: - NEW: LiquidationBatch + BatchItem (estate sale / auction / etc.)

@Model
public final class LiquidationBatch {
    @Attribute(.unique) public var batchId: UUID

    public var name: String
    public var statusRaw: String
    public var saleTypeRaw: String

    public var targetDate: Date?
    public var venueRaw: String?
    public var provider: String?

    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(inverse: \LTCUser.liquidationBatches) public var user: LTCUser?

    // Batch-level liquidation (Pattern A)
    @Relationship(deleteRule: .cascade, inverse: \LiquidationState.batch)
    public var liquidationState: LiquidationState?

    // Join records (context overrides live here)
    @Relationship(deleteRule: .cascade)
    public var items: [BatchItem] = []


    public var status: LiquidationBatchStatus {
        get { LiquidationBatchStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    public var saleType: LiquidationSaleType {
        get { LiquidationSaleType(rawValue: saleTypeRaw) ?? .estateSale }
        set { saleTypeRaw = newValue.rawValue }
    }

    public var venue: VenueType? {
        get {
            guard let raw = venueRaw else { return nil }
            return VenueType(rawValue: raw)
        }
        set {
            venueRaw = newValue?.rawValue
        }
    }

    public init(
        batchId: UUID = UUID(),
        name: String,
        status: LiquidationBatchStatus = .draft,
        saleType: LiquidationSaleType = .estateSale,
        targetDate: Date? = nil,
        venue: VenueType? = nil,
        provider: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.batchId = batchId
        self.name = name
        self.statusRaw = status.rawValue
        self.saleTypeRaw = saleType.rawValue
        self.targetDate = targetDate
        self.venueRaw = venue?.rawValue
        self.provider = provider
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class BatchItem {
    @Attribute(.unique) public var batchItemId: UUID
    public var createdAt: Date

    @Relationship(inverse: \LiquidationBatch.items) public var batch: LiquidationBatch?
    @Relationship public var item: LTCItem?

    // Context overrides IN THIS BATCH
    public var dispositionRaw: String

    public var lotNumber: String?
    public var roomGroup: String?

    public var priceFloor: Double?
    public var priceTarget: Double?

    public var handlingNotes: String?
    public var sellerNotes: String?

    public var disposition: BatchItemDisposition {
        get { BatchItemDisposition(rawValue: dispositionRaw) ?? .undecided }
        set { dispositionRaw = newValue.rawValue }
    }

    public init(
        batchItemId: UUID = UUID(),
        createdAt: Date = .now,
        disposition: BatchItemDisposition = .include,
        lotNumber: String? = nil,
        roomGroup: String? = nil,
        priceFloor: Double? = nil,
        priceTarget: Double? = nil,
        handlingNotes: String? = nil,
        sellerNotes: String? = nil
    ) {
        self.batchItemId = batchItemId
        self.createdAt = createdAt
        self.dispositionRaw = disposition.rawValue
        self.lotNumber = lotNumber
        self.roomGroup = roomGroup
        self.priceFloor = priceFloor
        self.priceTarget = priceTarget
        self.handlingNotes = handlingNotes
        self.sellerNotes = sellerNotes
    }
}

// MARK: - LEGACY: Liquidate Set (group of items)
// Kept temporarily for smooth migration from prototype -> Pattern A.
// Once other files are updated to use LTCItemSet + LiquidationState, we can remove.

@Model
public final class LTCSet {
    @Attribute(.unique) public var setId: UUID
    public var name: String
    public var setTypeRaw: String
    public var story: String?
    public var notes: String?
    
    // Closet Lot metadata (Clothing v1) — optional, only used when setType == .closetLot
    public var closetApproxItemCount: String?
    public var closetSizeBand: String?
    public var closetConditionBandRaw: String?   // LikeNew | Good | Fair | Poor
    public var closetBrandList: String?          // comma-separated free text

    public var sellTogetherPreferenceRaw: String
    public var completenessRaw: String

    /// Optional premium estimate (e.g., 0.15 = +15%) when sold as a coherent set.
    public var estimatedSetPremium: Double?

    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(inverse: \LTCUser.sets) public var user: LTCUser?

    /// Items in the set (each item may belong to 0/1 set in v1).
    @Relationship public var items: [LTCItem] = []

    /// Liquidate: AI brief history for this set (immutable artifacts)
    @Relationship(deleteRule: .cascade) public var liquidationBriefs: [LiquidationBrief] = []

    /// Liquidate: current execution plan for this set (mutable user state)
    public var liquidationPlan: LiquidationPlan?

    public var setType: SetType {
        get { SetType(rawValue: setTypeRaw) ?? .other }
        set { setTypeRaw = newValue.rawValue }
    }

    public var sellTogetherPreference: SellTogetherPreference {
        get { SellTogetherPreference(rawValue: sellTogetherPreferenceRaw) ?? .togetherPreferred }
        set { sellTogetherPreferenceRaw = newValue.rawValue }
    }

    public var completeness: Completeness {
        get { Completeness(rawValue: completenessRaw) ?? .unknown }
        set { completenessRaw = newValue.rawValue }
    }

    public init(
        setId: UUID = UUID(),
        name: String,
        setType: SetType = .other,
        story: String? = nil,
        notes: String? = nil,
        closetApproxItemCount: String? = nil,
        closetSizeBand: String? = nil,
        closetConditionBandRaw: String? = nil,
        closetBrandList: String? = nil,
        sellTogetherPreference: SellTogetherPreference = .togetherPreferred,
        completeness: Completeness = .unknown,
        estimatedSetPremium: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.setId = setId
        self.name = name
        self.setTypeRaw = setType.rawValue
        self.story = story
        self.notes = notes
        self.closetApproxItemCount = closetApproxItemCount
        self.closetSizeBand = closetSizeBand
        self.closetConditionBandRaw = closetConditionBandRaw
        self.closetBrandList = closetBrandList
        self.sellTogetherPreferenceRaw = sellTogetherPreference.rawValue
        self.completenessRaw = completeness.rawValue
        self.estimatedSetPremium = estimatedSetPremium
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - LEGACY: Liquidate Brief (immutable AI artifact)

@Model
public final class LiquidationBrief {
    @Attribute(.unique) public var briefId: UUID

    /// Scope of this brief (item vs set). Enforce XOR (item OR set) in creation code.
    public var scopeRaw: String

    /// Recommended path, as returned by AI.
    public var recommendedPathRaw: String

    /// Brief schema version (for future migrations of payload if needed).
    public var briefVersion: Int

    /// Opaque JSON payload containing the structured brief DTO.
    public var payloadJSON: Data

    /// AI provider metadata
    public var aiProvider: String?
    public var aiModel: String?

    public var createdAt: Date

    // Relationship: inverse only defined here (child/to-one side) to avoid circular macro resolution.
    @Relationship(inverse: \LTCItem.liquidationBriefs) public var item: LTCItem?
    @Relationship(inverse: \LTCSet.liquidationBriefs) public var set: LTCSet?

    public var scope: LiquidationScope {
        get { LiquidationScope(rawValue: scopeRaw) ?? .item }
        set { scopeRaw = newValue.rawValue }
    }

    public var recommendedPath: LiquidationPath {
        get { LiquidationPath(rawValue: recommendedPathRaw) ?? .needsInfo }
        set { recommendedPathRaw = newValue.rawValue }
    }

    public init(
        briefId: UUID = UUID(),
        scope: LiquidationScope,
        recommendedPath: LiquidationPath = .needsInfo,
        briefVersion: Int = 1,
        payloadJSON: Data = Data(),
        aiProvider: String? = nil,
        aiModel: String? = nil,
        createdAt: Date = .now
    ) {
        self.briefId = briefId
        self.scopeRaw = scope.rawValue
        self.recommendedPathRaw = recommendedPath.rawValue
        self.briefVersion = briefVersion
        self.payloadJSON = payloadJSON
        self.aiProvider = aiProvider
        self.aiModel = aiModel
        self.createdAt = createdAt
    }
}

// MARK: - LEGACY: Liquidate Plan (mutable user execution state)

@Model
public final class LiquidationPlan {
    @Attribute(.unique) public var planId: UUID

    /// Scope of this plan (item vs set). Enforce XOR (item OR set) in creation code.
    public var scopeRaw: String

    /// The user's chosen path for execution.
    public var chosenPathRaw: String

    public var statusRaw: String

    /// Opaque JSON payload representing checklist state (and any per-plan constraints snapshot).
    public var checklistJSON: Data

    public var userNotes: String?

    public var createdAt: Date
    public var updatedAt: Date

    // Relationship: inverse only defined here (child/to-one side) to avoid circular macro resolution.
    @Relationship(inverse: \LTCItem.liquidationPlan) public var item: LTCItem?
    @Relationship(inverse: \LTCSet.liquidationPlan) public var set: LTCSet?

    public var scope: LiquidationScope {
        get { LiquidationScope(rawValue: scopeRaw) ?? .item }
        set { scopeRaw = newValue.rawValue }
    }

    public var chosenPath: LiquidationPath {
        get { LiquidationPath(rawValue: chosenPathRaw) ?? .needsInfo }
        set { chosenPathRaw = newValue.rawValue }
    }

    public var status: PlanStatus {
        get { PlanStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    public init(
        planId: UUID = UUID(),
        scope: LiquidationScope,
        chosenPath: LiquidationPath,
        status: PlanStatus = .notStarted,
        checklistJSON: Data = Data(),
        userNotes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.planId = planId
        self.scopeRaw = scope.rawValue
        self.chosenPathRaw = chosenPath.rawValue
        self.statusRaw = status.rawValue
        self.checklistJSON = checklistJSON
        self.userNotes = userNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Liquidate: Text-only triage entry (saved inbox)

@Model
public final class TriageEntry {
    @Attribute(.unique) public var triageEntryId: UUID

    /// Raw user-entered text (no photo required).
    public var rawText: String

    /// Opaque JSON inputs (qty, condition, goal, location) for reproducibility.
    public var inputsJSON: Data

    /// Opaque JSON result payload (structured triage output).
    public var resultJSON: Data

    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(inverse: \LTCUser.triageEntries) public var user: LTCUser?

    /// Optional: if user converts this triage entry into a full item.
    public var convertedItem: LTCItem?

    public init(
        triageEntryId: UUID = UUID(),
        rawText: String,
        inputsJSON: Data = Data(),
        resultJSON: Data = Data(),
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.triageEntryId = triageEntryId
        self.rawText = rawText
        self.inputsJSON = inputsJSON
        self.resultJSON = resultJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - ItemValuation

@Model
public final class ItemValuation {
    @Attribute(.unique) public var valuationId: UUID

    public var valueLow: Double?
    public var estimatedValue: Double?
    public var valueHigh: Double?
    public var currencyCode: String
    public var confidenceScore: Double?
    public var valuationDate: Date?
    public var aiProvider: String?
    public var aiNotes: String?

    /// Short prompts describing what additional details would improve accuracy.
    public var missingDetails: [String]

    public var userNotes: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        valuationId: UUID = UUID(),
        valueLow: Double? = nil,
        estimatedValue: Double? = nil,
        valueHigh: Double? = nil,
        currencyCode: String = "USD",
        confidenceScore: Double? = nil,
        valuationDate: Date? = nil,
        aiProvider: String? = nil,
        aiNotes: String? = nil,
        missingDetails: [String] = [],
        userNotes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.valuationId = valuationId
        self.valueLow = valueLow
        self.estimatedValue = estimatedValue
        self.valueHigh = valueHigh
        self.currencyCode = currencyCode
        self.confidenceScore = confidenceScore
        self.valuationDate = valuationDate
        self.aiProvider = aiProvider
        self.aiNotes = aiNotes
        self.missingDetails = missingDetails
        self.userNotes = userNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - ItemImage

@Model
public final class ItemImage {
    @Attribute(.unique) public var imageId: UUID
    public var filePath: String
    public var createdAt: Date

    @Relationship(inverse: \LTCItem.images) public var item: LTCItem?

    public init(
        imageId: UUID = UUID(),
        filePath: String,
        createdAt: Date = .now
    ) {
        self.imageId = imageId
        self.filePath = filePath
        self.createdAt = createdAt
    }
}

// MARK: - AudioRecording

@Model
public final class AudioRecording {
    @Attribute(.unique) public var audioRecordingId: UUID
    public var filePath: String
    public var duration: Double
    public var transcription: String?
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(inverse: \LTCItem.audioRecordings) public var item: LTCItem?

    public init(
        audioRecordingId: UUID = UUID(),
        filePath: String,
        duration: Double,
        transcription: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.audioRecordingId = audioRecordingId
        self.filePath = filePath
        self.duration = duration
        self.transcription = transcription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Document

@Model
public final class Document {
    @Attribute(.unique) public var documentId: UUID
    public var filePath: String
    public var documentType: String
    public var originalFilename: String?
    public var createdAt: Date

    @Relationship(inverse: \LTCItem.documents) public var item: LTCItem?

    public init(
        documentId: UUID = UUID(),
        filePath: String,
        documentType: String,
        originalFilename: String? = nil,
        createdAt: Date = .now
    ) {
        self.documentId = documentId
        self.filePath = filePath
        self.documentType = documentType
        self.originalFilename = originalFilename
        self.createdAt = createdAt
    }
}

// MARK: - Beneficiary

@Model
public final class Beneficiary {
    @Attribute(.unique) public var beneficiaryId: UUID
    public var name: String
    public var relationship: String
    public var email: String?
    public var phoneNumber: String?
    public var contactIdentifier: String?
    public var isLinkedToContact: Bool
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(inverse: \LTCUser.beneficiaries) public var user: LTCUser?
    @Relationship(deleteRule: .cascade) public var itemLinks: [ItemBeneficiary] = []

    public init(
        beneficiaryId: UUID = UUID(),
        name: String,
        relationship: String,
        email: String? = nil,
        phoneNumber: String? = nil,
        contactIdentifier: String? = nil,
        isLinkedToContact: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.beneficiaryId = beneficiaryId
        self.name = name
        self.relationship = relationship
        self.email = email
        self.phoneNumber = phoneNumber
        self.contactIdentifier = contactIdentifier
        self.isLinkedToContact = isLinkedToContact
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - ItemBeneficiary (junction entity)

@Model
public final class ItemBeneficiary {
    @Attribute(.unique) public var itemBeneficiaryId: UUID
    public var accessPermissionRaw: String
    public var accessDate: Date?
    public var personalMessage: String?
    public var notificationStatusRaw: String
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(inverse: \LTCItem.itemBeneficiaries) public var item: LTCItem?
    @Relationship(inverse: \Beneficiary.itemLinks) public var beneficiary: Beneficiary?

    public var accessPermission: AccessPermission {
        get { AccessPermission(rawValue: accessPermissionRaw) ?? .immediate }
        set { accessPermissionRaw = newValue.rawValue }
    }

    public var notificationStatus: NotificationStatus {
        get { NotificationStatus(rawValue: notificationStatusRaw) ?? .notSent }
        set { notificationStatusRaw = newValue.rawValue }
    }

    public init(
        itemBeneficiaryId: UUID = UUID(),
        accessPermission: AccessPermission,
        accessDate: Date? = nil,
        personalMessage: String? = nil,
        notificationStatus: NotificationStatus = .notSent,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.itemBeneficiaryId = itemBeneficiaryId
        self.accessPermissionRaw = accessPermission.rawValue
        self.accessDate = accessDate
        self.personalMessage = personalMessage
        self.notificationStatusRaw = notificationStatus.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Category Helpers

extension LTCItem {
    static let baseCategories: [String] = [
        "Uncategorized",
        "Art",
        "Furniture",
        "Jewelry",
        "Collectibles",
        "Documents",
        "Electronics",
        "Appliance",
        "Rug",
        "China & Crystal",
        "Luxury Personal Items",
        "Clothing",
        "Tools",
        "Luggage",
        "Decor",
        "Other"
    ]
}
