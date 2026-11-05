//
//  ImproveWithAIReviewTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 4: review defaults, warnings and selective apply. Synthetic data.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

private func proposal(
    title: String = "Sample Maker Co. Counter Stool",
    summary: String = "Counter stool with a cutout back.",
    category: String = "Furniture",
    hints: ValueHints? = ValueHints(valueLow: 200, estimatedValue: 300, valueHigh: 400, confidenceScore: 0.7, aiNotes: "AI notes."),
    brand: String? = nil, materials: [String]? = nil, dimensions: String? = nil,
    unit: String? = "one stool", conflicts: [String]? = nil
) -> ItemAnalysis {
    ItemAnalysis(title: title, summary: summary, category: category, valueHints: hints,
                 brand: brand, materials: materials, dimensions: dimensions,
                 valuationUnit: unit, conflicts: conflicts)
}

@MainActor
private func makeItem(name: String = "Stools", description: String = "", llm: String? = nil,
                      category: String = "Furniture", value: Double = 0, quantity: Int = 1) throws -> (LTCItem, ModelContext) {
    let context = ModelContext(try ModelContainer(for: LTCItem.self,
                                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    let item = LTCItem(name: name, itemDescription: description, category: category, value: value, quantity: quantity)
    item.llmGeneratedDescription = llm
    context.insert(item)
    return (item, context)
}

// MARK: - Review defaults and warnings

@MainActor
struct ImproveWithAIReviewDefaultsTests {

    @Test func ownerWrittenAndMixedDescriptionsAreKeptByDefault() throws {
        let (owner, _) = try makeItem(description: "Grandma's stools.")
        #expect(ItemAnalysisReview(item: owner, analysis: proposal(), includedDocument: false).defaults.paragraph == .keep)

        let (mixed, _) = try makeItem(description: "Old AI text, edited.", llm: "Old AI text.")
        let review = ItemAnalysisReview(item: mixed, analysis: proposal(), includedDocument: false)
        #expect(review.defaults.paragraph == .keep)
        #expect(review.paragraphReplacesOwnerText)
    }

    @Test func emptyOrEarlierAIDescriptionDefaultsToNewParagraph() throws {
        let (empty, _) = try makeItem()
        #expect(ItemAnalysisReview(item: empty, analysis: proposal(), includedDocument: false).defaults.paragraph == .useAI)
        let (ai, _) = try makeItem(description: "Old AI text.", llm: "Old AI text.")
        #expect(ItemAnalysisReview(item: ai, analysis: proposal(), includedDocument: false).defaults.paragraph == .useAI)
    }

    @Test func attributeRowsNewSelectedChangedNotSelected() throws {
        let (item, _) = try makeItem(description: "Old AI.\n\nBrand: Old Co • Materials: oak", llm: "Old AI.")
        let review = ItemAnalysisReview(item: item, analysis: proposal(brand: "Old Co", materials: ["cherry"], dimensions: "24 in"),
                                        includedDocument: false)
        let kinds = Dictionary(uniqueKeysWithValues: review.attributes.map { ($0.label, $0.kind) })
        #expect(kinds == ["Brand": .same, "Materials": .changed, "Dimensions": .new])
        #expect(review.defaults.attributeLabels == ["Dimensions"])
    }

    @Test func documentAnalysisPreselectsNoText() throws {
        let (item, _) = try makeItem(name: "Pendant", category: "Uncategorized")
        let review = ItemAnalysisReview(item: item, analysis: proposal(brand: "X", unit: "one pendant"), includedDocument: true)
        #expect(!review.defaults.title)
        #expect(review.defaults.paragraph == .keep)
        #expect(review.defaults.attributeLabels.isEmpty)
        #expect(review.defaults.valuation)          // value is not document text
        #expect(review.warnings.contains(.documentDerived))
    }

    @Test func valuationBasisDefaults() throws {
        let (four, _) = try makeItem(quantity: 4)
        // A set priced as a whole is allocated, but not preselected.
        let setReview = ItemAnalysisReview(item: four, analysis: proposal(unit: "set of four stools"), includedDocument: false)
        #expect(setReview.valuation.basis == .group(size: 4))
        #expect(!setReview.hasUnitWarning)
        #expect(!setReview.defaults.valuation)

        let oneReview = ItemAnalysisReview(item: four, analysis: proposal(unit: "one stool"), includedDocument: false)
        #expect(!oneReview.hasUnitWarning)
        #expect(oneReview.defaults.valuation)
        #expect(oneReview.valuation.proposedTotal == 1200)

        let unstated = ItemAnalysisReview(item: four, analysis: proposal(unit: nil), includedDocument: false)
        #expect(unstated.hasUnitWarning)
        #expect(!unstated.valuation.canApply)

        let (service, _) = try makeItem(name: "China", quantity: 1)
        let serviceReview = ItemAnalysisReview(item: service, analysis: proposal(unit: "complete 10-place-setting service"),
                                               includedDocument: false)
        #expect(!serviceReview.hasUnitWarning)        // one catalog unit = the complete service
    }

    @Test func identifierHeuristic() {
        #expect(ItemAnalysisReview.containsPossibleIdentifier("According to lab report No. 2141438167"))
        #expect(ItemAnalysisReview.containsPossibleIdentifier("Appraised for owner at 123 Main Street"))
        #expect(ItemAnalysisReview.containsPossibleIdentifier("Contact jane.example@example.com"))
        #expect(!ItemAnalysisReview.containsPossibleIdentifier("Noritake Cabot pattern #9785, made in Japan"))
        #expect(!ItemAnalysisReview.containsPossibleIdentifier("Approx. 24 x 18 x 28 in, 2.08 ct"))
    }

    @Test func categoryPreselectedOnlyWhenUncategorized() throws {
        let (uncategorized, _) = try makeItem(category: "Uncategorized")
        #expect(ItemAnalysisReview(item: uncategorized, analysis: proposal(category: "Furniture"), includedDocument: false).defaults.category)
        let (chosen, _) = try makeItem(category: "Decor")
        let review = ItemAnalysisReview(item: chosen, analysis: proposal(category: "Furniture"), includedDocument: false)
        #expect(review.categoryChanged && !review.defaults.category)
    }

    @Test func conflictsAndLargeChangesAreWarnings() throws {
        let (item, _) = try makeItem(value: 50)
        let review = ItemAnalysisReview(item: item, analysis: proposal(conflicts: ["Stamp says oak, notes say cherry"]),
                                        includedDocument: false)
        #expect(review.warnings.contains(.conflict("Stamp says oak, notes say cherry")))
        #expect(review.warnings.contains(.largeValueChange(current: 50, proposed: 300)))
    }

    @Test func missingOutputSelectsNothingRisky() throws {
        let (item, _) = try makeItem(name: "Lamp", value: 120)
        let analysis = proposal(title: "  ", summary: "", hints: nil, unit: nil)
        let review = ItemAnalysisReview(item: item, analysis: analysis, includedDocument: false)
        #expect(!review.defaults.title)
        #expect(review.defaults.paragraph == .keep)
        #expect(!review.defaults.valuation)
        #expect(!review.valuation.hasEstimate)
        ItemAnalysisApplier.apply(analysis, to: item, choices: review.defaults)
        #expect(item.name == "Lamp" && item.value == 120)
    }
}

// MARK: - Selective apply

@MainActor
struct SelectiveApplyTests {

    @Test func declinedValuationLeavesEverythingStored() throws {
        let (item, _) = try makeItem(description: "Owner text.", value: 90)
        item.valuation = ItemValuation(valueLow: 50, estimatedValue: 90, valueHigh: 120, confidenceScore: 0.4,
                                       aiNotes: "Earlier notes", missingDetails: ["Height"], userNotes: "Owner notes")
        item.suggestedPriceNew = 120
        item.suggestedPriceUsed = 50

        var choices = ItemAnalysisApplier.Choices()
        choices.title = true
        ItemAnalysisApplier.apply(proposal(), to: item, choices: choices)

        #expect(item.name == "Sample Maker Co. Counter Stool")
        #expect(item.value == 90)
        #expect(item.suggestedPriceNew == 120 && item.suggestedPriceUsed == 50)
        let v = try #require(item.valuation)
        #expect(v.valueLow == 50 && v.estimatedValue == 90 && v.valueHigh == 120)
        #expect(v.confidenceScore == 0.4 && v.aiNotes == "Earlier notes" && v.missingDetails == ["Height"])
        #expect(v.userNotes == "Owner notes")
        #expect(item.itemDescription == "Owner text.")
    }

    @Test func valuationAloneDoesNotTouchDescriptionOrTitle() throws {
        let original = "Owner text  with   odd spacing.\n\n\nSecond paragraph."
        let (item, _) = try makeItem(name: "My stools", description: original, value: 90, quantity: 4)
        var choices = ItemAnalysisApplier.Choices()
        choices.valuation = true
        ItemAnalysisApplier.apply(proposal(brand: "X"), to: item, choices: choices)
        #expect(item.itemDescription == original)            // byte-identical
        #expect(item.name == "My stools")
        #expect(item.value == 300 && item.quantity == 4 && item.estimatedTotalValue == 1200)
        #expect(item.valuation?.aiNotes == "AI notes.")
    }

    @Test func nothingChosenChangesNothing() throws {
        let (item, _) = try makeItem(description: "Text", value: 10)
        let before = item.updatedAt
        ItemAnalysisApplier.apply(proposal(brand: "X"), to: item, choices: ItemAnalysisApplier.Choices())
        #expect(item.itemDescription == "Text" && item.value == 10 && item.name == "Stools")
        #expect(item.updatedAt == before)
    }

    @Test func ownerWrittenUseAIGoesAboveOwnerText() throws {
        let (item, _) = try makeItem(description: "Grandma's stools.")
        var choices = ItemAnalysisApplier.Choices()
        choices.paragraph = .useAI
        ItemAnalysisApplier.apply(proposal(), to: item, choices: choices)
        #expect(item.itemDescription == "Counter stool with a cutout back.\n\nGrandma's stools.")
        #expect(item.llmGeneratedDescription == "Counter stool with a cutout back.")
    }

    @Test func mixedUseAIReplacesOnlyWhenChosen() throws {
        let (item, _) = try makeItem(description: "Old AI text, edited by owner.", llm: "Old AI text.")
        var choices = ItemAnalysisApplier.Choices()
        choices.paragraph = .useAI
        ItemAnalysisApplier.apply(proposal(), to: item, choices: choices)
        #expect(item.itemDescription == "Counter stool with a cutout back.")
    }

    @Test func earlierAIParagraphReplacedOwnerAdditionsKept() throws {
        let (item, _) = try makeItem(description: "Old AI text.\n\nBrand: Old Co • Materials: oak\n\nBought in 2007.", llm: "Old AI text.")
        var choices = ItemAnalysisApplier.Choices()
        choices.paragraph = .useAI
        ItemAnalysisApplier.apply(proposal(materials: ["cherry"]), to: item, choices: choices)
        #expect(item.itemDescription == "Counter stool with a cutout back.\n\nBought in 2007.\n\nBrand: Old Co • Materials: oak")
    }

    /// Stage 1 limitation 1: owner text exactly matching a returned attribute.
    @Test func ownerLineMatchingAttributeIsNeverRemoved() throws {
        let description = "Old AI.\n\nDimensions: 36 inches\n\nBrand: Old Co • Materials: oak"
        let (item, _) = try makeItem(description: description, llm: "Old AI.")
        let analysis = proposal(dimensions: "36 inches")
        let review = ItemAnalysisReview(item: item, analysis: analysis, includedDocument: false)
        ItemAnalysisApplier.apply(analysis, to: item, choices: review.defaults)
        #expect(item.itemDescription.contains("Dimensions: 36 inches\n"))   // owner line kept as text
        #expect(item.itemDescription.components(separatedBy: "\n").filter { $0.contains("•") }.count == 1)
    }

    /// Stage 1 limitation 2: an owner edit inside the generated line.
    @Test func editedGeneratedValueIsKeptUnlessChosen() throws {
        let description = "Old AI.\n\nBrand: Old Co • Dimensions: 36 in (measured by me)"
        let (item, _) = try makeItem(description: description, llm: "Old AI.")
        let analysis = proposal(dimensions: "30 in")
        let review = ItemAnalysisReview(item: item, analysis: analysis, includedDocument: false)
        #expect(review.attributes.first { $0.label == "Dimensions" }?.kind == .changed)
        #expect(!review.defaults.attributeLabels.contains("Dimensions"))
        ItemAnalysisApplier.apply(analysis, to: item, choices: review.defaults)
        #expect(item.itemDescription.contains("Dimensions: 36 in (measured by me)"))

        var choose = review.defaults
        choose.attributeLabels.insert("Dimensions")
        let (item2, _) = try makeItem(description: description, llm: "Old AI.")
        ItemAnalysisApplier.apply(analysis, to: item2, choices: choose)
        #expect(item2.itemDescription.contains("Dimensions: 30 in"))
    }

    @Test func previewMatchesApplied() throws {
        let (item, _) = try makeItem(description: "Grandma's stools.")
        let analysis = proposal(brand: "Sample Maker Co.")
        let review = ItemAnalysisReview(item: item, analysis: analysis, includedDocument: false)
        var choices = review.defaults
        choices.paragraph = .useAI
        let preview = review.previewDescription(analysis: analysis, llmGeneratedDescription: item.llmGeneratedDescription,
                                                choices: choices)
        ItemAnalysisApplier.apply(analysis, to: item, choices: choices)
        #expect(item.itemDescription == preview)
    }

    @Test func repeatedSelectiveApplyIsStable() throws {
        let (item, _) = try makeItem()
        let analysis = proposal(brand: "Sample Maker Co.", materials: ["cherry"])
        for _ in 0..<3 {
            let review = ItemAnalysisReview(item: item, analysis: analysis, includedDocument: false)
            ItemAnalysisApplier.apply(analysis, to: item, choices: review.defaults)
        }
        #expect(item.itemDescription == "Counter stool with a cutout back.\n\nBrand: Sample Maker Co. • Materials: cherry")
    }
}
