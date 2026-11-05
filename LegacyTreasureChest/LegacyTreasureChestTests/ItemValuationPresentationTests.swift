//
//  ItemValuationPresentationTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 2: what Item Detail shows for a value. AI estimate vs owner value,
//  per-unit value and total, explanation and suggestions. Display only.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

@MainActor
struct ItemValuationPresentationTests {

    private func makeItem(value: Double = 0, quantity: Int = 1) throws -> (LTCItem, ModelContext) {
        let container = try ModelContainer(for: LTCItem.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let item = LTCItem(name: "Sample", itemDescription: "", category: "Furniture", value: value, quantity: quantity)
        context.insert(item)
        return (item, context)
    }

    private func aiValuation(low: Double?, est: Double?, high: Double?, confidence: Double? = 0.7,
                             notes: String? = "Based on similar stools.",
                             missing: [String] = ["Seat height", "Photos of all stools", "Maker mark", "Receipt"]) -> ItemValuation {
        ItemValuation(valueLow: low, estimatedValue: est, valueHigh: high, confidenceScore: confidence,
                      aiProvider: "gemini-3.6-flash", aiNotes: notes, missingDetails: missing)
    }

    @Test func noValueAndNoAI() throws {
        let (item, _) = try makeItem()
        let p = ItemValuationPresentation(item: item)
        #expect(p.source == .none)
        #expect(p.unitValue == nil)
        #expect(p.totalValue == nil)
        #expect(p.aiUnitEstimate == nil)
        #expect(p.sourceCaption == "Not estimated yet")
    }

    @Test func manualValueShowsNoInventedRangeOrExplanation() throws {
        let (item, _) = try makeItem(value: 250)
        let p = ItemValuationPresentation(item: item)
        #expect(p.source == .manual)
        #expect(p.sourceCaption == "Entered by you")
        #expect(p.aiLow == nil && p.aiHigh == nil && p.aiUnitEstimate == nil)
        #expect(p.explanation == nil)
        #expect(p.suggestions.isEmpty)
        #expect(p.confidenceLabel == nil)
    }

    @Test func ownerNotesOnlyValuationIsNotAnAIResult() throws {
        // ItemValuation is created just to hold More Details notes.
        let (item, _) = try makeItem(value: 120)
        item.valuation = ItemValuation(userNotes: "Bought in 1998.")
        let p = ItemValuationPresentation(item: item)
        #expect(p.source == .manual)
        #expect(p.aiUnitEstimate == nil)
    }

    @Test func aiEstimateWithQuantityShowsUnitRangeAndTotal() throws {
        let (item, _) = try makeItem(value: 350, quantity: 4)
        item.valuation = aiValuation(low: 200, est: 350, high: 500)
        let p = ItemValuationPresentation(item: item)
        #expect(p.source == .aiEstimate)
        #expect(p.sourceCaption == "AI estimate")
        #expect(p.unitValue == 350)
        #expect(p.totalValue == 1400)
        #expect(p.hasRange)
        #expect(p.aiLow == 200 && p.aiHigh == 500)
        #expect(p.confidenceLabel == "Medium")
        #expect(p.explanation == "Based on similar stools.")
        #expect(p.suggestions == ["Seat height", "Photos of all stools", "Maker mark"])   // at most 3
    }

    @Test func quantityOneHasNoTotal() throws {
        let (item, _) = try makeItem(value: 350, quantity: 1)
        item.valuation = aiValuation(low: 200, est: 350, high: 500)
        #expect(ItemValuationPresentation(item: item).totalValue == nil)
    }

    @Test func ownerChangedValueAfterAI() throws {
        let (item, _) = try makeItem(value: 450, quantity: 2)
        item.valuation = aiValuation(low: 200, est: 350, high: 500)
        let p = ItemValuationPresentation(item: item)
        #expect(p.source == .ownerOverride)
        #expect(p.sourceCaption == "Entered by you")
        #expect(p.unitValue == 450)
        #expect(p.totalValue == 900)
        #expect(p.aiUnitEstimate == 350)
    }

    @Test func midpointFromRangeMatchesApply() throws {
        // Apply writes (low + high) / 2 when no estimatedValue is returned.
        let (item, _) = try makeItem(value: 300)
        item.valuation = aiValuation(low: 200, est: nil, high: 400)
        let p = ItemValuationPresentation(item: item)
        #expect(p.source == .aiEstimate)
        #expect(p.aiUnitEstimate == 300)
    }

    @Test func aiCouldNotEstimate() throws {
        let (item, _) = try makeItem(value: 0)
        item.valuation = aiValuation(low: nil, est: nil, high: nil, confidence: 0.15,
                                     notes: "Not estimated. Add the maker.", missing: ["Maker"])
        let p = ItemValuationPresentation(item: item)
        #expect(p.source == .aiNotEstimated)
        #expect(p.sourceCaption == "AI could not estimate yet")
        #expect(p.unitValue == nil)
        #expect(p.confidenceLabel == nil)
        #expect(p.explanation == "Not estimated. Add the maker.")
        #expect(p.suggestions == ["Maker"])
    }

    @Test func explicitZeroAIEstimateIsAnAIEstimate() throws {
        let (item, _) = try makeItem(value: 0)
        item.valuation = aiValuation(low: 0, est: 0, high: 0)
        let p = ItemValuationPresentation(item: item)
        #expect(p.unitValue == 0)
        #expect(p.source == .aiEstimate)
        #expect(!p.hasRange)
    }
}
