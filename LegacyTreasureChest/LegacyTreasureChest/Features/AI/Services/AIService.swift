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
    /// This is the primary function the AI-assisted views call when a photo exists.
    func analyzeItemPhoto(
        _ image: UIImage,
        hints: ItemAIHints? = nil
    ) async throws -> ItemAnalysis {

        guard featureFlags.enableMarketAI else {
            throw AIError.featureDisabled("Market AI features are currently turned off.")
        }

        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw AIError.imageEncodingFailed
        }

        do {
            return try await provider.analyzeItemPhoto(imageData: data, hints: hints)
        } catch let aiError as AIError {
            throw aiError
        } catch {
            throw AIError.underlying(error)
        }
    }

    /// Analyze an item using only text fields (title/description/category).
    /// This is used when the user has no photo yet.
    func analyzeItemText(
        hints: ItemAIHints
    ) async throws -> ItemAnalysis {

        guard featureFlags.enableMarketAI else {
            throw AIError.featureDisabled("Market AI features are currently turned off.")
        }

        // Require at least something meaningful, otherwise you get junk results.
        let hasSomeText =
            !(hints.userWrittenTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !(hints.userWrittenDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !(hints.knownCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard hasSomeText else {
            throw AIError.invalidResponse("Add at least a title or description before running text-only AI.")
        }

        do {
            return try await provider.analyzeItemText(hints: hints)
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
