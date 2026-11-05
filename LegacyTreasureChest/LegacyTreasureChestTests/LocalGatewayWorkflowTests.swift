//
//  LocalGatewayWorkflowTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 5A integrated workflows through a LOCAL gateway whose Gemini call
//  is stubbed (scenario markers in item names select the stub's response).
//  Off by default; never calls Gemini or any paid service:
//
//    TEST_RUNNER_LTC_LOCAL_GATEWAY_TESTS=1 xcodebuild test ... \
//      -only-testing:LegacyTreasureChestTests/LocalGatewayWorkflowTests
//
//  Complements LocalGatewayImproveWithAITests and LocalGatewayEvidenceTests.
//  Synthetic photos and PDFs only.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

private nonisolated let workflowGatewayTestsEnabled = ProcessInfo.processInfo.environment["LTC_LOCAL_GATEWAY_TESTS"] == "1"

/// Resolves a relative path in `first` when the file exists there, else in `then`.
private nonisolated struct FallbackMedia: AIEvidenceMediaSource {
    let first: any AIEvidenceMediaSource
    let then: any AIEvidenceMediaSource
    func fileURL(forRelativePath path: String) -> URL {
        let url = first.fileURL(forRelativePath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : then.fileURL(forRelativePath: path)
    }
}

@MainActor
@Suite(.enabled(if: workflowGatewayTestsEnabled, "Set LTC_LOCAL_GATEWAY_TESTS=1 with a local stubbed gateway"), .serialized)
struct LocalGatewayWorkflowTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func provider(port: Int = 8000) -> BackendAIProvider {
        let defaults = UserDefaults(suiteName: "LocalGatewayWorkflowTests")!
        let consent = AICloudConsentManager(defaults: defaults)
        consent.grant()
        return BackendAIProvider(baseURL: URL(string: "http://127.0.0.1:\(port)")!, consent: consent)
    }

    private struct Fixture {
        let media: TempMedia
        let context: ModelContext
        let item: LTCItem
        let extras: [ItemImage]
        let document: Document?
        let sibling: LTCItem
        let set: LTCSet
    }

    /// An item (with owner notes, a full saved valuation and attachments) in a
    /// Set with one other item, so Set totals can be checked.
    private func fixture(name: String, category: String = "Furniture", description: String = "Owner text.",
                         quantity: Int = 1, value: Double = 90, extraPhotos: Int = 0,
                         pdfPages: Int? = nil) throws -> Fixture {
        let media = try TempMedia()
        let context = ModelContext(try ModelContainer(for: LTCItem.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let item = LTCItem(name: name, itemDescription: description, category: category, value: value, quantity: quantity)
        item.valuation = ItemValuation(valueLow: 70, estimatedValue: value, valueHigh: 110, confidenceScore: 0.3,
                                       aiNotes: "Earlier notes.", missingDetails: ["Maker"], userNotes: "Owner notes (synthetic).")
        context.insert(item)
        var extras: [ItemImage] = []
        for i in 0..<(1 + extraPhotos) {
            let image = ItemImage(filePath: try media.writeJPEG("p\(i).jpg", width: 2400, height: 1800),
                                  createdAt: t0.addingTimeInterval(Double(i)))
            image.item = item
            item.images.append(image)
            context.insert(image)
            if i > 0 { extras.append(image) }
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
        let sibling = LTCItem(name: "Sibling (SYNTHETIC)", itemDescription: "", category: "Furniture", value: 50, quantity: 2)
        context.insert(sibling)
        let set = LTCSet(name: "Synthetic set")
        context.insert(set)
        set.items = [item, sibling]
        return Fixture(media: media, context: context, item: item, extras: extras, document: document,
                       sibling: sibling, set: set)
    }

    private func setTotal(_ set: LTCSet) -> Double { set.items.reduce(0) { $0 + ($1.estimatedTotalValue ?? 0) } }

    private struct Snapshot: Equatable {
        let name, description, category: String
        let value: Double
        let quantity: Int
        let notes: String?
        let low, estimate, high, confidence: Double?
        let aiNotes: String?
        let images: [String]
        let documents: [String]
        let setID: UUID?
        let setTotal: Double
    }

    private func snapshot(_ f: Fixture) -> Snapshot {
        let v = f.item.valuation
        return Snapshot(name: f.item.name, description: f.item.itemDescription, category: f.item.category,
                        value: f.item.value, quantity: f.item.quantity, notes: v?.userNotes,
                        low: v?.valueLow, estimate: v?.estimatedValue, high: v?.valueHigh, confidence: v?.confidenceScore,
                        aiNotes: v?.aiNotes, images: f.item.images.map(\.filePath).sorted(),
                        documents: f.item.documents.map(\.filePath).sorted(), setID: f.item.set?.setId,
                        setTotal: setTotal(f.set))
    }

    private func model(_ f: Fixture, preparer: AIEvidencePreparer? = nil, port: Int = 8000) -> ImproveWithAIModel {
        let p = provider(port: port)
        return ImproveWithAIModel(item: f.item, preparer: preparer ?? AIEvidencePreparer(media: f.media),
                                  analyzer: { try await p.analyzeItem($0) })
    }

    /// Runs until review or error (bounded, ~20 s).
    private func run(_ model: ImproveWithAIModel) async throws {
        #expect(model.canAnalyze)
        model.startAnalysis()
        for _ in 0..<2000 {
            if case .review = model.phase { return }
            if model.errorMessage != nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func review(_ model: ImproveWithAIModel) throws -> (ItemAnalysis, ItemAnalysisReview) {
        guard case .review(let analysis, let review) = model.phase else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: model.errorMessage ?? "no review"])
        }
        return (analysis, review)
    }

    // W1. Existing Improve with AI: primary photo only, no supplementary evidence.
    @Test func primaryPhotoOnlyNoEvidence() async throws {
        let f = try fixture(name: "Brass lamp (SYNTHETIC)", category: "Decor")
        defer { f.media.remove() }
        let m = model(f)
        #expect(!m.requiresEvidenceDisclosure)        // consent v1 is enough
        try await run(m)
        let (analysis, _) = try review(m)
        #expect(analysis.inputSummary?.primaryPhoto == true)
        #expect(analysis.inputSummary?.supplementaryPhotos == 0)
        #expect(analysis.inputSummary?.documents == 0)
        #expect(analysis.title.contains("Brass lamp"))           // neutral stub echoes this item
    }

    // W5. A PDF attached from within Improve with AI becomes an attachment and is analyzed.
    @Test func newlyAttachedPDFIsSelectedAndAnalyzed() async throws {
        let f = try fixture(name: "[JEWELRY] Pendant", category: "Jewelry")
        defer { f.media.remove() }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("stage5a-new-appraisal.pdf")
        let tmp = try TempMedia(); defer { tmp.remove() }
        try FileManager.default.copyItem(at: tmp.fileURL(forRelativePath: try tmp.writePDF("a.pdf", pages: 2)), to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        // The importer stores the file through MediaStorage, like the picker
        // does; the fixture's photo stays in the temporary folder.
        let m = model(f, preparer: AIEvidencePreparer(media: FallbackMedia(first: f.media, then: StoredMediaSource())))
        let document = try ItemDocumentImporter.importDocument(from: source, into: f.item, context: f.context)
        defer { try? MediaStorage.deleteFile(at: document.filePath) }
        m.didImportDocument(document)
        #expect(m.selectedDocumentID == document.documentId)
        #expect(f.item.documents.count == 1)
        try await run(m)
        let (analysis, review) = try review(m)
        #expect(analysis.inputSummary?.documents == 1)
        #expect(analysis.inputSummary?.documentPages == 2)
        #expect(review.warnings.contains(.documentDerived))
        // The owner discards the review: the attachment stays.
        m.discardReview()
        #expect(f.item.documents.map(\.documentId) == [document.documentId])
        #expect(f.item.valuation?.userNotes == "Owner notes (synthetic).")
    }

    // W6. A 12-page PDF needs acknowledgement; only 10 pages are sent.
    @Test func longPDFRequiresAcknowledgementAndIsTruncated() async throws {
        let f = try fixture(name: "Writing desk (SYNTHETIC)", pdfPages: 12)
        defer { f.media.remove() }
        let m = model(f)
        m.selectDocument(f.document?.documentId)
        #expect(m.needsTruncationAcknowledgement)
        #expect(!m.canAnalyze)
        m.acknowledgedTruncation = true
        try await run(m)
        let (analysis, _) = try review(m)
        #expect(analysis.inputSummary?.documentPages == 10)
    }

    // W8. Quantity 4 with a per-unit estimate: applied as returned, total = 4 × each.
    @Test func perUnitEstimateAtQuantityFour() async throws {
        let f = try fixture(name: "Counter stools (SYNTHETIC)", quantity: 4)
        defer { f.media.remove() }
        let before = setTotal(f.set)
        let m = model(f)
        try await run(m)
        let (analysis, review) = try review(m)
        #expect(analysis.inputSummary?.quantity == 4)
        #expect(analysis.valuationUnit == "one stool")
        #expect(review.valuation.basis == .perUnit)
        #expect(review.valuation.proposedEstimate == 120 && review.valuation.proposedTotal == 480)
        #expect(m.choices.valuation)
        #expect(m.apply())
        #expect(f.item.value == 120 && f.item.estimatedTotalValue == 480 && f.item.quantity == 4)
        #expect(setTotal(f.set) == before - 360 + 480)
    }

    // W9. Selective accept/reject across identification, attributes, description and valuation.
    @Test func selectiveAcceptAndReject() async throws {
        let f = try fixture(name: "[FURNITURE] Counter stool", category: "Uncategorized", extraPhotos: 1, pdfPages: 1)
        defer { f.media.remove() }
        let before = snapshot(f)
        let m = model(f)
        _ = m.togglePhoto(f.extras[0].imageId)
        try await run(m)
        let (_, review) = try review(m)
        #expect(review.attributes.contains { $0.label == "Brand" })
        #expect(review.attributes.contains { $0.label == "Materials" })

        m.choices = ItemAnalysisApplier.Choices()
        m.choices.title = false            // rejected
        m.choices.category = true          // accepted
        m.choices.paragraph = .keep        // rejected
        m.choices.attributeLabels = ["Brand"]
        m.choices.valuation = false        // rejected
        #expect(m.apply())

        #expect(f.item.name == before.name)
        #expect(f.item.category == "Furniture")
        #expect(f.item.itemDescription.hasPrefix("Owner text."))
        #expect(f.item.itemDescription.contains("Brand: Sample Maker Co."))
        #expect(!f.item.itemDescription.contains("Materials"))
        #expect(!f.item.itemDescription.contains("LOCAL STUB"))
        // Valuation, notes, quantity, attachments and the Set are untouched.
        let after = snapshot(f)
        #expect(after.value == before.value && after.quantity == before.quantity)
        #expect(after.low == before.low && after.estimate == before.estimate && after.high == before.high)
        #expect(after.confidence == before.confidence && after.aiNotes == before.aiNotes)
        #expect(after.notes == before.notes)
        #expect(after.images == before.images && after.documents == before.documents)
        #expect(after.setID == before.setID && after.setTotal == before.setTotal)
        #expect(f.media.fileCount() == 3)
    }

    // W10a. Cancellation while the gateway is working leaves the item unchanged.
    @Test func cancellationLeavesItemUnchanged() async throws {
        let f = try fixture(name: "[SLOW] Side table", extraPhotos: 1)
        defer { f.media.remove() }
        let before = snapshot(f)
        let m = model(f)
        _ = m.togglePhoto(f.extras[0].imageId)
        m.startAnalysis()
        #expect(m.isAnalyzing)
        try await Task.sleep(nanoseconds: 500_000_000)
        m.startAnalysis()                                   // duplicate submission is ignored
        m.cancelAnalysis()
        for _ in 0..<500 where m.isAnalyzing { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(!m.isAnalyzing)
        #expect(m.errorMessage == AIError.cancelled.localizedDescription)
        #expect(snapshot(f) == before)
        #expect(m.selectedPhotoIDs == [f.extras[0].imageId])   // selection kept for a retry
    }

    // W10b. Network failure (nothing listening) leaves the item unchanged.
    @Test func networkFailureLeavesItemUnchanged() async throws {
        let f = try fixture(name: "Mirror (SYNTHETIC)", extraPhotos: 1)
        defer { f.media.remove() }
        let before = snapshot(f)
        let m = model(f, port: 8009)
        _ = m.togglePhoto(f.extras[0].imageId)
        try await run(m)
        #expect(m.errorMessage != nil)
        if case .compose = m.phase {} else { Issue.record("expected compose, got \(m.phase)") }
        #expect(snapshot(f) == before)
        print("STAGE5A network failure message:", m.errorMessage ?? "-")
    }

    // W10c. A malformed model response (and failed repair) surfaces an error; item unchanged.
    @Test func malformedResponseLeavesItemUnchanged() async throws {
        let f = try fixture(name: "[MALFORMED] Clock", extraPhotos: 1)
        defer { f.media.remove() }
        let before = snapshot(f)
        let m = model(f)
        _ = m.togglePhoto(f.extras[0].imageId)
        try await run(m)
        #expect(m.errorMessage != nil)
        if case .compose = m.phase {} else { Issue.record("expected compose, got \(m.phase)") }
        #expect(snapshot(f) == before)
        print("STAGE5A malformed message:", m.errorMessage ?? "-")
    }

    // W10c'. A malformed first response that the gateway repairs reaches review normally.
    @Test func repairedResponseReachesReview() async throws {
        let f = try fixture(name: "[REPAIRED] Clock", extraPhotos: 1)
        defer { f.media.remove() }
        let m = model(f)
        _ = m.togglePhoto(f.extras[0].imageId)
        try await run(m)
        let (analysis, _) = try review(m)
        #expect(analysis.inputSummary?.supplementaryPhotos == 1)
    }
}
