//
//  LocalGatewayEvidenceTests.swift
//  LegacyTreasureChestTests
//
//  End-to-end Improve with AI evidence checks against a LOCAL gateway
//  (http://127.0.0.1:8000) whose Gemini call is stubbed. Off by default; they
//  never call Gemini or any paid service:
//
//    (start the gateway locally with Gemini stubbed, then)
//    TEST_RUNNER_LTC_LOCAL_GATEWAY_TESTS=1 xcodebuild test ... \
//      -only-testing:LegacyTreasureChestTests/LocalGatewayEvidenceTests
//
//  Synthetic photos and PDFs only.
//

import Foundation
import SwiftData
import Testing
import UIKit
@testable import LegacyTreasureChest

private nonisolated let localGatewayTestsEnabled = ProcessInfo.processInfo.environment["LTC_LOCAL_GATEWAY_TESTS"] == "1"

@MainActor
@Suite(.enabled(if: localGatewayTestsEnabled, "Set LTC_LOCAL_GATEWAY_TESTS=1 with a local stubbed gateway"), .serialized)
struct LocalGatewayEvidenceTests {

    private let gateway = URL(string: "http://127.0.0.1:8000")!

    private func provider() -> BackendAIProvider {
        let defaults = UserDefaults(suiteName: "LocalGatewayEvidenceTests")!
        let consent = AICloudConsentManager(defaults: defaults)
        consent.grant()
        return BackendAIProvider(baseURL: gateway, consent: consent)
    }

    private func makeItem(_ media: TempMedia) throws -> (LTCItem, ModelContext, [UUID], UUID) {
        let context = ModelContext(try ModelContainer(for: LTCItem.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let item = LTCItem(name: "Counter Stools (SYNTHETIC)", itemDescription: "Cherry stool.\n\nBrand: Old Co • Materials: cherry",
                           category: "Furniture", quantity: 4)
        item.llmGeneratedDescription = "Cherry stool."
        item.valuation = ItemValuation(userNotes: "Stamp under the seat (synthetic).")
        context.insert(item)

        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var ids: [UUID] = []
        for (i, name) in ["primary.jpg", "stamp.jpg", "label.jpg"].enumerated() {
            let image = ItemImage(filePath: try media.writeJPEG(name, width: 3024, height: 4032), createdAt: t0.addingTimeInterval(Double(i)))
            image.item = item
            item.images.append(image)
            context.insert(image)
            if i > 0 { ids.append(image.imageId) }
        }
        let doc = Document(filePath: try media.writePDF("appraisal.pdf", pages: 12), documentType: "PDF", originalFilename: "appraisal.pdf")
        doc.item = item
        item.documents.append(doc)
        context.insert(doc)
        return (item, context, ids, doc.documentId)
    }

    @Test func photosAndTruncatedPdfAreAnalyzedAndConfirmed() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let (item, _, photoIDs, docID) = try makeItem(media)
        let selection = AIEvidenceSelection(supplementaryImageIDs: photoIDs, documentIDs: [docID])

        let preparer = AIEvidencePreparer(media: media)
        let plan = try preparer.plan(for: item, selection: selection)
        #expect(plan.truncatedDocuments.first?.totalPages == 12)

        let prepared = try await preparer.prepare(for: item, selection: selection)
        let request = ItemAnalysisRequestBuilder.build(for: item, prepared: prepared)
        let result = try await provider().analyzeItem(request)

        let summary = try #require(result.inputSummary)
        #expect(summary.primaryPhoto)
        #expect(summary.supplementaryPhotos == 2)
        #expect(summary.documents == 1)
        #expect(summary.documentPages == 10)
        #expect(summary.quantity == 4)
        #expect(summary.ownerNotes == true)
        #expect(summary.savedDescriptionParts == 1)
        #expect(summary.priorAttributes == 2)
        #expect(result.valuationUnit == "one stool")
        #expect(result.brand == "Sample Maker Co.")
        print("LOCAL-GATEWAY upload bytes:", prepared.totalBytes)
    }

    @Test func textOnlyItemUsesContext() async throws {
        let context = ModelContext(try ModelContainer(for: LTCItem.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let item = LTCItem(name: "Brass Lamp (SYNTHETIC)", itemDescription: "Owner text.", category: "Decor", quantity: 2)
        context.insert(item)
        let request = ItemAnalysisRequestBuilder.build(
            for: item,
            prepared: PreparedEvidence(primaryJPEG: nil, supplementary: [],
                                       plan: AIEvidencePlan(includesPrimaryPhoto: false, supplementaryImageIDs: [], documents: []))
        )
        let result = try await provider().analyzeItem(request)
        #expect(result.inputSummary?.quantity == 2)
        #expect(result.inputSummary?.primaryPhoto == false)
    }

    @Test func gatewayRejectsTooManyPhotosWithClearCode() async throws {
        let jpeg = AIEvidencePreparer.jpegData(from: UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }.cgImage!, quality: 0.8)!
        let request = ItemAnalysisRequest(
            hints: ItemAIHints(userWrittenTitle: "x"),
            context: ItemAnalysisContextDTO(quantity: 1, ownerNotes: nil, savedDescription: [], priorAttributes: nil),
            primaryJPEG: jpeg,
            supplementary: Array(repeating: .photo(jpeg), count: 4)
        )
        do {
            _ = try await provider().analyzeItem(request)
            Issue.record("expected a rejection")
        } catch let error as AIError {
            if case .evidenceRejected(let code, _) = error { #expect(code == "EVIDENCE_TOO_MANY_PHOTOS") }
            else { Issue.record("got \(error)") }
        }
    }
}
