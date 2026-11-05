//
//  ImproveWithAIModelTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 4: the Improve with AI sheet's state (selection, plan, analysis,
//  review, cancellation). The analyzer is injected; nothing reaches a network.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

@MainActor
@Suite(.serialized)
struct ImproveWithAIModelTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    final class Calls { var requests: [ItemAnalysisRequest] = [] }

    private struct Fixture {
        let media: TempMedia
        let context: ModelContext
        let item: LTCItem
        let photos: [ItemImage]      // supplementary, oldest first
    }

    private func fixture(photos: Int = 4, primary: Bool = true, description: String = "Cherry stool.",
                         quantity: Int = 1) throws -> Fixture {
        let media = try TempMedia()
        let context = ModelContext(try ModelContainer(for: LTCItem.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let item = LTCItem(name: "Stools", itemDescription: description, category: "Furniture", quantity: quantity)
        context.insert(item)
        var extras: [ItemImage] = []
        let count = photos + (primary ? 1 : 0)
        for i in 0..<count {
            let image = ItemImage(filePath: try media.writeJPEG("p\(i).jpg", width: 400, height: 300),
                                  createdAt: t0.addingTimeInterval(Double(i)))
            image.item = item
            item.images.append(image)
            context.insert(image)
            if !primary || i > 0 { extras.append(image) }
        }
        return Fixture(media: media, context: context, item: item, photos: extras)
    }

    private func addDocument(_ f: Fixture, pages: Int, locked: Bool = false, name: String = "appraisal.pdf") throws -> Document {
        let doc = Document(filePath: try f.media.writePDF(name, pages: pages, password: locked ? "pw" : nil),
                           documentType: "PDF", originalFilename: name)
        doc.item = f.item
        f.item.documents.append(doc)
        f.context.insert(doc)
        return doc
    }

    private func model(_ f: Fixture, calls: Calls? = nil,
                       analyzer: ImproveWithAIModel.Analyzer? = nil) -> ImproveWithAIModel {
        let calls = calls ?? Calls()
        return ImproveWithAIModel(
            item: f.item,
            preparer: AIEvidencePreparer(media: f.media),
            analyzer: analyzer ?? { request in
                calls.requests.append(request)
                return ItemAnalysis(title: "Suggested", summary: "Suggested paragraph.", category: "Furniture",
                                    valueHints: ValueHints(valueLow: 100, estimatedValue: 150, valueHigh: 200),
                                    brand: "Sample Maker Co.", valuationUnit: "one stool")
            }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func isReview(_ m: ImproveWithAIModel) -> Bool { if case .review = m.phase { return true }; return false }
    private func isCompose(_ m: ImproveWithAIModel) -> Bool { if case .compose = m.phase { return true }; return false }

    // MARK: Selection

    @Test func startsWithPrimaryOnlyAndNothingSelected() throws {
        let f = try fixture(); defer { f.media.remove() }
        let m = model(f)
        #expect(m.plan?.includesPrimaryPhoto == true)
        #expect(m.selectedPhotoIDs.isEmpty && m.selectedDocumentID == nil)
        #expect(!m.requiresEvidenceDisclosure)
        #expect(m.canAnalyze)
    }

    @Test func photoSelectionLimitAndDeselect() throws {
        let f = try fixture(); defer { f.media.remove() }
        let m = model(f)
        for photo in f.photos.prefix(3) { #expect(m.togglePhoto(photo.imageId)) }
        #expect(!m.togglePhoto(f.photos[3].imageId))           // a 4th is refused
        #expect(m.selectedPhotoIDs.count == 3)
        #expect(m.plan?.supplementaryPhotoCount == 3)
        #expect(m.togglePhoto(f.photos[0].imageId))             // deselect
        #expect(m.selectedPhotoIDs == [f.photos[1].imageId, f.photos[2].imageId])
        #expect(m.requiresEvidenceDisclosure)
    }

    @Test func primaryPhotoIsNeverASupplementarySelection() throws {
        let f = try fixture(photos: 1); defer { f.media.remove() }
        let m = model(f)
        m.didImportPhotos([f.item.primaryImage!, f.photos[0]])
        #expect(m.selectedPhotoIDs == [f.photos[0].imageId])
    }

    @Test func importedPhotosAreSelectedUpToTheLimit() throws {
        let f = try fixture(photos: 5); defer { f.media.remove() }
        let m = model(f)
        m.togglePhoto(f.photos[0].imageId)
        m.didImportPhotos(Array(f.photos[1...4]))
        #expect(m.selectedPhotoIDs.count == 3)
        #expect(f.item.images.count == 6)                        // all stay attached
    }

    @Test func oneDocumentAtATime() throws {
        let f = try fixture(); defer { f.media.remove() }
        let a = try addDocument(f, pages: 2, name: "a.pdf")
        let b = try addDocument(f, pages: 3, name: "b.pdf")
        let m = model(f)
        m.toggleDocument(a.documentId)
        #expect(m.selectedDocumentID == a.documentId)
        m.toggleDocument(b.documentId)
        #expect(m.selectedDocumentID == b.documentId)
        #expect(m.plan?.documentPageCount == 3)
        m.toggleDocument(b.documentId)
        #expect(m.selectedDocumentID == nil)
    }

    @Test func longPdfNeedsAcknowledgement() throws {
        let f = try fixture(); defer { f.media.remove() }
        let long = try addDocument(f, pages: 12, name: "long.pdf")
        let short = try addDocument(f, pages: 2, name: "short.pdf")
        let m = model(f)
        m.selectDocument(long.documentId)
        #expect(m.needsTruncationAcknowledgement)
        #expect(!m.canAnalyze)
        m.acknowledgedTruncation = true
        #expect(m.canAnalyze)
        m.selectDocument(short.documentId)                        // resets
        #expect(!m.acknowledgedTruncation && !m.needsTruncationAcknowledgement && m.canAnalyze)
        m.selectDocument(long.documentId)
        #expect(!m.canAnalyze)
    }

    @Test func lockedPdfBlocksAnalysisWithMessage() throws {
        let f = try fixture(); defer { f.media.remove() }
        let locked = try addDocument(f, pages: 2, locked: true, name: "locked.pdf")
        let m = model(f)
        m.selectDocument(locked.documentId)
        #expect(m.planError == .documentLocked)
        #expect(!m.canAnalyze)
    }

    @Test func noPhotoNoTextCannotAnalyzeUntilSomethingIsAdded() throws {
        let f = try fixture(photos: 0, primary: false, description: ""); defer { f.media.remove() }
        f.item.name = ""
        let m = model(f)
        #expect(m.plan?.isTextOnly == true)
        #expect(!m.canAnalyze)
        f.item.valuation = ItemValuation(userNotes: "Owner notes")
        m.refreshPlan()
        #expect(m.canAnalyze)
    }

    // MARK: Analysis

    @Test func successfulAnalysisMovesToReviewWithDefaultsAndSendsSelection() async throws {
        let f = try fixture(); defer { f.media.remove() }
        let doc = try addDocument(f, pages: 2)
        let calls = Calls()
        let m = model(f, calls: calls)
        m.togglePhoto(f.photos[0].imageId)
        m.selectDocument(doc.documentId)
        m.startAnalysis()
        await waitUntil { isReview(m) }
        #expect(isReview(m))
        let request = try #require(calls.requests.first)
        #expect(request.primaryJPEG != nil)
        #expect(request.supplementaryPhotoCount == 1 && request.documentPageCount == 2)
        #expect(m.analyzedWithDocument)
        #expect(m.choices.paragraph == .keep)                     // document: no text preselected
        #expect(f.item.name == "Stools")                          // nothing applied yet
    }

    @Test func doubleStartSubmitsOnce() async throws {
        let f = try fixture(); defer { f.media.remove() }
        let calls = Calls()
        let m = model(f, calls: calls)
        m.startAnalysis()
        m.startAnalysis()
        await waitUntil { isReview(m) }
        #expect(calls.requests.count == 1)
    }

    @Test func failureReturnsToComposeWithMessageAndNoChanges() async throws {
        let f = try fixture(); defer { f.media.remove() }
        let m = model(f, analyzer: { _ in throw AIError.evidenceRejected(code: "EVIDENCE_TOO_MANY_PAGES", requestID: "abc12345") })
        m.startAnalysis()
        await waitUntil { isCompose(m) && m.errorMessage != nil }
        #expect(m.errorMessage?.contains("Too many document pages") == true)
        #expect(f.item.name == "Stools" && f.item.itemDescription == "Cherry stool.")

        let mismatch = model(f, analyzer: { _ in throw AIError.evidenceNotProcessed })
        mismatch.startAnalysis()
        await waitUntil { mismatch.errorMessage != nil }
        #expect(mismatch.errorMessage?.contains("weren't used") == true)
    }

    @Test func cancellingReturnsToComposeWithNoChanges() async throws {
        let f = try fixture(); defer { f.media.remove() }
        let m = model(f, analyzer: { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return ItemAnalysis(title: "Late", summary: "Late", category: "Furniture")
        })
        m.startAnalysis()
        await waitUntil { m.isAnalyzing }
        try await Task.sleep(nanoseconds: 100_000_000)
        m.cancelAnalysis()
        await waitUntil { isCompose(m) }
        #expect(isCompose(m))
        #expect(m.errorMessage == AIError.cancelled.localizedDescription)
        #expect(f.item.name == "Stools")
    }

    // MARK: Review

    @Test func applyUsesOnlyChosenFields() async throws {
        let f = try fixture(); defer { f.media.remove() }
        f.item.value = 90
        let m = model(f)
        m.startAnalysis()
        await waitUntil { isReview(m) }
        m.choices = ItemAnalysisApplier.Choices()
        m.choices.valuation = true
        #expect(m.apply())
        #expect(f.item.value == 150)
        #expect(f.item.name == "Stools")
        #expect(f.item.itemDescription == "Cherry stool.")
    }

    /// Applying every suggestion, including an allocated group valuation, must
    /// not delete, detach or alter the item's photos or documents.
    @Test func applyingEverythingKeepsPhotosAndDocuments() async throws {
        let f = try fixture(photos: 3, quantity: 4); defer { f.media.remove() }
        let doc = try addDocument(f, pages: 2)
        func snapshot(_ item: LTCItem) -> [String] {
            item.images.map { "\($0.imageId)|\($0.filePath)|\($0.createdAt.timeIntervalSince1970)" }.sorted()
                + item.documents.map { "\($0.documentId)|\($0.filePath)|\($0.documentType)|\($0.originalFilename ?? "")" }.sorted()
        }
        let before = snapshot(f.item)
        let primaryBefore = f.item.primaryImage?.imageId

        let m = model(f, analyzer: { _ in
            ItemAnalysis(title: "Suggested", summary: "Suggested paragraph.", category: "Furniture",
                         valueHints: ValueHints(valueLow: 600, estimatedValue: 800, valueHigh: 1000, aiNotes: "Group."),
                         brand: "Sample Maker Co.", materials: ["oak"], valuationUnit: "set of four stools")
        })
        m.togglePhoto(f.photos[0].imageId)
        m.selectDocument(doc.documentId)
        m.startAnalysis()
        await waitUntil { isReview(m) }
        #expect(isReview(m))

        m.choices.title = true
        m.choices.category = true
        m.choices.paragraph = .useAI
        m.choices.attributeLabels = ["Brand", "Materials"]
        m.choices.valuation = true
        #expect(m.apply())
        try f.context.save()

        #expect(f.item.name == "Suggested" && f.item.value == 200)   // the apply really happened
        #expect(snapshot(f.item) == before)
        #expect(f.item.images.count == 4 && f.item.documents.count == 1)
        #expect(f.item.primaryImage?.imageId == primaryBefore)
        #expect(f.item.images.allSatisfy { $0.item === f.item && !$0.isDeleted })
        #expect(f.item.documents.allSatisfy { $0.item === f.item && !$0.isDeleted })
        for path in f.item.images.map(\.filePath) + f.item.documents.map(\.filePath) {
            #expect(FileManager.default.fileExists(atPath: f.media.fileURL(forRelativePath: path).path))
        }
    }

    @Test func discardingReviewChangesNothingAndKeepsAttachments() async throws {
        let f = try fixture(); defer { f.media.remove() }
        let doc = try addDocument(f, pages: 1)
        let m = model(f)
        m.didImportDocument(doc)
        m.startAnalysis()
        await waitUntil { isReview(m) }
        m.discardReview()
        #expect(isCompose(m))
        #expect(!m.apply())                                       // nothing to apply outside review
        #expect(f.item.name == "Stools")
        #expect(f.item.documents.count == 1)
        #expect(m.selectedDocumentID == doc.documentId)           // selection kept for another try
    }
}
