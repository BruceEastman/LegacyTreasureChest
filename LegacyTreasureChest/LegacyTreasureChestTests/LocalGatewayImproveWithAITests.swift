//
//  LocalGatewayImproveWithAITests.swift
//  LegacyTreasureChestTests
//
//  End-to-end Improve with AI (Stage 4) through a LOCAL gateway whose Gemini
//  call is stubbed with scenario-specific synthetic responses. Off by default;
//  never calls Gemini or any paid service:
//
//    TEST_RUNNER_LTC_LOCAL_GATEWAY_TESTS=1 xcodebuild test ... \
//      -only-testing:LegacyTreasureChestTests/LocalGatewayImproveWithAITests
//
//  Item names carry a scenario marker the stub uses to pick its response.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

private nonisolated let improveGatewayTestsEnabled = ProcessInfo.processInfo.environment["LTC_LOCAL_GATEWAY_TESTS"] == "1"

@MainActor
@Suite(.enabled(if: improveGatewayTestsEnabled, "Set LTC_LOCAL_GATEWAY_TESTS=1 with a local stubbed gateway"), .serialized)
struct LocalGatewayImproveWithAITests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func provider() -> BackendAIProvider {
        let defaults = UserDefaults(suiteName: "LocalGatewayImproveWithAITests")!
        let consent = AICloudConsentManager(defaults: defaults)
        consent.grant()
        return BackendAIProvider(baseURL: URL(string: "http://127.0.0.1:8000")!, consent: consent)
    }

    private struct Fixture {
        let media: TempMedia
        let context: ModelContext
        let item: LTCItem
        let extras: [ItemImage]
        let document: Document?
    }

    private func fixture(name: String, category: String, description: String = "", llm: String? = nil,
                         notes: String? = nil, quantity: Int = 1, primary: Bool = true,
                         extraPhotos: Int = 0, pdfPages: Int? = nil) throws -> Fixture {
        let media = try TempMedia()
        let context = ModelContext(try ModelContainer(for: LTCItem.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let item = LTCItem(name: name, itemDescription: description, category: category, quantity: quantity)
        item.llmGeneratedDescription = llm
        if let notes { item.valuation = ItemValuation(userNotes: notes) }
        context.insert(item)
        var extras: [ItemImage] = []
        for i in 0..<((primary ? 1 : 0) + extraPhotos) {
            let image = ItemImage(filePath: try media.writeJPEG("p\(i).jpg", width: 2400, height: 1800),
                                  createdAt: t0.addingTimeInterval(Double(i)))
            image.item = item
            item.images.append(image)
            context.insert(image)
            if !primary || i > 0 { extras.append(image) }
        }
        var document: Document?
        if let pdfPages {
            let doc = Document(filePath: try media.writePDF("appraisal.pdf", pages: pdfPages), documentType: "PDF",
                               originalFilename: "appraisal.pdf")
            doc.item = item
            item.documents.append(doc)
            context.insert(doc)
            document = doc
        }
        return Fixture(media: media, context: context, item: item, extras: extras, document: document)
    }

    private func analyze(_ f: Fixture, configure: (ImproveWithAIModel) -> Void = { _ in }) async throws
        -> (ImproveWithAIModel, ItemAnalysis, ItemAnalysisReview) {
        let p = provider()
        let model = ImproveWithAIModel(item: f.item, preparer: AIEvidencePreparer(media: f.media),
                                       analyzer: { try await p.analyzeItem($0) })
        configure(model)
        #expect(model.canAnalyze)
        model.startAnalysis()
        for _ in 0..<500 {
            if case .review = model.phase { break }
            if model.errorMessage != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard case .review(let analysis, let review) = model.phase else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: model.errorMessage ?? "no review"])
        }
        return (model, analysis, review)
    }

    // 1. Furniture with a maker-mark photograph.
    @Test func furnitureWithMakerMark() async throws {
        let f = try fixture(name: "[FURNITURE] Counter stool", category: "Furniture", extraPhotos: 1)
        defer { f.media.remove() }
        let (model, analysis, review) = try await analyze(f) { $0.togglePhoto(f.extras[0].imageId) }
        #expect(analysis.inputSummary?.supplementaryPhotos == 1)
        #expect(analysis.inputSummary?.primaryPhoto == true)
        #expect(review.defaults.title && review.defaults.paragraph == .useAI)
        #expect(review.defaults.attributeLabels.contains("Brand"))
        #expect(model.apply())
        #expect(f.item.itemDescription.contains("Brand: Sample Maker Co."))
        #expect(f.item.value == 120)
    }

    // 2. China with a backstamp photograph.
    @Test func chinaWithBackstamp() async throws {
        let f = try fixture(name: "[CHINA] Dinnerware", category: "Uncategorized",
                            notes: "10 place settings", extraPhotos: 1)
        defer { f.media.remove() }
        let (model, _, review) = try await analyze(f) { $0.togglePhoto(f.extras[0].imageId) }
        #expect(review.valuation.unit == "complete 10-place-setting service")
        #expect(!review.hasUnitWarning)                    // quantity 1: the unit is the whole service
        #expect(review.defaults.category)                  // was Uncategorized
        #expect(review.attributes.contains { $0.label == "Model" && $0.proposed == "9785" })
        #expect(model.apply())
        #expect(f.item.category == "China & Crystal")
        #expect(f.item.itemDescription.contains("Model: 9785"))
        #expect(f.item.valuation?.userNotes == "10 place settings")
    }

    // 3. Jewelry with a multipage appraisal document.
    @Test func jewelryWithAppraisalDocument() async throws {
        let f = try fixture(name: "[JEWELRY] Pendant", category: "Jewelry", description: "My mother's pendant.",
                            notes: "18K I think", pdfPages: 3)
        defer { f.media.remove() }
        let (model, analysis, review) = try await analyze(f) { $0.selectDocument(f.document?.documentId) }
        #expect(analysis.inputSummary?.documentPages == 3)
        #expect(review.warnings.contains(.documentDerived))
        #expect(review.warnings.contains(.possibleIdentifier))     // report number in the proposed text
        #expect(review.warnings.contains { if case .conflict = $0 { return true } else { return false } })
        // Nothing document-derived is preselected; the value is.
        #expect(!review.defaults.title && review.defaults.paragraph == .keep && review.defaults.attributeLabels.isEmpty)
        #expect(model.apply())
        #expect(f.item.name == "[JEWELRY] Pendant")
        #expect(f.item.itemDescription == "My mother's pendant.")
        #expect(!f.item.itemDescription.contains("2141438167"))
        #expect(f.item.value == 9500)
    }

    // 4. No primary photograph (document only).
    @Test func noPrimaryPhotoDocumentOnly() async throws {
        let f = try fixture(name: "[NOPRIMARY] Unknown item", category: "Uncategorized", primary: false, pdfPages: 1)
        defer { f.media.remove() }
        let (_, analysis, _) = try await analyze(f) { $0.selectDocument(f.document?.documentId) }
        #expect(analysis.inputSummary?.primaryPhoto == false)
        #expect(analysis.inputSummary?.documentPages == 1)
    }

    // 5. Quantity greater than one, with an estimate for the whole set.
    @Test func quantityFourWithSetEstimate() async throws {
        let f = try fixture(name: "[QTYSET] Counter stools", category: "Furniture", quantity: 4)
        defer { f.media.remove() }
        f.item.value = 90
        let (model, analysis, review) = try await analyze(f)
        #expect(analysis.inputSummary?.quantity == 4)
        #expect(review.valuation.basis == .group(size: 4))     // "set of four stools", $600–$1,000
        #expect(review.valuation.proposedEstimate == 200 && review.valuation.proposedTotal == 800)
        #expect(!review.defaults.valuation)
        model.choices.title = false                                // keep the scenario marker for the second run
        #expect(model.apply())                                     // with defaults: value untouched
        #expect(f.item.value == 90 && f.item.estimatedTotalValue == 360)

        let (accepting, _, _) = try await analyze(f)
        accepting.choices.valuation = true
        #expect(accepting.apply())
        #expect(f.item.value == 200 && f.item.estimatedTotalValue == 800)
    }

    // 5b. Group size that contradicts the quantity: nothing is applied.
    @Test func quantityConflictIsNotApplied() async throws {
        let f = try fixture(name: "[QTYCONFLICT] Dining chairs", category: "Furniture", quantity: 4)
        defer { f.media.remove() }
        f.item.value = 90
        let (model, _, review) = try await analyze(f)
        #expect(review.valuation.basis == .ambiguous(.conflictingCount(6)))
        model.choices.valuation = true
        #expect(model.apply())
        #expect(f.item.value == 90)
    }

    // 6. Previously edited AI description.
    @Test func previouslyEditedDescription() async throws {
        let description = "Old AI paragraph, recaned by my father.\n\nBrand: Old Co • Dimensions: 36 in"
        let f = try fixture(name: "[EDITED] Stool", category: "Furniture", description: description,
                            llm: "Old AI paragraph.")
        defer { f.media.remove() }
        let (model, _, review) = try await analyze(f)
        #expect(review.saved.origin == .mixed)
        #expect(review.defaults.paragraph == .keep)
        #expect(review.attributes.first { $0.label == "Dimensions" }?.kind == .changed)
        #expect(!review.defaults.attributeLabels.contains("Dimensions"))
        #expect(model.apply())
        #expect(f.item.itemDescription.hasPrefix("Old AI paragraph, recaned by my father."))
        #expect(f.item.itemDescription.contains("Dimensions: 36 in"))
    }
}
