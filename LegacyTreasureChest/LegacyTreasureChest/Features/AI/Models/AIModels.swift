//
//  AIModels.swift
//  LegacyTreasureChest
//
//  Provider-agnostic AI models used by AIService and concrete providers.
//  These types are NOT SwiftData models; they are simple value types.
//

import Foundation

// MARK: - AIError

/// Errors specific to the AI layer (separate from AppError).
enum AIError: LocalizedError, Sendable {
    case providerNotConfigured
    case featureDisabled(String)
    case invalidRequest(String)
    case invalidResponse(String)
    case decodingFailed(String)
    case imageEncodingFailed
    case notImplementedYet(String)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured:
            return "AI provider is not configured."
        case .featureDisabled(let message):
            return "AI feature is disabled: \(message)"
        case .invalidRequest(let message):
            return "AI request is invalid: \(message)"
        case .invalidResponse(let message):
            return "Unexpected AI response: \(message)"
        case .decodingFailed(let message):
            return "Failed to decode AI response: \(message)"
        case .imageEncodingFailed:
            return "Unable to encode image data for AI."
        case .notImplementedYet(let message):
            return "AI feature not implemented yet: \(message)"
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - Item Hints

/// Optional hints we can send along with an item photo to guide the model.
/// These come from fields the user may have already entered.
struct ItemAIHints: Codable, Sendable {
    var userWrittenTitle: String?
    var userWrittenDescription: String?
    var knownCategory: String?

    init(
        userWrittenTitle: String? = nil,
        userWrittenDescription: String? = nil,
        knownCategory: String? = nil
    ) {
        self.userWrittenTitle = userWrittenTitle
        self.userWrittenDescription = userWrittenDescription
        self.knownCategory = knownCategory
    }
}

// MARK: - Item Analysis (v2)

/// High-level understanding of an item derived from photos and (optional) text.
/// All enrichment fields are optional so providers can omit them safely.
struct ItemAnalysis: Codable, Sendable {
    // Core summary (used to seed LTCItem fields)
    var title: String
    var summary: String
    var category: String

    // Generic categorization
    var tags: [String]?
    var confidence: Double?

    // Value hints
    var valueHints: ValueRange?

    // Rich, structured details (all optional)
    var extractedText: String?
    var brand: String?
    var modelNumber: String?
    var maker: String?
    var materials: [String]?
    var style: String?
    var origin: String?
    var condition: String?
    var dimensions: String?
    var eraOrYear: String?
    var features: [String]?

    init(
        title: String,
        summary: String,
        category: String,
        tags: [String]? = nil,
        confidence: Double? = nil,
        valueHints: ValueRange? = nil,
        extractedText: String? = nil,
        brand: String? = nil,
        modelNumber: String? = nil,
        maker: String? = nil,
        materials: [String]? = nil,
        style: String? = nil,
        origin: String? = nil,
        condition: String? = nil,
        dimensions: String? = nil,
        eraOrYear: String? = nil,
        features: [String]? = nil
    ) {
        self.title = title
        self.summary = summary
        self.category = category
        self.tags = tags
        self.confidence = confidence
        self.valueHints = valueHints
        self.extractedText = extractedText
        self.brand = brand
        self.modelNumber = modelNumber
        self.maker = maker
        self.materials = materials
        self.style = style
        self.origin = origin
        self.condition = condition
        self.dimensions = dimensions
        self.eraOrYear = eraOrYear
        self.features = features
    }
}

// MARK: - Value Range

/// Represents an estimated monetary range for an item.
struct ValueRange: Codable, Sendable {
    /// Lower bound of the estimate.
    var low: Double

    /// Upper bound of the estimate.
    var high: Double

    /// ISO 4217 currency code (e.g., "USD").
    var currencyCode: String

    /// Optional confidence score in the range [0, 1].
    var confidence: Double?

    /// Short human-readable notes describing how this estimate was derived.
    var sources: [String]

    /// When this estimate was generated (free-form ISO-like string).
    /// We keep this as a String to avoid decode failures from format drift.
    var lastUpdated: String?

    init(
        low: Double,
        high: Double,
        currencyCode: String = "USD",
        confidence: Double? = nil,
        sources: [String] = [],
        lastUpdated: String? = nil
    ) {
        self.low = low
        self.high = high
        self.currencyCode = currencyCode
        self.confidence = confidence
        self.sources = sources
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Item Value Input

/// Flattened, provider-agnostic representation of an item for value estimation.
/// This is created from LTCItem but does not depend on SwiftData.
struct ItemValueInput: Codable, Sendable {
    var title: String
    var description: String
    var category: String
    var originalValue: Double?
    var purchaseYear: Int?

    init(
        title: String,
        description: String,
        category: String,
        originalValue: Double? = nil,
        purchaseYear: Int? = nil
    ) {
        self.title = title
        self.description = description
        self.category = category
        self.originalValue = originalValue
        self.purchaseYear = purchaseYear
    }
}

// MARK: - Message Drafting

/// Context needed to draft a personal message to a beneficiary.
struct MessageDraftInput: Codable, Sendable {
    var itemTitle: String
    var itemDescription: String
    var beneficiaryName: String
    var relationship: String
    /// Optional extra notes from the user about what they want to convey.
    var userNotes: String?

    init(
        itemTitle: String,
        itemDescription: String,
        beneficiaryName: String,
        relationship: String,
        userNotes: String? = nil
    ) {
        self.itemTitle = itemTitle
        self.itemDescription = itemDescription
        self.beneficiaryName = beneficiaryName
        self.relationship = relationship
        self.userNotes = userNotes
    }
}

/// Result of drafting a personal message.
struct DraftMessageResult: Codable, Sendable {
    var message: String
    var rationale: String?

    init(message: String, rationale: String? = nil) {
        self.message = message
        self.rationale = rationale
    }
}

// MARK: - Beneficiary Suggestions

/// Input for suggesting beneficiaries for an item.
struct BeneficiarySuggestionInput: Codable, Sendable {
    struct Candidate: Codable, Sendable {
        var id: UUID?
        var name: String
        var relationship: String

        init(id: UUID? = nil, name: String, relationship: String) {
            self.id = id
            self.name = name
            self.relationship = relationship
        }
    }

    var itemTitle: String
    var itemDescription: String
    var candidates: [Candidate]

    init(
        itemTitle: String,
        itemDescription: String,
        candidates: [Candidate]
    ) {
        self.itemTitle = itemTitle
        self.itemDescription = itemDescription
        self.candidates = candidates
    }
}

/// AI-predicted mapping from an item to a beneficiary with reasoning.
struct BeneficiarySuggestion: Codable, Sendable, Identifiable {
    var id: UUID
    var beneficiaryId: UUID?
    var name: String
    var confidence: Double?
    var reasoning: String

    init(
        id: UUID = UUID(),
        beneficiaryId: UUID? = nil,
        name: String,
        confidence: Double? = nil,
        reasoning: String
    ) {
        self.id = id
        self.beneficiaryId = beneficiaryId
        self.name = name
        self.confidence = confidence
        self.reasoning = reasoning
    }
}
