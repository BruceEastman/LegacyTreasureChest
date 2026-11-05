//
//  ValuationBasisTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 4: LTC establishes what the AI's estimate covers. Per-unit
//  estimates are shown as is; a group estimate whose size matches the quantity
//  is allocated equally per unit; anything else is not applied. Synthetic data.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

private func analysis(unit: String?, low: Double? = 600, estimate: Double? = 800, high: Double? = 1000,
                      notes: String? = "Synthetic AI notes.") -> ItemAnalysis {
    ItemAnalysis(title: "Synthetic stools", summary: "Synthetic summary.", category: "Furniture",
                 valueHints: ValueHints(valueLow: low, estimatedValue: estimate, valueHigh: high,
                                        confidenceScore: 0.6, aiNotes: notes, missingDetails: ["Seat height"]),
                 valuationUnit: unit)
}

private func review(quantity: Int, unit: String?, low: Double? = 600, estimate: Double? = 800,
                    high: Double? = 1000, currentValue: Double? = 90) -> ItemAnalysisReview {
    ItemAnalysisReview(currentTitle: "Stools", currentCategory: "Furniture", currentDescription: "",
                       llmGeneratedDescription: nil, quantity: quantity, currentUnitValue: currentValue,
                       analysis: analysis(unit: unit, low: low, estimate: estimate, high: high),
                       includedDocument: false)
}

// MARK: - Basis

struct ValuationBasisClassificationTests {

    @Test func unitDescriptions() {
        typealias R = ItemAnalysisReview
        #expect(R.valuationBasis(quantity: 4, unit: "one stool") == .perUnit)
        #expect(R.valuationBasis(quantity: 4, unit: "each stool") == .perUnit)
        #expect(R.valuationBasis(quantity: 4, unit: "per item") == .perUnit)
        #expect(R.valuationBasis(quantity: 4, unit: "stool") == .perUnit)
        #expect(R.valuationBasis(quantity: 4, unit: "one of four stools") == .perUnit)
        #expect(R.valuationBasis(quantity: 4, unit: "set of four stools") == .group(size: 4))
        #expect(R.valuationBasis(quantity: 4, unit: "4 stools") == .group(size: 4))
        #expect(R.valuationBasis(quantity: 4, unit: "all 4 chairs") == .group(size: 4))
        #expect(R.valuationBasis(quantity: 2, unit: "pair of nightstands") == .group(size: 2))
        #expect(R.valuationBasis(quantity: 4, unit: "set of six chairs") == .ambiguous(.conflictingCount(6)))
        #expect(R.valuationBasis(quantity: 4, unit: "the complete set") == .ambiguous(.unclearGroup))
        #expect(R.valuationBasis(quantity: 4, unit: nil) == .ambiguous(.unstated))
        #expect(R.valuationBasis(quantity: 4, unit: "  ") == .ambiguous(.unstated))
    }

    @Test func quantityOneIsAlwaysTheWholeCatalogEntry() {
        typealias R = ItemAnalysisReview
        #expect(R.valuationBasis(quantity: 1, unit: "complete 10-place-setting service") == .perUnit)
        #expect(R.valuationBasis(quantity: 1, unit: "set of four chairs") == .perUnit)
        #expect(R.valuationBasis(quantity: 1, unit: nil) == .perUnit)
    }
}

// MARK: - Presentation and defaults

struct ValuationBasisReviewTests {

    @Test func perUnitEstimateAtQuantityFour() {
        let r = review(quantity: 4, unit: "one stool", low: 200, estimate: 300, high: 400)
        #expect(r.valuation.basis == .perUnit)
        #expect(r.valuation.proposedLow == 200 && r.valuation.proposedEstimate == 300 && r.valuation.proposedHigh == 400)
        #expect(r.valuation.proposedTotal == 1200)
        #expect(r.defaults.valuation)
        #expect(r.valueHintsToApply?.estimatedValue == 300)
        #expect(r.valueHintsToApply?.aiNotes == "Synthetic AI notes.")     // unchanged
        #expect(!r.warnings.contains(.groupAllocation(quantity: 4)))
    }

    @Test func groupEstimateIsAllocatedAcrossFour() {
        let r = review(quantity: 4, unit: "set of four stools")
        #expect(r.valuation.basis == .group(size: 4))
        #expect(r.valuation.aiLow == 600 && r.valuation.aiEstimate == 800 && r.valuation.aiHigh == 1000)
        #expect(r.valuation.proposedLow == 150)
        #expect(r.valuation.proposedEstimate == 200)
        #expect(r.valuation.proposedHigh == 250)
        #expect(r.valuation.proposedTotal == 800)                 // not 800 × 4
        #expect(!r.defaults.valuation)                            // deliberate selection
        #expect(r.valuation.canApply && !r.hasUnitWarning)
        #expect(r.warnings.contains(.groupAllocation(quantity: 4)))
    }

    @Test func groupRangeAndMidpointStayConsistent() {
        // The AI gave only a range: the midpoint is computed, then allocated.
        let r = review(quantity: 4, unit: "4 stools", low: 600, estimate: nil, high: 1000)
        let v = r.valuation
        #expect(v.aiEstimate == 800)
        #expect(v.proposedEstimate == 200)
        #expect(v.proposedEstimate == ((v.proposedLow ?? 0) + (v.proposedHigh ?? 0)) / 2)
        #expect(v.proposedTotal == v.aiEstimate)
        let hints = r.valueHintsToApply
        #expect(hints?.valueLow == 150 && hints?.valueHigh == 250 && hints?.estimatedValue == 200)
    }

    @Test func quantityOneServiceIsPreselectedAsIs() {
        let r = review(quantity: 1, unit: "complete 10-place-setting service", low: 200, estimate: 300, high: 450)
        #expect(r.valuation.basis == .perUnit)
        #expect(r.defaults.valuation)
        #expect(r.valuation.proposedEstimate == 300)
        #expect(r.valuation.proposedTotal == nil)
    }

    @Test func missingOrContradictoryUnitsCannotBeApplied() {
        for unit in [nil, "set of six chairs", "the complete set"] as [String?] {
            let r = review(quantity: 4, unit: unit)
            #expect(r.valuation.isAmbiguous)
            #expect(!r.valuation.canApply)
            #expect(r.valuation.proposedEstimate == nil && r.valuation.proposedTotal == nil)
            #expect(r.valueHintsToApply == nil)
            #expect(!r.defaults.valuation)
            #expect(r.hasUnitWarning)
            #expect(r.warnings.contains(.valuationUnclear(quantity: 4, unit: unit)))
        }
    }

    @Test func largeChangeWarningUsesThePerUnitFigure() {
        // $200 allocated vs $90 current is not a 3× change; $800 would have been.
        let r = review(quantity: 4, unit: "set of four stools", currentValue: 90)
        #expect(!r.warnings.contains { if case .largeValueChange = $0 { return true } else { return false } })
    }
}

// MARK: - Applying through the review model

@MainActor
@Suite(.serialized)
struct ValuationBasisApplyTests {

    private func reviewing(unit: String?, quantity: Int = 4) async throws -> (ImproveWithAIModel, LTCItem, ModelContext) {
        let context = ModelContext(try ModelContainer(for: LTCItem.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let item = LTCItem(name: "Synthetic stools", itemDescription: "Owner text.", category: "Furniture",
                           value: 90, quantity: quantity)
        item.valuation = ItemValuation(valueLow: 70, estimatedValue: 90, valueHigh: 110, confidenceScore: 0.3,
                                       aiNotes: "Earlier notes.", missingDetails: ["Maker"], userNotes: "Owner notes.")
        item.suggestedPriceNew = 110
        item.suggestedPriceUsed = 70
        context.insert(item)
        let model = ImproveWithAIModel(item: item, analyzer: { _ in analysis(unit: unit) })
        model.startAnalysis()
        for _ in 0..<200 {
            if case .review = model.phase { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard case .review = model.phase else { throw CancellationError() }
        return (model, item, context)
    }

    private func expectUnchanged(_ item: LTCItem) {
        #expect(item.value == 90 && item.estimatedTotalValue == 360)
        #expect(item.suggestedPriceNew == 110 && item.suggestedPriceUsed == 70)
        #expect(item.valuation?.valueLow == 70 && item.valuation?.estimatedValue == 90 && item.valuation?.valueHigh == 110)
        #expect(item.valuation?.confidenceScore == 0.3 && item.valuation?.aiNotes == "Earlier notes.")
        #expect(item.valuation?.missingDetails == ["Maker"])
        #expect(item.valuation?.userNotes == "Owner notes.")
    }

    @Test func declinedGroupValuationLeavesEverythingUnchanged() async throws {
        let (model, item, _) = try await reviewing(unit: "set of four stools")
        #expect(!model.choices.valuation)              // default off
        #expect(model.apply())
        expectUnchanged(item)
    }

    @Test func acceptedAllocationStoresPerUnitFiguresAndGroupBasis() async throws {
        let (model, item, _) = try await reviewing(unit: "set of four stools")
        model.choices = ItemAnalysisApplier.Choices()
        model.choices.valuation = true
        #expect(model.apply())

        #expect(item.value == 200)
        #expect(item.estimatedTotalValue == 800)
        #expect(item.suggestedPriceNew == 250 && item.suggestedPriceUsed == 150)
        let v = try #require(item.valuation)
        #expect(v.valueLow == 150 && v.estimatedValue == 200 && v.valueHigh == 250)
        #expect(v.confidenceScore == 0.6)
        let notes = v.aiNotes ?? ""
        #expect(notes.contains("all 4 together at $600–$1,000 (midpoint $800)"))
        #expect(notes.contains("$150–$250 per item (midpoint $200)"))
        #expect(notes.contains("allocation, not a separately established selling price"))
        #expect(notes.hasSuffix("Synthetic AI notes."))
        #expect(v.userNotes == "Owner notes.")
        #expect(item.itemDescription == "Owner text.")
    }

    @Test func ambiguousValuationIsNeverApplied() async throws {
        for unit in [nil, "set of six chairs"] as [String?] {
            let (model, item, _) = try await reviewing(unit: unit)
            model.choices.valuation = true                 // even if forced on
            #expect(model.apply())
            expectUnchanged(item)
        }
    }

    @Test func perUnitEstimateAppliesAsReturned() async throws {
        let (model, item, _) = try await reviewing(unit: "one stool")
        #expect(model.choices.valuation)
        #expect(model.apply())
        #expect(item.value == 800 && item.estimatedTotalValue == 3200)
        #expect(item.valuation?.aiNotes == "Synthetic AI notes.")
    }
}
