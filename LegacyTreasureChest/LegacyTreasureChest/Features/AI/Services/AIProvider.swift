//
//  AIProvider.swift
//  LegacyTreasureChest
//
//  Provider-agnostic protocol for AI backends (Gemini, OpenAI, etc.).
//

import Foundation

/// Low-level AI provider interface. Concrete implementations (e.g., GeminiProvider)
/// are responsible for performing network calls and translating to/from AIModels.
protocol AIProvider: Sendable {
    // MARK: - Item Photo Analysis

    /// Analyze an item given a photo and optional hints from the user.
    ///
    /// - Parameters:
    ///   - imageData: Encoded image data (JPEG/PNG) suitable for upload.
    ///   - hints: Optional textual hints (existing title/description/category).
    func analyzeItemPhoto(
        imageData: Data,
        hints: ItemAIHints?
    ) async throws -> ItemAnalysis

    // MARK: - Value Estimation

    /// Estimate the resale value range for an item based on its details.
    func estimateValue(
        for item: ItemValueInput
    ) async throws -> ValueRange

    // MARK: - Personal Message Drafting

    /// Draft a personal message to a beneficiary about an item.
    func draftPersonalMessage(
        from input: MessageDraftInput
    ) async throws -> DraftMessageResult

    // MARK: - Beneficiary Suggestions

    /// Suggest which beneficiaries are a good match for a given item.
    func suggestBeneficiaries(
        from input: BeneficiarySuggestionInput
    ) async throws -> [BeneficiarySuggestion]
}
