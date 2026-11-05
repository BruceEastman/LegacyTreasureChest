//
//  ItemAnalysisApplierTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 1: Improve with AI Apply. Attribute mapping (brand and other
//  returned attributes), one generated details line, description
//  preservation, owner notes, and unchanged value/quantity semantics.
//  Synthetic analyses only; no network.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

// MARK: - Fixtures

private func analysis(
    title: String = "Sample Maker Co. Counter Stool",
    summary: String = "Counter stool with a solid seat and cutout backrest.",
    category: String = "Furniture",
    valueHints: ValueHints? = nil,
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
) -> ItemAnalysis {
    ItemAnalysis(
        title: title, summary: summary, category: category,
        valueHints: valueHints,
        brand: brand, modelNumber: modelNumber, maker: maker, materials: materials,
        style: style, origin: origin, condition: condition, dimensions: dimensions,
        eraOrYear: eraOrYear, features: features
    )
}

private func detailsLines(in text: String) -> [String] {
    text.components(separatedBy: "\n").filter { GeneratedDetailsLine.parse($0) != nil }
}

// MARK: - Generated details line

struct GeneratedDetailsLineTests {

    @Test func mapsBrandAndPreviouslyDroppedAttributesInCanonicalOrder() {
        let a = analysis(
            brand: "Lexington", modelNumber: "LX-100",
            materials: ["cherry", "brass"], style: "Colonial Revival",
            origin: "USA", condition: "Good", dimensions: "24 x 18 x 28 in",
            eraOrYear: "1990s", features: ["3 drawers", "bracket feet"]
        )
        let line = GeneratedDetailsLine.build(GeneratedDetailsLine.attributes(from: a))
        #expect(line == "Brand: Lexington • Model: LX-100 • Materials: cherry, brass • Style: Colonial Revival • Origin: USA • Era: 1990s • Dimensions: 24 x 18 x 28 in • Condition: Good • Features: 3 drawers, bracket feet")
    }

    @Test func makerIsUsedAsBrandWhenBrandIsMissing() {
        let attrs = GeneratedDetailsLine.attributes(from: analysis(maker: "Nichols & Stone"))
        #expect(attrs["Brand"] == "Nichols & Stone")
        #expect(attrs["Maker"] == nil)
    }

    @Test func distinctMakerIsKeptAlongsideBrand() {
        let attrs = GeneratedDetailsLine.attributes(from: analysis(brand: "Ethan Allen", maker: "Ethan Allen"))
        #expect(attrs["Brand"] == "Ethan Allen")
        #expect(attrs["Maker"] == nil)   // same value is not repeated

        let both = GeneratedDetailsLine.attributes(from: analysis(brand: "Lexington", maker: "Bob Timberlake"))
        #expect(both["Brand"] == "Lexington")
        #expect(both["Maker"] == "Bob Timberlake")
    }

    @Test func blankValuesAreOmitted() {
        let attrs = GeneratedDetailsLine.attributes(from: analysis(brand: "  ", materials: ["", " "], condition: ""))
        #expect(attrs.isEmpty)
        #expect(GeneratedDetailsLine.build(attrs) == nil)
    }

    @Test func roundTripsAndSanitizesSeparatorsAndNewlines() {
        let attrs = GeneratedDetailsLine.attributes(from: analysis(brand: "A • B", condition: "Good\nminor wear"))
        let line = GeneratedDetailsLine.build(attrs)!
        #expect(!line.contains("\n"))
        #expect(GeneratedDetailsLine.parse(line) == ["Brand": "A · B", "Condition": "Good minor wear"])
    }

    @Test func parseRejectsOrdinaryText() {
        #expect(GeneratedDetailsLine.parse("Purchased in 1995 from a gallery.") == nil)
        #expect(GeneratedDetailsLine.parse("Color: blue • Brand: X") == nil)        // unknown key
        #expect(GeneratedDetailsLine.parse("Brand: X • Brand: Y") == nil)            // repeated key
        #expect(GeneratedDetailsLine.parse("Maker: Foo • Materials: oak") == ["Maker": "Foo", "Materials": "oak"]) // 1.2 line
    }
}

// MARK: - Saved description classification

struct SavedDescriptionTests {

    @Test func emptyDescription() {
        let saved = SavedDescription.classify(description: "  \n ", llmGeneratedDescription: nil)
        #expect(saved.origin == .empty)
    }

    @Test func ownerWrittenWhenNoAIParagraphRecorded() {
        let saved = SavedDescription.classify(
            description: "Grandma's stools.\nCondition: Excellent • Brand: Mine",
            llmGeneratedDescription: nil
        )
        #expect(saved.origin == .ownerWritten)
        // Without a recorded AI apply, nothing is treated as generated.
        #expect(saved.generatedAttributes.isEmpty)
        #expect(saved.otherText == "Grandma's stools.\nCondition: Excellent • Brand: Mine")
    }

    @Test func unmodifiedAIOutput() {
        let saved = SavedDescription.classify(
            description: "AI paragraph.\n\nBrand: X • Condition: Good",
            llmGeneratedDescription: "AI paragraph."
        )
        #expect(saved.origin == .aiGenerated)
        #expect(saved.otherText == nil)
        #expect(saved.generatedAttributes == ["Brand": "X", "Condition": "Good"])
    }

    @Test func aiOutputWithOwnerAdditionsBelowTheGeneratedLine() {
        let saved = SavedDescription.classify(
            description: "AI paragraph.\n\nBrand: X • Condition: Good\n\nBought in 1998 in Boston.",
            llmGeneratedDescription: "AI paragraph."
        )
        #expect(saved.origin == .aiGenerated)
        #expect(saved.otherText == "Bought in 1998 in Boston.")
        #expect(saved.generatedAttributes == ["Brand": "X", "Condition": "Good"])
    }

    @Test func editedAIParagraphIsMixed() {
        let saved = SavedDescription.classify(
            description: "AI paragraph, but the seat was recaned.\n\nBrand: X • Condition: Good",
            llmGeneratedDescription: "AI paragraph."
        )
        #expect(saved.origin == .mixed)
        #expect(saved.prose == "AI paragraph, but the seat was recaned.")
    }

    @Test func sameSentenceContinuationIsMixedNotAddition() {
        // Text appended to the same line is an edit of the AI paragraph.
        let saved = SavedDescription.classify(
            description: "AI paragraph. Owner continued here.",
            llmGeneratedDescription: "AI paragraph."
        )
        #expect(saved.origin == .mixed)
    }

    @Test func singleKeyOwnerLineInsideTextIsNotTreatedAsGenerated() {
        let saved = SavedDescription.classify(
            description: "AI paragraph.\n\nCondition: Excellent\nOwner says it was refinished.",
            llmGeneratedDescription: "AI paragraph."
        )
        #expect(saved.generatedAttributes.isEmpty)
        #expect(saved.otherText == "Condition: Excellent\nOwner says it was refinished.")
    }
}

// MARK: - Composing the description on Apply

struct ComposeDescriptionTests {

    private let first = analysis(
        summary: "Counter stool with a cutout backrest.",
        brand: "Sample Maker Co.", materials: ["cherry"], condition: "Good",
        dimensions: "24 in seat height"
    )

    @Test func newItemGetsParagraphAndOneDetailsLine() {
        let composed = ItemAnalysisApplier.composeDescription(current: "", llmGeneratedDescription: nil, analysis: first)
        #expect(composed.description == "Counter stool with a cutout backrest.\n\nBrand: Sample Maker Co. • Materials: cherry • Dimensions: 24 in seat height • Condition: Good")
        #expect(composed.appliedAIParagraph == "Counter stool with a cutout backrest.")
    }

    @Test func repeatedIdenticalAnalysisIsIdempotent() {
        let once = ItemAnalysisApplier.composeDescription(current: "", llmGeneratedDescription: nil, analysis: first)
        let twice = ItemAnalysisApplier.composeDescription(current: once.description,
                                                           llmGeneratedDescription: once.appliedAIParagraph,
                                                           analysis: first)
        #expect(twice.description == once.description)
        #expect(detailsLines(in: twice.description).count == 1)
    }

    @Test func laterAnalysisReplacesChangedAttributesAndKeepsUnmentionedOnes() {
        let once = ItemAnalysisApplier.composeDescription(current: "", llmGeneratedDescription: nil, analysis: first)
        // Second run omits materials and dimensions and corrects the condition.
        let second = analysis(summary: "Updated paragraph.", brand: "Sample Maker Co.", condition: "Fair, seat wear")
        let twice = ItemAnalysisApplier.composeDescription(current: once.description,
                                                           llmGeneratedDescription: once.appliedAIParagraph,
                                                           analysis: second)
        #expect(twice.description == "Updated paragraph.\n\nBrand: Sample Maker Co. • Materials: cherry • Dimensions: 24 in seat height • Condition: Fair, seat wear")
        #expect(detailsLines(in: twice.description).count == 1)
    }

    @Test func ownerWrittenTextIsKeptBelowTheNewParagraph() {
        let owner = "Set of four stools from my parents' kitchen. Stamp under the seat."
        let once = ItemAnalysisApplier.composeDescription(current: owner, llmGeneratedDescription: nil, analysis: first)
        #expect(once.description.hasPrefix("Counter stool with a cutout backrest.\n\n\(owner)\n\nBrand: "))

        // Running again keeps the owner text exactly once and one details line.
        let twice = ItemAnalysisApplier.composeDescription(current: once.description,
                                                           llmGeneratedDescription: once.appliedAIParagraph,
                                                           analysis: first)
        #expect(twice.description == once.description)
        #expect(twice.description.components(separatedBy: owner).count == 2)
    }

    @Test func ownerAdditionsAfterGeneratedLineSurviveWithoutDuplicatingTheLine() {
        let once = ItemAnalysisApplier.composeDescription(current: "", llmGeneratedDescription: nil, analysis: first)
        let edited = once.description + "\n\nBought new in 2007."
        let twice = ItemAnalysisApplier.composeDescription(current: edited,
                                                           llmGeneratedDescription: once.appliedAIParagraph,
                                                           analysis: first)
        #expect(twice.description == "Counter stool with a cutout backrest.\n\nBought new in 2007.\n\nBrand: Sample Maker Co. • Materials: cherry • Dimensions: 24 in seat height • Condition: Good")
        #expect(detailsLines(in: twice.description).count == 1)
    }

    @Test func mixedDescriptionProseIsLeftUnchanged() {
        let current = "Counter stool, recaned by my father in 1985.\n\nMaker: Old • Materials: oak"
        let composed = ItemAnalysisApplier.composeDescription(current: current,
                                                              llmGeneratedDescription: "Counter stool with a cutout backrest.",
                                                              analysis: first)
        #expect(composed.appliedAIParagraph == nil)
        #expect(composed.description.hasPrefix("Counter stool, recaned by my father in 1985.\n\n"))
        // The 1.2 line is replaced, not duplicated; the new materials win.
        #expect(detailsLines(in: composed.description) == ["Brand: Sample Maker Co. • Maker: Old • Materials: cherry • Dimensions: 24 in seat height • Condition: Good"])
    }

    @Test func emptyAIParagraphKeepsExistingProse() {
        let composed = ItemAnalysisApplier.composeDescription(current: "Owner text.", llmGeneratedDescription: nil,
                                                              analysis: analysis(summary: "  ", brand: "X"))
        #expect(composed.description == "Owner text.\n\nBrand: X")
        #expect(composed.appliedAIParagraph == nil)
    }

    @Test func legacy12OutputIsRecognized() {
        // Exactly what app 1.2 Apply wrote (summary, blank line, details line).
        let legacy = "Old AI paragraph.\n\nMaterials: oak • Style: Shaker • Condition: Good"
        let composed = ItemAnalysisApplier.composeDescription(current: legacy,
                                                              llmGeneratedDescription: "Old AI paragraph.",
                                                              analysis: first)
        #expect(composed.description == "Counter stool with a cutout backrest.\n\nBrand: Sample Maker Co. • Materials: cherry • Style: Shaker • Dimensions: 24 in seat height • Condition: Good")
    }
}

// MARK: - Apply on a stored item

// MARK: - Owner-added attribute-like lines (Stage 1 verification)

/// An owner line that looks like a generated attribute ("Dimensions: 36
/// inches") must never be absorbed into, or overwritten by, the generated line.
@MainActor
struct OwnerAttributeLikeLineTests {

    private let ownerLine = "Dimensions: 36 inches"

    private let first = analysis(
        summary: "Cherry nightstand with three drawers.",
        brand: "Lexington", materials: ["cherry"], condition: "Good", dimensions: "24 x 18 x 28 in"
    )

    private func applied(_ current: String, _ llm: String?, _ a: ItemAnalysis) -> ItemAnalysisApplier.ComposedDescription {
        ItemAnalysisApplier.composeDescription(current: current, llmGeneratedDescription: llm, analysis: a)
    }

    private func occurrences(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    @Test func ownerLineSurvivesWhenNewAnalysisReturnsDifferentDimensions() {
        let once = applied("", nil, first)
        let withOwnerLine = once.description + "\n\n" + ownerLine

        let second = analysis(summary: "Lexington cherry nightstand.", brand: "Lexington", dimensions: "30 x 20 x 29 in")
        let result = applied(withOwnerLine, once.appliedAIParagraph, second)

        #expect(occurrences(ownerLine, in: result.description) == 1)
        #expect(detailsLines(in: result.description).filter { GeneratedDetailsLine.parse($0)!.count >= 2 }.count == 1)
        #expect(result.description.hasSuffix("Brand: Lexington • Materials: cherry • Dimensions: 30 x 20 x 29 in • Condition: Good"))
    }

    @Test func ownerLineSurvivesWhenNewAnalysisOmitsDimensions() {
        let once = applied("", nil, first)
        let withOwnerLine = once.description + "\n\n" + ownerLine

        let second = analysis(summary: "Lexington cherry nightstand.", brand: "Lexington", condition: "Fair")
        let result = applied(withOwnerLine, once.appliedAIParagraph, second)

        #expect(occurrences(ownerLine, in: result.description) == 1)
        // The earlier generated dimensions stay in the generated line, separate from the owner's line.
        #expect(result.description.hasSuffix("Brand: Lexington • Materials: cherry • Dimensions: 24 x 18 x 28 in • Condition: Fair"))
    }

    @Test func ownerLineAddedToAIDescriptionWithoutGeneratedLineSurvives() {
        // An earlier analysis returned no attributes, so no generated line exists.
        let once = applied("", nil, analysis(summary: "Cherry nightstand."))
        #expect(once.description == "Cherry nightstand.")
        let withOwnerLine = once.description + "\n\n" + ownerLine

        let second = analysis(summary: "Lexington cherry nightstand.", brand: "Lexington", dimensions: "30 in")
        let result = applied(withOwnerLine, once.appliedAIParagraph, second)

        #expect(occurrences(ownerLine, in: result.description) == 1)
        #expect(result.description == "Lexington cherry nightstand.\n\n\(ownerLine)\n\nBrand: Lexington • Dimensions: 30 in")
    }

    @Test func repeatedApplyIsStableWithOwnerLine() {
        let once = applied("", nil, first)
        let withOwnerLine = once.description + "\n\n" + ownerLine
        let second = analysis(summary: "Lexington cherry nightstand.", brand: "Lexington", dimensions: "30 in")

        var current = applied(withOwnerLine, once.appliedAIParagraph, second)
        let afterFirstRepeat = current.description
        for _ in 0..<3 {
            current = applied(current.description, current.appliedAIParagraph, second)
            #expect(current.description == afterFirstRepeat)
        }
        #expect(occurrences(ownerLine, in: current.description) == 1)
        #expect(occurrences("Brand: Lexington", in: current.description) == 1)
    }

    @Test func repeatedSingleAttributeApplyIsStable() {
        // A first analysis that returned only one attribute writes a one-segment line.
        let only = analysis(summary: "Vase.", brand: "Waterford")
        var current = applied("", nil, only)
        let first = current.description
        #expect(first == "Vase.\n\nBrand: Waterford")
        for _ in 0..<3 {
            current = applied(current.description, current.appliedAIParagraph, only)
            #expect(current.description == first)
        }
    }

    @Test func applyOnStoredItemKeepsOwnerNotesAndOwnerLine() throws {
        let container = try ModelContainer(for: LTCItem.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let item = LTCItem(name: "Nightstand", itemDescription: "", category: "Furniture", value: 175, quantity: 2)
        context.insert(item)
        item.valuation = ItemValuation(userNotes: "Bob Timberlake collection for Lexington.")
        try context.save()

        ItemAnalysisApplier.apply(first, to: item)
        item.itemDescription += "\n\n" + ownerLine
        ItemAnalysisApplier.apply(analysis(summary: "Lexington cherry nightstand.", brand: "Lexington", dimensions: "30 in"), to: item)
        ItemAnalysisApplier.apply(analysis(summary: "Lexington cherry nightstand.", brand: "Lexington", dimensions: "30 in"), to: item)
        try context.save()

        #expect(item.valuation?.userNotes == "Bob Timberlake collection for Lexington.")
        #expect(occurrences(ownerLine, in: item.itemDescription) == 1)
        #expect(item.quantity == 2)
    }
}

@MainActor
struct ItemAnalysisApplyTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: LTCItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func applyKeepsOwnerNotesAndWritesBrand() throws {
        let context = try makeContext()
        let item = LTCItem(name: "Stools", itemDescription: "Owner text.", category: "Uncategorized")
        context.insert(item)
        let valuation = ItemValuation(userNotes: "Quantity: 4. Stamp reads Sample Maker Co.")
        item.valuation = valuation
        try context.save()

        let hints = ValueHints(valueLow: 200, estimatedValue: 350, valueHigh: 500, currencyCode: "USD",
                               confidenceScore: 0.8, aiNotes: "notes", missingDetails: ["Seat height"])
        ItemAnalysisApplier.apply(analysis(valueHints: hints, brand: "Sample Maker Co."), to: item)
        try context.save()

        #expect(item.valuation?.userNotes == "Quantity: 4. Stamp reads Sample Maker Co.")
        #expect(item.itemDescription.contains("Owner text."))
        #expect(item.itemDescription.hasSuffix("Brand: Sample Maker Co."))
        #expect(item.llmGeneratedDescription == "Counter stool with a solid seat and cutout backrest.")
        #expect(item.llmGeneratedTitle == "Sample Maker Co. Counter Stool")
        #expect(item.category == "Furniture")
        #expect(item.valuation?.estimatedValue == 350)
        #expect(item.valuation?.missingDetails == ["Seat height"])
    }

    @Test func valueStaysPerUnitAndQuantityIsUnchanged() throws {
        let context = try makeContext()
        let item = LTCItem(name: "Stools", itemDescription: "", category: "Furniture", value: 90, quantity: 4)
        context.insert(item)
        try context.save()

        let hints = ValueHints(valueLow: 200, estimatedValue: 350, valueHigh: 500)
        ItemAnalysisApplier.apply(analysis(valueHints: hints), to: item)

        #expect(item.quantity == 4)
        #expect(item.value == 350)
        #expect(item.estimatedUnitValue == 350)
        #expect(item.estimatedTotalValue == 1400)
        #expect(item.suggestedPriceNew == 500)
        #expect(item.suggestedPriceUsed == 200)
    }

    @Test func missingEstimateLeavesValueUntouched() throws {
        let context = try makeContext()
        let item = LTCItem(name: "Rug", itemDescription: "", category: "Rug", value: 1200, quantity: 1)
        context.insert(item)
        try context.save()

        ItemAnalysisApplier.apply(analysis(valueHints: ValueHints()), to: item)
        #expect(item.value == 1200)
    }

    @Test func mixedDescriptionDoesNotMoveTheAIAnchor() throws {
        let context = try makeContext()
        let item = LTCItem(name: "Stools", itemDescription: "Edited by owner.", category: "Furniture")
        item.llmGeneratedDescription = "Original AI paragraph."
        context.insert(item)
        try context.save()

        ItemAnalysisApplier.apply(analysis(brand: "X"), to: item)
        #expect(item.itemDescription == "Edited by owner.\n\nBrand: X")
        #expect(item.llmGeneratedDescription == "Original AI paragraph.")
    }
}
