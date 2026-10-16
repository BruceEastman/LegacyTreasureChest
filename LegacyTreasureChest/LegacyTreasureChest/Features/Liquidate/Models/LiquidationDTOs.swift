//
//  LiquidationDTOs.swift
//  LegacyTreasureChest
//
//  Codable DTOs used by the Liquidate module.
//  These DTOs are encoded/decoded to Data for SwiftData persistence
//  (LiquidationBrief.payloadJSON and LiquidationPlan.checklistJSON).
//

import Foundation

// MARK: - Brief DTO

public struct LiquidationBriefDTO: Codable, Sendable {
    public var schemaVersion: Int
    public var scope: LiquidationScopeDTO

    public var generatedAt: Date
    public var aiProvider: String?
    public var aiModel: String?

    public var recommendedPath: LiquidationPathDTO
    public var reasoning: String

    /// Three primary paths (A/B/C), plus optional donate/needsInfo when applicable.
    public var pathOptions: [LiquidationPathOptionDTO]

    /// Proposed steps to execute (used to seed a user plan).
    public var actionSteps: [String]

    public var missingDetails: [String]
    public var assumptions: [String]

    /// [0,1] confidence score (if your backend provides it)
    public var confidence: Double?

    /// Echo of the user's request context, for transparency/auditing
    public var inputs: LiquidationInputsDTO?

    /// Optional item description for later specialist searches (absent in older Briefs).
    public var specialty: LiquidationSpecialtyDTO?

    public init(
        schemaVersion: Int = 1,
        scope: LiquidationScopeDTO,
        generatedAt: Date = .now,
        aiProvider: String? = nil,
        aiModel: String? = nil,
        recommendedPath: LiquidationPathDTO,
        reasoning: String,
        pathOptions: [LiquidationPathOptionDTO],
        actionSteps: [String],
        missingDetails: [String] = [],
        assumptions: [String] = [],
        confidence: Double? = nil,
        inputs: LiquidationInputsDTO? = nil,
        specialty: LiquidationSpecialtyDTO? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.scope = scope
        self.generatedAt = generatedAt
        self.aiProvider = aiProvider
        self.aiModel = aiModel
        self.recommendedPath = recommendedPath
        self.reasoning = reasoning
        self.pathOptions = pathOptions
        self.actionSteps = actionSteps
        self.missingDetails = missingDetails
        self.assumptions = assumptions
        self.confidence = confidence
        self.inputs = inputs
        self.specialty = specialty
    }
}

public enum LiquidationScopeDTO: String, Codable, Sendable {
    case item
    case set
}

public enum LiquidationPathDTO: String, Codable, Sendable {
    case pathA_maximizePrice
    case pathB_delegateConsign
    case pathC_quickExit
    case donate
    case needsInfo

    /// Customer-facing name (see UserFacingTerms.Liquidation).
    nonisolated public var displayName: String {
        UserFacingTerms.Liquidation.approachName(self)
    }

    /// The persisted app path for this Brief path.
    nonisolated public var appPath: LiquidationPath {
        switch self {
        case .pathA_maximizePrice: return .pathA
        case .pathB_delegateConsign: return .pathB
        case .pathC_quickExit: return .pathC
        case .donate: return .donate
        case .needsInfo: return .needsInfo
        }
    }
}

extension LiquidationPath {
    /// The Brief/Gateway path for this persisted app path.
    nonisolated public var briefPath: LiquidationPathDTO {
        switch self {
        case .pathA: return .pathA_maximizePrice
        case .pathB: return .pathB_delegateConsign
        case .pathC: return .pathC_quickExit
        case .donate: return .donate
        case .needsInfo: return .needsInfo
        }
    }

    /// Customer-facing name (see UserFacingTerms.Liquidation).
    nonisolated public var displayName: String {
        UserFacingTerms.Liquidation.approachName(self)
    }
}

/// Optional description of what kind of item a Brief covers, for later
/// specialist searches. Metadata only; Briefs created before it existed
/// simply have none.
public struct LiquidationSpecialtyDTO: Codable, Sendable, Equatable {
    public var itemKind: String?
    public var detailTerms: [String]
    public var brand: String?
    public var model: String?
    public var isSpecialistItem: Bool

    public init(
        itemKind: String? = nil,
        detailTerms: [String] = [],
        brand: String? = nil,
        model: String? = nil,
        isSpecialistItem: Bool = false
    ) {
        self.itemKind = itemKind
        self.detailTerms = detailTerms
        self.brand = brand
        self.model = model
        self.isSpecialistItem = isSpecialistItem
    }

    private enum CodingKeys: String, CodingKey {
        case itemKind, detailTerms, brand, model, isSpecialistItem
    }

    /// Never fails: a malformed block decodes as empty instead of making the
    /// whole Brief unreadable.
    public init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        self.init(
            itemKind: (try? c.decodeIfPresent(String.self, forKey: .itemKind)) ?? nil,
            detailTerms: ((try? c.decodeIfPresent([String].self, forKey: .detailTerms)) ?? nil) ?? [],
            brand: (try? c.decodeIfPresent(String.self, forKey: .brand)) ?? nil,
            model: (try? c.decodeIfPresent(String.self, forKey: .model)) ?? nil,
            isSpecialistItem: ((try? c.decodeIfPresent(Bool.self, forKey: .isSpecialistItem)) ?? nil) ?? false
        )
    }

    public var isEmpty: Bool {
        (itemKind ?? "").isEmpty && detailTerms.isEmpty && brand == nil && model == nil
    }
}

public struct LiquidationPathOptionDTO: Codable, Sendable, Identifiable {
    public var id: UUID
    public var path: LiquidationPathDTO

    public var label: String
    public var netProceeds: MoneyRangeDTO?

    public var effort: EffortLevelDTO
    public var timeEstimate: String?

    public var risks: [String]
    public var logisticsNotes: String?

    public init(
        id: UUID = UUID(),
        path: LiquidationPathDTO,
        label: String,
        netProceeds: MoneyRangeDTO? = nil,
        effort: EffortLevelDTO,
        timeEstimate: String? = nil,
        risks: [String] = [],
        logisticsNotes: String? = nil
    ) {
        self.id = id
        self.path = path
        self.label = label
        self.netProceeds = netProceeds
        self.effort = effort
        self.timeEstimate = timeEstimate
        self.risks = risks
        self.logisticsNotes = logisticsNotes
    }
}

public enum EffortLevelDTO: String, Codable, Sendable {
    case low
    case medium
    case high
    case veryHigh
}

public struct MoneyRangeDTO: Codable, Sendable, Equatable {
    public var currencyCode: String
    public var low: Double?
    public var likely: Double?
    public var high: Double?

    public init(
        currencyCode: String = "USD",
        low: Double? = nil,
        likely: Double? = nil,
        high: Double? = nil
    ) {
        self.currencyCode = currencyCode
        self.low = low
        self.likely = likely
        self.high = high
    }
}

public struct LiquidationInputsDTO: Codable, Sendable {
    public var goal: LiquidationGoalDTO?
    public var constraints: LiquidationConstraintsDTO?
    public var locationHint: String?

    public init(
        goal: LiquidationGoalDTO? = nil,
        constraints: LiquidationConstraintsDTO? = nil,
        locationHint: String? = nil
    ) {
        self.goal = goal
        self.constraints = constraints
        self.locationHint = locationHint
    }
}

public enum LiquidationGoalDTO: String, Codable, Sendable {
    case maximizeValue
    case minimizeEffort
    case balanced
    case fastestExit
}

public struct LiquidationConstraintsDTO: Codable, Sendable {
    public var localPickupOnly: Bool?
    public var canShip: Bool?
    public var deadline: Date?
    public var notes: String?

    public init(
        localPickupOnly: Bool? = nil,
        canShip: Bool? = nil,
        deadline: Date? = nil,
        notes: String? = nil
    ) {
        self.localPickupOnly = localPickupOnly
        self.canShip = canShip
        self.deadline = deadline
        self.notes = notes
    }
}// MARK: - Plan Checklist DTO

public struct LiquidationPlanChecklistDTO: Codable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var items: [LiquidationChecklistItemDTO]

    // Plan v2 (optional; absent in Plans created by app 1.2)

    /// One sentence: how the Plan carries out the chosen approach.
    public var focus: String?
    /// Who produced the checklist ("gemini", or "local" for the basic offline Plan).
    public var aiProvider: String?
    public var aiModel: String?
    /// The homeowner's choice and the Brief it came from, written by the app.
    public var context: LiquidationPlanContextDTO?
    /// What actually happened, recorded by the homeowner (local only).
    public var outcome: LiquidationPlanOutcomeDTO?
    /// The newer Brief the homeowner chose to keep this Plan with, so the
    /// "based on an earlier Brief" notice is not shown again for it.
    public var keptWithBriefRecordId: UUID?

    public init(
        schemaVersion: Int = 1,
        createdAt: Date = .now,
        items: [LiquidationChecklistItemDTO],
        focus: String? = nil,
        aiProvider: String? = nil,
        aiModel: String? = nil,
        context: LiquidationPlanContextDTO? = nil,
        outcome: LiquidationPlanOutcomeDTO? = nil,
        keptWithBriefRecordId: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.items = items
        self.focus = focus
        self.aiProvider = aiProvider
        self.aiModel = aiModel
        self.context = context
        self.outcome = outcome
        self.keptWithBriefRecordId = keptWithBriefRecordId
    }

    // Every stored field must be listed here AND in init(from:)/encode(to:),
    // or a checkbox toggle (decode, edit, re-encode) silently erases it.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, createdAt, items, focus, aiProvider, aiModel, context
        case outcome, keptWithBriefRecordId
    }

    // Optional v2 fields decode leniently: a bad value is dropped, never the Plan.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.items = try c.decode([LiquidationChecklistItemDTO].self, forKey: .items)
        self.focus = (try? c.decodeIfPresent(String.self, forKey: .focus)) ?? nil
        self.aiProvider = (try? c.decodeIfPresent(String.self, forKey: .aiProvider)) ?? nil
        self.aiModel = (try? c.decodeIfPresent(String.self, forKey: .aiModel)) ?? nil
        self.context = (try? c.decodeIfPresent(LiquidationPlanContextDTO.self, forKey: .context)) ?? nil
        self.outcome = (try? c.decodeIfPresent(LiquidationPlanOutcomeDTO.self, forKey: .outcome)) ?? nil
        self.keptWithBriefRecordId = (try? c.decodeIfPresent(UUID.self, forKey: .keptWithBriefRecordId)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(focus, forKey: .focus)
        try c.encodeIfPresent(aiProvider, forKey: .aiProvider)
        try c.encodeIfPresent(aiModel, forKey: .aiModel)
        try c.encodeIfPresent(context, forKey: .context)
        try c.encodeIfPresent(outcome, forKey: .outcome)
        try c.encodeIfPresent(keptWithBriefRecordId, forKey: .keptWithBriefRecordId)
    }

    /// True when the checklist came from the basic offline generator.
    public var isBasicPlan: Bool {
        context?.generator == LiquidationPlanContextDTO.basicGenerator || aiProvider == "local"
    }
}

public struct LiquidationChecklistItemDTO: Codable, Sendable, Identifiable {
    public var id: UUID
    public var order: Int
    public var text: String
    public var isCompleted: Bool
    public var completedAt: Date?
    public var userNotes: String?

    // Plan v2 (optional)

    /// One short line on why or how.
    public var detail: String?
    /// Hook for opening Find Help from this step ("findHelp" or "findSpecialtyHelp"); not acted on yet.
    public var action: String?
    /// Closet-lot pile: luxury, contemporary, donate, discard, or other.
    public var group: String?

    public init(
        id: UUID = UUID(),
        order: Int,
        text: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        userNotes: String? = nil,
        detail: String? = nil,
        action: String? = nil,
        group: String? = nil
    ) {
        self.id = id
        self.order = order
        self.text = text
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.userNotes = userNotes
        self.detail = detail
        self.action = action
        self.group = group
    }

    // Backend may omit "id" — generate one if missing.
    // Every stored field must be listed here AND in init(from:)/encode(to:),
    // or a checkbox toggle (decode, edit, re-encode) silently erases it.
    private enum CodingKeys: String, CodingKey {
        case id
        case order
        case text
        case isCompleted
        case completedAt
        case userNotes
        case detail
        case action
        case group
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.order = try c.decode(Int.self, forKey: .order)
        self.text = try c.decode(String.self, forKey: .text)
        self.isCompleted = (try? c.decode(Bool.self, forKey: .isCompleted)) ?? false
        self.completedAt = try? c.decode(Date.self, forKey: .completedAt)
        self.userNotes = try? c.decode(String.self, forKey: .userNotes)
        self.detail = try? c.decode(String.self, forKey: .detail)
        self.action = try? c.decode(String.self, forKey: .action)
        self.group = try? c.decode(String.self, forKey: .group)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(order, forKey: .order)
        try c.encode(text, forKey: .text)
        try c.encode(isCompleted, forKey: .isCompleted)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(userNotes, forKey: .userNotes)
        try c.encodeIfPresent(detail, forKey: .detail)
        try c.encodeIfPresent(action, forKey: .action)
        try c.encodeIfPresent(group, forKey: .group)
    }
}

/// What actually happened to the item or Set, as the homeowner reports it.
public enum LiquidationOutcomeResult: String, Codable, CaseIterable, Sendable {
    case sold
    case donated
    case consigned
    case kept
    case didNotSell

    public var displayName: String {
        switch self {
        case .sold: return "Sold"
        case .donated: return "Donated"
        case .consigned: return "Consigned, awaiting sale or payout"
        case .kept: return "Kept"
        case .didNotSell: return "Didn't sell"
        }
    }

    /// Approved mapping: only a finished disposition completes the Plan.
    public var planStatus: PlanStatus {
        switch self {
        case .sold, .donated: return .completed
        case .consigned: return .inProgress
        case .kept, .didNotSell: return .onHold
        }
    }

    /// Whether an amount actually received applies.
    public var recordsAmount: Bool { self == .sold || self == .consigned }

    /// Label for the provider or recipient field, or nil when none applies.
    public var counterpartyLabel: String? {
        switch self {
        case .sold: return "Sold to"
        case .donated: return "Donated to"
        case .consigned: return "Consigned with"
        case .didNotSell: return "Tried with"
        case .kept: return nil
        }
    }
}

/// The homeowner's record of the actual outcome. Amounts are what was really
/// received, never derived from the Brief's estimates. Stored only on device.
public struct LiquidationPlanOutcomeDTO: Codable, Sendable, Equatable {
    public var result: LiquidationOutcomeResult
    public var amountReceived: Double?
    public var currencyCode: String?
    public var counterparty: String?
    public var date: Date
    public var notes: String?
    public var recordedAt: Date
    public var updatedAt: Date

    public init(
        result: LiquidationOutcomeResult,
        amountReceived: Double? = nil,
        currencyCode: String? = nil,
        counterparty: String? = nil,
        date: Date = .now,
        notes: String? = nil,
        recordedAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.result = result
        self.amountReceived = amountReceived
        self.currencyCode = currencyCode
        self.counterparty = counterparty
        self.date = date
        self.notes = notes
        self.recordedAt = recordedAt
        self.updatedAt = updatedAt
    }

    /// A cleaned outcome from the form: amount only where it applies (whole
    /// dollars, never negative), blank text dropped, first-recorded time kept.
    public static func fromForm(
        result: LiquidationOutcomeResult,
        amount: Double?,
        currencyCode: String,
        counterparty: String,
        date: Date,
        notes: String,
        previous: LiquidationPlanOutcomeDTO?,
        now: Date = .now
    ) -> LiquidationPlanOutcomeDTO {
        func clean(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let keptAmount = result.recordsAmount ? amount.map { max($0, 0).rounded() } : nil
        return LiquidationPlanOutcomeDTO(
            result: result,
            amountReceived: keptAmount,
            currencyCode: keptAmount == nil ? nil : currencyCode,
            counterparty: result.counterpartyLabel == nil ? nil : clean(counterparty),
            date: date,
            notes: clean(notes),
            recordedAt: previous?.recordedAt ?? now,
            updatedAt: now
        )
    }
}

/// Plan v2: the homeowner's choice and where it came from, saved inside the Plan
/// JSON so it stays stable even if a later Brief recommends something else.
public struct LiquidationPlanContextDTO: Codable, Sendable, Equatable {
    public static let aiGenerator = "ai"
    public static let basicGenerator = "basic"

    public var schemaVersion: Int
    /// The approach the homeowner chose (never needsInfo).
    public var chosenPath: LiquidationPathDTO?
    /// Name shown when the Plan was created, e.g. "Consignment".
    public var approachName: String
    /// The chosen option's specific recommendation, e.g. "Specialist camera consignment".
    public var specificRecommendation: String?
    /// Whether the chosen approach was the Brief's recommendation.
    public var wasRecommended: Bool
    /// What the Brief recommended (may be needsInfo).
    public var recommendedPath: LiquidationPathDTO?
    /// Created while the Brief still needed more information.
    public var isProvisional: Bool
    public var briefRecordId: UUID?
    public var briefGeneratedAt: Date?
    public var estimatedNet: MoneyRangeDTO?
    public var effort: EffortLevelDTO?
    public var timeEstimate: String?
    public var keyRisks: [String]
    public var specialty: LiquidationSpecialtyDTO?
    /// "ai" or "basic" (offline fallback).
    public var generator: String

    public init(
        schemaVersion: Int = 2,
        chosenPath: LiquidationPathDTO?,
        approachName: String,
        specificRecommendation: String? = nil,
        wasRecommended: Bool,
        recommendedPath: LiquidationPathDTO?,
        isProvisional: Bool,
        briefRecordId: UUID? = nil,
        briefGeneratedAt: Date? = nil,
        estimatedNet: MoneyRangeDTO? = nil,
        effort: EffortLevelDTO? = nil,
        timeEstimate: String? = nil,
        keyRisks: [String] = [],
        specialty: LiquidationSpecialtyDTO? = nil,
        generator: String
    ) {
        self.schemaVersion = schemaVersion
        self.chosenPath = chosenPath
        self.approachName = approachName
        self.specificRecommendation = specificRecommendation
        self.wasRecommended = wasRecommended
        self.recommendedPath = recommendedPath
        self.isProvisional = isProvisional
        self.briefRecordId = briefRecordId
        self.briefGeneratedAt = briefGeneratedAt
        self.estimatedNet = estimatedNet
        self.effort = effort
        self.timeEstimate = timeEstimate
        self.keyRisks = keyRisks
        self.specialty = specialty
        self.generator = generator
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, chosenPath, approachName, specificRecommendation, wasRecommended
        case recommendedPath, isProvisional, briefRecordId, briefGeneratedAt, estimatedNet
        case effort, timeEstimate, keyRisks, specialty, generator
    }

    /// Lenient: unknown or malformed values fall back instead of failing the Plan.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func opt<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }
        let chosen = opt(LiquidationPathDTO.self, .chosenPath)
        self.init(
            schemaVersion: opt(Int.self, .schemaVersion) ?? 2,
            chosenPath: chosen,
            approachName: opt(String.self, .approachName) ?? chosen?.displayName ?? "",
            specificRecommendation: opt(String.self, .specificRecommendation),
            wasRecommended: opt(Bool.self, .wasRecommended) ?? false,
            recommendedPath: opt(LiquidationPathDTO.self, .recommendedPath),
            isProvisional: opt(Bool.self, .isProvisional) ?? false,
            briefRecordId: opt(UUID.self, .briefRecordId),
            briefGeneratedAt: opt(Date.self, .briefGeneratedAt),
            estimatedNet: opt(MoneyRangeDTO.self, .estimatedNet),
            effort: opt(EffortLevelDTO.self, .effort),
            timeEstimate: opt(String.self, .timeEstimate),
            keyRisks: opt([String].self, .keyRisks) ?? [],
            specialty: opt(LiquidationSpecialtyDTO.self, .specialty),
            generator: opt(String.self, .generator) ?? Self.aiGenerator
        )
    }
}

// MARK: - Plan Request DTO

/// Request payload sent from iOS to backend: /ai/generate-liquidation-plan
/// Matches backend LiquidationPlanRequest (Pydantic).
public struct LiquidationPlanRequest: Codable, Sendable {

    /// Schema version for forward compatibility (2 = Plan v2 context included).
    public var schemaVersion: Int

    /// Scope of liquidation (item or set).
    public var scope: LiquidationScopeDTO

    /// Path chosen by the user. Never needsInfo.
    public var chosenPath: LiquidationPathDTO

    /// The previously generated liquidation brief.
    public var brief: LiquidationBriefDTO

    /// Display title (used for checklist phrasing).
    public var title: String

    /// Category context.
    public var category: String

    // Plan v2 (optional)

    /// The full Brief option the homeowner chose, when the Brief has one.
    public var selectedOption: LiquidationPathOptionDTO?
    /// Whether that option was the Brief's recommendation.
    public var isRecommended: Bool?
    /// What LTC already knows about an item (metadata only; no photos or files).
    public var itemContext: LiquidationPlanItemContextDTO?
    /// Set details and member summaries.
    public var setContext: LiquidationSetContext?

    public init(
        schemaVersion: Int = 1,
        scope: LiquidationScopeDTO,
        chosenPath: LiquidationPathDTO,
        brief: LiquidationBriefDTO,
        title: String,
        category: String,
        selectedOption: LiquidationPathOptionDTO? = nil,
        isRecommended: Bool? = nil,
        itemContext: LiquidationPlanItemContextDTO? = nil,
        setContext: LiquidationSetContext? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.scope = scope
        self.chosenPath = chosenPath
        self.brief = brief
        self.title = title
        self.category = category
        self.selectedOption = selectedOption
        self.isRecommended = isRecommended
        self.itemContext = itemContext
        self.setContext = setContext
    }
}

/// Plan v2: what LTC already has for an item. Counts and document types only;
/// photos, files, and audio are never sent for Plan generation.
public struct LiquidationPlanItemContextDTO: Codable, Sendable, Equatable {
    public var description: String?
    public var quantity: Int?
    public var unitValue: Double?
    public var currencyCode: String?
    public var valuationLow: Double?
    public var valuationHigh: Double?
    public var valuationNotes: String?
    public var photoCount: Int?
    public var documentCount: Int?
    public var documentTypes: [String]
    public var hasAudioStory: Bool?

    public init(
        description: String? = nil,
        quantity: Int? = nil,
        unitValue: Double? = nil,
        currencyCode: String? = nil,
        valuationLow: Double? = nil,
        valuationHigh: Double? = nil,
        valuationNotes: String? = nil,
        photoCount: Int? = nil,
        documentCount: Int? = nil,
        documentTypes: [String] = [],
        hasAudioStory: Bool? = nil
    ) {
        self.description = description
        self.quantity = quantity
        self.unitValue = unitValue
        self.currencyCode = currencyCode
        self.valuationLow = valuationLow
        self.valuationHigh = valuationHigh
        self.valuationNotes = valuationNotes
        self.photoCount = photoCount
        self.documentCount = documentCount
        self.documentTypes = documentTypes
        self.hasAudioStory = hasAudioStory
    }
}


// MARK: - Text-only Triage DTO

public struct TextTriageResultDTO: Codable, Sendable {
    public var recommendation: TextTriageRecommendationDTO
    public var confidence: Double?
    public var rationaleBullets: [String]
    public var nextSteps: [String]

    public var netProceeds: MoneyRangeDTO?
    public var effort: EffortLevelDTO?

    public var followUpQuestions: [String]?
    public var suggestedSearchTerms: [String]?

    public init(
        recommendation: TextTriageRecommendationDTO,
        confidence: Double? = nil,
        rationaleBullets: [String] = [],
        nextSteps: [String] = [],
        netProceeds: MoneyRangeDTO? = nil,
        effort: EffortLevelDTO? = nil,
        followUpQuestions: [String]? = nil,
        suggestedSearchTerms: [String]? = nil
    ) {
        self.recommendation = recommendation
        self.confidence = confidence
        self.rationaleBullets = rationaleBullets
        self.nextSteps = nextSteps
        self.netProceeds = netProceeds
        self.effort = effort
        self.followUpQuestions = followUpQuestions
        self.suggestedSearchTerms = suggestedSearchTerms
    }
}

public enum TextTriageRecommendationDTO: String, Codable, Sendable {
    case donate
    case sellLocalBundle
    case sellOnline
    case consign
    case researchNeeded
}
