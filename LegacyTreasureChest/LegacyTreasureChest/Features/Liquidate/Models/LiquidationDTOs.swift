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
        inputs: LiquidationInputsDTO? = nil
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

public struct MoneyRangeDTO: Codable, Sendable {
    public var currencyCode: String
    public var low: Double?
    public var likely: Double?
    public var high: Double?

    public init(currencyCode: String = "USD", low: Double? = nil, likely: Double? = nil, high: Double? = nil) {
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

    public init(goal: LiquidationGoalDTO? = nil, constraints: LiquidationConstraintsDTO? = nil, locationHint: String? = nil) {
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

    public init(localPickupOnly: Bool? = nil, canShip: Bool? = nil, deadline: Date? = nil, notes: String? = nil) {
        self.localPickupOnly = localPickupOnly
        self.canShip = canShip
        self.deadline = deadline
        self.notes = notes
    }
}

// MARK: - Plan Checklist DTO

public struct LiquidationPlanChecklistDTO: Codable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date

    /// The steps the user is executing (seeded from brief).
    public var items: [LiquidationChecklistItemDTO]

    public init(schemaVersion: Int = 1, createdAt: Date = .now, items: [LiquidationChecklistItemDTO]) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.items = items
    }
}

public struct LiquidationChecklistItemDTO: Codable, Sendable, Identifiable {
    public var id: UUID
    public var order: Int
    public var text: String
    public var isCompleted: Bool
    public var completedAt: Date?
    public var userNotes: String?

    public init(
        id: UUID = UUID(),
        order: Int,
        text: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        userNotes: String? = nil
    ) {
        self.id = id
        self.order = order
        self.text = text
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.userNotes = userNotes
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

    /// Only when recommendation == researchNeeded
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
