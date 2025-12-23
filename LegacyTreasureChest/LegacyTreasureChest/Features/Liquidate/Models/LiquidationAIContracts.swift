//
//  LiquidationAIContracts.swift
//  LegacyTreasureChest
//
//  Network contracts (Codable) for Liquidate AI calls.
//  Photo is optional.
//

import Foundation

public struct LiquidationBriefRequest: Codable, Sendable {
    public var schemaVersion: Int

    /// "item" or "set" (mirrors DTO scope)
    public var scope: LiquidationScopeDTO

    /// Text-only core info (always present)
    public var title: String?
    public var description: String?
    public var category: String?
    public var quantity: Int?
    public var unitValue: Double?
    public var currencyCode: String?

    /// Optional value range if you have it
    public var valuationLow: Double?
    public var valuationLikely: Double?
    public var valuationHigh: Double?

    /// Optional photo (base64-encoded JPEG)
    public var photoJpegBase64: String?

    /// Optional set context (for sets or “sell as set” scenarios)
    public var setContext: LiquidationSetContext?

    /// Optional user intent
    public var inputs: LiquidationInputsDTO?

    public init(
        schemaVersion: Int = 1,
        scope: LiquidationScopeDTO,
        title: String? = nil,
        description: String? = nil,
        category: String? = nil,
        quantity: Int? = nil,
        unitValue: Double? = nil,
        currencyCode: String? = "USD",
        valuationLow: Double? = nil,
        valuationLikely: Double? = nil,
        valuationHigh: Double? = nil,
        photoJpegBase64: String? = nil,
        setContext: LiquidationSetContext? = nil,
        inputs: LiquidationInputsDTO? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.scope = scope
        self.title = title
        self.description = description
        self.category = category
        self.quantity = quantity
        self.unitValue = unitValue
        self.currencyCode = currencyCode
        self.valuationLow = valuationLow
        self.valuationLikely = valuationLikely
        self.valuationHigh = valuationHigh
        self.photoJpegBase64 = photoJpegBase64
        self.setContext = setContext
        self.inputs = inputs
    }
}

public struct LiquidationSetContext: Codable, Sendable {
    public var setName: String?
    public var setType: String?
    public var story: String?
    public var sellTogetherPreference: String?
    public var completeness: String?

    /// Minimal summaries of member items (text-only v1; photos later if desired)
    public var memberSummaries: [LiquidationMemberSummary]

    public init(
        setName: String? = nil,
        setType: String? = nil,
        story: String? = nil,
        sellTogetherPreference: String? = nil,
        completeness: String? = nil,
        memberSummaries: [LiquidationMemberSummary] = []
    ) {
        self.setName = setName
        self.setType = setType
        self.story = story
        self.sellTogetherPreference = sellTogetherPreference
        self.completeness = completeness
        self.memberSummaries = memberSummaries
    }
}

public struct LiquidationMemberSummary: Codable, Sendable {
    public var title: String?
    public var category: String?
    public var quantity: Int?
    public var unitValue: Double?

    public init(title: String? = nil, category: String? = nil, quantity: Int? = nil, unitValue: Double? = nil) {
        self.title = title
        self.category = category
        self.quantity = quantity
        self.unitValue = unitValue
    }
}
