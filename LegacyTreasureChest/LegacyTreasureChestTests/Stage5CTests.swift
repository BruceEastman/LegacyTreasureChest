//
//  Stage5CTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 5C: quantity-one group prices and accessibility labels. Synthetic data.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

@MainActor
private func item(name: String, description: String = "", notes: String? = nil, quantity: Int = 1,
                  value: Double = 0) throws -> (LTCItem, ModelContext) {
    let context = ModelContext(try ModelContainer(for: LTCItem.self,
                                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    let item = LTCItem(name: name, itemDescription: description, category: "Furniture", value: value, quantity: quantity)
    if let notes { item.valuation = ItemValuation(userNotes: notes) }
    context.insert(item)
    return (item, context)
}

private func analysis(unit: String?, estimate: Double = 900) -> ItemAnalysis {
    ItemAnalysis(title: "Suggested", summary: "Suggested paragraph.", category: "Furniture",
                 valueHints: ValueHints(valueLow: estimate * 0.75, estimatedValue: estimate, valueHigh: estimate * 1.25,
                                        confidenceScore: 0.5, aiNotes: "Synthetic."),
                 valuationUnit: unit)
}

@MainActor
struct QuantityOneGroupPriceTests {

    typealias R = ItemAnalysisReview

    @Test func unitsThatNameAGroup() {
        for u in ["set of six chairs", "set of 6 chairs", "pair of lamps", "4 stools", "six chairs",
                  "collection of figurines", "lot of books", "matching set", "bedroom suite"] {
            #expect(R.unitNamesGroup(u), "\(u)")
        }
        for u in [nil, "", "one bible", "one bed frame", "each", "one complete china service", "single chair",
                  "complete 10-place-setting service"] as [String?] {
            #expect(!R.unitNamesGroup(u), "\(String(describing: u))")
        }
    }

    @Test func ownerTextThatDescribesASet() {
        for t in ["Complete china service — 10 place settings", "Dining chairs, set of 6", "Pair of lamps",
                  "Six chairs", "China place setting 10 place settings", "Matching nightstands", "4 bar stools"] {
            #expect(R.itemTextDescribesSet(t), "\(t)")
        }
        for t in ["Family Bible", "Four-poster bed", "Old brass lamp", "Made in 1890.", "Dining chairs",
                  "Grandpa's chair, bought in 1952", ""] {
            #expect(!R.itemTextDescribesSet(t), "\(t)")
        }
    }

    @Test func groupPriceForOneObjectIsFlaggedAndNotPreselected() throws {
        // Stage 5A finding f: a stub answer priced "set of six chairs" for a single Family Bible.
        let (bible, _) = try item(name: "Family Bible")
        let r = ItemAnalysisReview(item: bible, analysis: analysis(unit: "set of six chairs"), includedDocument: false)
        #expect(r.valuation.basis == .perUnit)               // the approved quantity-1 rule is unchanged
        #expect(r.valuation.canApply)                        // the owner may still choose it
        #expect(!r.defaults.valuation)                       // but it is never applied silently
        #expect(r.warnings.contains(.singleItemGroupPrice(unit: "set of six chairs")))
    }

    @Test func narrativeDescriptionDoesNotMakeAnItemASet() throws {
        // The sample Family Bible's description says "passed down through four generations".
        let (bible, _) = try item(name: "Family Bible (SAMPLE)",
                                  description: "Leather-bound family bible passed down through four generations.")
        let r = ItemAnalysisReview(item: bible, analysis: analysis(unit: "set of six chairs"), includedDocument: false)
        #expect(!r.defaults.valuation)
        #expect(r.warnings.contains(.singleItemGroupPrice(unit: "set of six chairs")))
    }

    @Test func ownerCanStillApplyTheFlaggedEstimate() throws {
        let (bible, _) = try item(name: "Family Bible", value: 120)
        let proposal = analysis(unit: "set of six chairs")
        var choices = ItemAnalysisReview(item: bible, analysis: proposal, includedDocument: false).defaults
        ItemAnalysisApplier.apply(proposal, to: bible, choices: choices)
        #expect(bible.value == 120)                          // defaults keep the owner's value
        choices.valuation = true
        ItemAnalysisApplier.apply(proposal, to: bible, choices: choices)
        #expect(bible.value == 900)
    }

    @Test func genuineSetsCatalogedAsOneItemAreUnchanged() throws {
        let cases: [(String, String?, String)] = [
            ("Complete china service — 10 place settings", nil, "complete 10-place-setting service"),
            ("China place setting", "10 place settings", "set of 10 place settings"),
            ("Dining chairs, set of 6", nil, "set of six chairs"),
            ("Pair of brass candlesticks", nil, "pair of candlesticks"),
        ]
        for (name, notes, unit) in cases {
            let (it, _) = try item(name: name, notes: notes)
            let r = ItemAnalysisReview(item: it, analysis: analysis(unit: unit), includedDocument: false)
            #expect(r.defaults.valuation, "\(name)")
            #expect(!r.warnings.contains(.singleItemGroupPrice(unit: unit)), "\(name)")
        }
    }

    @Test func singleObjectWithSingleUnitIsUnchanged() throws {
        let (bed, _) = try item(name: "Four-poster bed", notes: "Made in 1890.")
        let r = ItemAnalysisReview(item: bed, analysis: analysis(unit: "one bed frame"), includedDocument: false)
        #expect(r.defaults.valuation)
        #expect(r.warnings.isEmpty)
    }

    @Test func quantityAboveOneRulesAreUnchanged() throws {
        let (stools, _) = try item(name: "Bar stools", quantity: 4)
        let perUnit = ItemAnalysisReview(item: stools, analysis: analysis(unit: "one stool", estimate: 75), includedDocument: false)
        #expect(perUnit.valuation.basis == .perUnit && perUnit.defaults.valuation && perUnit.valuation.proposedTotal == 300)
        let group = ItemAnalysisReview(item: stools, analysis: analysis(unit: "set of four stools", estimate: 300), includedDocument: false)
        #expect(group.valuation.basis == .group(size: 4) && !group.defaults.valuation)
        #expect(!group.warnings.contains { if case .singleItemGroupPrice = $0 { return true }; return false })
    }

    @Test func noEstimateMeansNoFlag() throws {
        let (bible, _) = try item(name: "Family Bible")
        let none = ItemAnalysis(title: "t", summary: "s", category: "Books",
                                valueHints: ValueHints(valueLow: nil, estimatedValue: nil, valueHigh: nil),
                                valuationUnit: "set of six chairs")
        let r = ItemAnalysisReview(item: bible, analysis: none, includedDocument: false)
        #expect(r.warnings.isEmpty)
    }
}

struct Stage5CAccessibilityLabelTests {

    @Test func photoTilesHaveOrdinals() {
        #expect(ItemAIAnalysisSheet.photoAccessibilityLabel(position: 1, of: 3, selected: true)
                == "Additional photo 1 of 3, selected")
        #expect(ItemAIAnalysisSheet.photoAccessibilityLabel(position: 3, of: 3, selected: false)
                == "Additional photo 3 of 3, not selected")
    }

    @Test func documentRowsReadTheFullNameTypeAndPages() {
        let long = "Synthetic_Furniture_Appraisal_12_pages_SYNTHETIC.pdf"
        #expect(ItemAIAnalysisSheet.documentAccessibilityLabel(name: long, type: "PDF", pages: 12, selected: false)
                == "\(long), PDF, 12 pages, not selected")
        #expect(ItemAIAnalysisSheet.documentAccessibilityLabel(name: "receipt.jpg", type: "IMAGE", pages: nil, selected: true)
                == "receipt.jpg, Image, selected")
        #expect(ItemAIAnalysisSheet.documentAccessibilityLabel(name: "a.pdf", type: "pdf", pages: 1, selected: true)
                == "a.pdf, PDF, 1 page, selected")
    }
}
