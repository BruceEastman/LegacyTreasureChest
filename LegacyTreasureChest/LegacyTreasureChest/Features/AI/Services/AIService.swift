//
//  AIService.swift
//  LegacyTreasureChest
//
//  Provider-agnostic façade used throughout the app.
//  Views should always call AIService rather than the provider directly.
//

import Foundation
import UIKit

@MainActor
final class AIService {

    // MARK: - Singleton

    static let shared = AIService()

    private init(
        // NOTE: Default provider is now BackendAIProvider, which talks to your
        // backend AI gateway. No Gemini key ever lives in the iOS app.
        provider: any AIProvider = BackendAIProvider(),
        featureFlags: FeatureFlags = FeatureFlags()
    ) {
        self.provider = provider
        self.featureFlags = featureFlags
    }

    // MARK: - Internal State

    private let provider: any AIProvider
    private let featureFlags: FeatureFlags

    // MARK: - Public API

    /// Analyze an item photo using AI.
    ///
    /// This is the primary function the AI-assisted views call.
    func analyzeItemPhoto(
        _ image: UIImage,
        hints: ItemAIHints? = nil
    ) async throws -> ItemAnalysis {

        // Feature flag check
        guard featureFlags.enableMarketAI else {
            throw AIError.featureDisabled("Market AI features are currently turned off.")
        }

        // Convert UIImage → JPEG data
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw AIError.imageEncodingFailed
        }

        do {
            let result = try await provider.analyzeItemPhoto(
                imageData: data,
                hints: hints
            )
            return result
        } catch let aiError as AIError {
            throw aiError
        } catch {
            throw AIError.underlying(error)
        }
    }

    /// Estimate a value range for an item.
    func estimateValue(for item: ItemValueInput) async throws -> ValueRange {
        guard featureFlags.enableMarketAI else {
            throw AIError.featureDisabled("Market AI features are currently turned off.")
        }

        do {
            return try await provider.estimateValue(for: item)
        } catch let aiError as AIError {
            throw aiError
        } catch {
            throw AIError.underlying(error)
        }
    }

    /// Ask AI to draft a personal message.
    func draftMessage(
        for input: MessageDraftInput
    ) async throws -> DraftMessageResult {
        guard featureFlags.enableMarketAI else {
            throw AIError.featureDisabled("AI messaging features are currently turned off.")
        }

        do {
            return try await provider.draftPersonalMessage(from: input)
        } catch let aiError as AIError {
            throw aiError
        } catch {
            throw AIError.underlying(error)
        }
    }

    /// Ask AI to suggest beneficiaries.
    func suggestBeneficiaries(
        for input: BeneficiarySuggestionInput
    ) async throws -> [BeneficiarySuggestion] {
        guard featureFlags.enableMarketAI else {
            throw AIError.featureDisabled("AI beneficiary suggestions are currently turned off.")
        }

        do {
            return try await provider.suggestBeneficiaries(from: input)
        } catch let aiError as AIError {
            throw aiError
        } catch {
            throw AIError.underlying(error)
        }
    }

    // MARK: - Convenience for LTCItem

    /// Convert LTCItem to value-estimation context (used later).
    func valueInput(from item: LTCItem) -> ItemValueInput {
        ItemValueInput(
            title: item.name,
            description: item.itemDescription,
            category: item.category,
            originalValue: item.value,
            purchaseYear: Calendar.current.component(.year, from: item.createdAt)
        )
    }
}
