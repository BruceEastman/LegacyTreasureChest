//
//  LocalGatewayCompatibilityTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 5A backward compatibility, against LOCAL gateways whose Gemini
//  call is stubbed. Off by default; never calls Gemini or any paid service.
//
//    Current gateway  (this branch)        on 127.0.0.1:8000
//    Outdated gateway (production 1.2 code) on 127.0.0.1:8001
//
//    TEST_RUNNER_LTC_LOCAL_GATEWAY_TESTS=1 TEST_RUNNER_LTC_OUTDATED_GATEWAY_TESTS=1 xcodebuild test ... \
//      -only-testing:LegacyTreasureChestTests/LocalGatewayCompatibilityTests
//
//  Synthetic photos and PDFs only.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

private nonisolated let compatibilityTestsEnabled =
    ProcessInfo.processInfo.environment["LTC_LOCAL_GATEWAY_TESTS"] == "1"
    && ProcessInfo.processInfo.environment["LTC_OUTDATED_GATEWAY_TESTS"] == "1"

@MainActor
@Suite(.enabled(if: compatibilityTestsEnabled, "Needs the current (8000) and outdated (8001) local stub gateways"), .serialized)
struct LocalGatewayCompatibilityTests {

    private static let current = 8000
    private static let outdated = 8001
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func provider(port: Int, consentVersion: Int? = nil) -> BackendAIProvider {
        let defaults = UserDefaults(suiteName: "LocalGatewayCompatibilityTests")!
        let consent = AICloudConsentManager(defaults: defaults)
        consent.reset()
        consent.grant()
        return BackendAIProvider(baseURL: URL(string: "http://127.0.0.1:\(port)")!, consent: consent)
    }

    private func fixture(name: String, quantity: Int = 1, primary: Bool = true, extraPhotos: Int = 0,
                         pdfPages: Int? = nil) throws -> (TempMedia, ModelContext, LTCItem, [ItemImage], Document?) {
        let media = try TempMedia()
        let context = ModelContext(try ModelContainer(for: LTCItem.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let item = LTCItem(name: name, itemDescription: "Owner text.", category: "Furniture", value: 90, quantity: quantity)
        item.valuation = ItemValuation(estimatedValue: 90, userNotes: "Owner notes (synthetic).")
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
        return (media, context, item, extras, document)
    }

    private func run(_ item: LTCItem, media: TempMedia, port: Int,
                     configure: (ImproveWithAIModel) -> Void = { _ in }) async throws -> ImproveWithAIModel {
        let p = provider(port: port)
        let model = ImproveWithAIModel(item: item, preparer: AIEvidencePreparer(media: media),
                                       analyzer: { try await p.analyzeItem($0) })
        configure(model)
        #expect(model.canAnalyze)
        model.startAnalysis()
        for _ in 0..<1000 {
            if case .review = model.phase { break }
            if model.errorMessage != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return model
    }

    private func isReview(_ model: ImproveWithAIModel) -> Bool {
        if case .review = model.phase { return true }
        return false
    }

    // MARK: 1.3 client → outdated (1.2) gateway

    @Test func evidencePhotoOnOutdatedGatewayIsNotSilentlyLost() async throws {
        let (media, _, item, extras, _) = try fixture(name: "Counter stool (SYNTHETIC)", extraPhotos: 1)
        defer { media.remove() }
        let model = try await run(item, media: media, port: Self.outdated) { _ = $0.togglePhoto(extras[0].imageId) }
        #expect(!isReview(model))
        #expect(model.errorMessage == AIError.evidenceNotProcessed.localizedDescription)
        #expect(item.name == "Counter stool (SYNTHETIC)" && item.value == 90 && item.itemDescription == "Owner text.")
        print("STAGE5A outdated-gateway message:", model.errorMessage ?? "-")
    }

    @Test func documentOnOutdatedGatewayIsNotSilentlyLost() async throws {
        let (media, _, item, _, doc) = try fixture(name: "Writing desk (SYNTHETIC)", pdfPages: 2)
        defer { media.remove() }
        let model = try await run(item, media: media, port: Self.outdated) { $0.selectDocument(doc?.documentId) }
        #expect(!isReview(model))
        #expect(model.errorMessage == AIError.evidenceNotProcessed.localizedDescription)
    }

    @Test func noPrimaryPhotoWithDocumentOnOutdatedGatewayIsRejected() async throws {
        let (media, _, item, _, doc) = try fixture(name: "Unknown item (SYNTHETIC)", primary: false, pdfPages: 1)
        defer { media.remove() }
        let model = try await run(item, media: media, port: Self.outdated) { $0.selectDocument(doc?.documentId) }
        #expect(!isReview(model))
        #expect(model.errorMessage != nil)
        print("STAGE5A outdated no-primary message:", model.errorMessage ?? "-")
    }

    @Test func singlePhotoStillWorksOnOutdatedGateway() async throws {
        let (media, _, item, _, _) = try fixture(name: "Counter stool (SYNTHETIC)")
        defer { media.remove() }
        let model = try await run(item, media: media, port: Self.outdated)
        guard case .review(let analysis, let review) = model.phase else {
            Issue.record("expected review, got \(model.errorMessage ?? "-")"); return
        }
        #expect(analysis.inputSummary == nil)                 // 1.2 gateway has no receipt
        #expect(review.valuation.basis == .perUnit)           // quantity 1
        #expect(model.apply())
    }

    @Test func textOnlyStillWorksOnOutdatedGateway() async throws {
        let (media, _, item, _, _) = try fixture(name: "Brass lamp (SYNTHETIC)", primary: false)
        defer { media.remove() }
        let model = try await run(item, media: media, port: Self.outdated)
        #expect(isReview(model), "got \(model.errorMessage ?? "-")")
    }

    /// The 1.2 gateway ignores quantity context; without a valuation unit the
    /// estimate for quantity > 1 is ambiguous and is never applied.
    @Test func quantityOnOutdatedGatewayNeverAppliesAnUnstatedEstimate() async throws {
        let (media, _, item, _, _) = try fixture(name: "Counter stools (SYNTHETIC)", quantity: 4)
        defer { media.remove() }
        let model = try await run(item, media: media, port: Self.outdated)
        guard case .review(let analysis, let review) = model.phase else {
            Issue.record("expected review, got \(model.errorMessage ?? "-")"); return
        }
        print("STAGE5A outdated qty unit:", analysis.valuationUnit ?? "nil", review.valuation.basis)
        if analysis.valuationUnit == nil {
            #expect(review.valuation.basis == .ambiguous(.unstated))
            #expect(!review.valuation.canApply && !model.choices.valuation)
            model.choices.valuation = true
            #expect(model.apply())
            #expect(item.value == 90)
        }
    }

    // MARK: 1.2-style requests → current gateway

    @Test func legacyPhotoRequestOnCurrentGateway() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let jpeg = try Data(contentsOf: media.fileURL(forRelativePath: try media.writeJPEG("a.jpg", width: 1200, height: 900)))
        let result = try await provider(port: Self.current)
            .analyzeItemPhoto(imageData: jpeg, hints: ItemAIHints(userWrittenTitle: "Counter stool (SYNTHETIC)"))
        #expect(result.inputSummary == nil)                   // 1.2 path: unchanged response shape
        #expect(!result.title.isEmpty)
        #expect(result.valueHints != nil)
    }

    @Test func legacyTextRequestOnCurrentGateway() async throws {
        let result = try await provider(port: Self.current)
            .analyzeItemText(hints: ItemAIHints(userWrittenTitle: "Brass lamp (SYNTHETIC)"))
        #expect(result.inputSummary == nil)
        #expect(!result.title.isEmpty)
    }
}
