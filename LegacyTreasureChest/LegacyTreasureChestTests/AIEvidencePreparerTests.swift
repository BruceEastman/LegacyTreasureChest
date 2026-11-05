//
//  AIEvidencePreparerTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 3: preparing Improve with AI evidence. Synthetic images and PDFs
//  in a temporary folder; in-memory SwiftData; no network.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

@MainActor
@Suite(.serialized)
struct AIEvidencePreparerTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: LTCItem.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func makeItem(_ context: ModelContext, quantity: Int = 1) -> LTCItem {
        let item = LTCItem(name: "Synthetic stool", itemDescription: "", category: "Furniture", quantity: quantity)
        context.insert(item)
        return item
    }

    @discardableResult
    private func addPhoto(_ path: String, offset: TimeInterval, to item: LTCItem, _ context: ModelContext) -> ItemImage {
        let image = ItemImage(filePath: path, createdAt: t0.addingTimeInterval(offset))
        image.item = item
        item.images.append(image)
        context.insert(image)
        return image
    }

    @discardableResult
    private func addDocument(_ path: String, type: String, to item: LTCItem, _ context: ModelContext) -> Document {
        let doc = Document(filePath: path, documentType: type, originalFilename: path)
        doc.item = item
        item.documents.append(doc)
        context.insert(doc)
        return doc
    }

    // MARK: Primary photo and selection

    @Test func primaryPhotoIsIncludedAutomatically() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        addPhoto(try media.writeJPEG("creation.jpg", width: 1200, height: 900), offset: 0, to: item, context)
        addPhoto(try media.writeJPEG("stamp.jpg", width: 900, height: 900), offset: 60, to: item, context)

        let prepared = try await AIEvidencePreparer(media: media).prepare(for: item, selection: AIEvidenceSelection())
        #expect(prepared.primaryJPEG != nil)
        #expect(imagePixelSize(prepared.primaryJPEG!) == CGSize(width: 1200, height: 900))
        #expect(prepared.supplementary.isEmpty)          // later photos only when selected
        #expect(prepared.plan.includesPrimaryPhoto)
        #expect(!prepared.plan.hasSupplementaryEvidence)
    }

    @Test func selectedPhotosKeepSelectionOrder() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        addPhoto(try media.writeJPEG("p0.jpg", width: 500, height: 500), offset: 0, to: item, context)
        let a = addPhoto(try media.writeJPEG("a.jpg", width: 600, height: 400), offset: 10, to: item, context)
        let b = addPhoto(try media.writeJPEG("b.jpg", width: 800, height: 300), offset: 20, to: item, context)

        let selection = AIEvidenceSelection(supplementaryImageIDs: [b.imageId, a.imageId])
        let prepared = try await AIEvidencePreparer(media: media).prepare(for: item, selection: selection)
        #expect(prepared.supplementary.map(\.kind) == [.photo, .photo])
        #expect(prepared.supplementary.map { imagePixelSize($0.data) } == [CGSize(width: 800, height: 300),
                                                                          CGSize(width: 600, height: 400)])
        #expect(prepared.plan.supplementaryImageIDs == [b.imageId, a.imageId])
    }

    @Test func primaryAndDuplicatesInSelectionAreIgnored() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        let primary = addPhoto(try media.writeJPEG("p0.jpg", width: 500, height: 500), offset: 0, to: item, context)
        let a = addPhoto(try media.writeJPEG("a.jpg", width: 600, height: 400), offset: 10, to: item, context)

        let selection = AIEvidenceSelection(supplementaryImageIDs: [primary.imageId, a.imageId, a.imageId])
        let prepared = try await AIEvidencePreparer(media: media).prepare(for: item, selection: selection)
        #expect(prepared.supplementary.count == 1)
    }

    @Test func moreThanThreePhotosIsRejected() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        addPhoto(try media.writeJPEG("p0.jpg", width: 100, height: 100), offset: 0, to: item, context)
        var ids: [UUID] = []
        for i in 1...4 {
            ids.append(addPhoto(try media.writeJPEG("p\(i).jpg", width: 100, height: 100), offset: Double(i), to: item, context).imageId)
        }
        await #expect(throws: AIEvidenceError.tooManyPhotos(max: 3)) {
            try await AIEvidencePreparer(media: media).prepare(for: item, selection: AIEvidenceSelection(supplementaryImageIDs: ids))
        }
    }

    @Test func unknownPhotoIsRejected() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        await #expect(throws: AIEvidenceError.photoNotFound) {
            try await AIEvidencePreparer(media: media).prepare(for: item, selection: AIEvidenceSelection(supplementaryImageIDs: [UUID()]))
        }
    }

    @Test func textOnlyItemHasNothingToUpload() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        let prepared = try await AIEvidencePreparer(media: media).prepare(for: item, selection: AIEvidenceSelection())
        #expect(prepared.primaryJPEG == nil)
        #expect(prepared.supplementary.isEmpty)
        #expect(prepared.plan.isTextOnly)
        #expect(prepared.totalBytes == 0)
    }

    @Test func unreadablePhotoIsAClearError() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        addPhoto(try media.writeBytes("broken.jpg", Data("not an image".utf8)), offset: 0, to: item, context)
        await #expect(throws: AIEvidenceError.photoUnreadable) {
            try await AIEvidencePreparer(media: media).prepare(for: item, selection: AIEvidenceSelection())
        }
    }

    // MARK: Resizing and metadata

    @Test func largePhotosAreDownscaledSmallOnesAreNotUpscaled() throws {
        let media = try TempMedia(); defer { media.remove() }
        let big = media.fileURL(forRelativePath: try media.writeJPEG("big.jpg", width: 4032, height: 3024))
        let small = media.fileURL(forRelativePath: try media.writeJPEG("small.jpg", width: 800, height: 600))

        let bigOut = try AIEvidencePreparer.downsampledJPEG(at: big, maxLongSide: 2048, quality: 0.8)
        #expect(imagePixelSize(bigOut) == CGSize(width: 2048, height: 1536))
        let smallOut = try AIEvidencePreparer.downsampledJPEG(at: small, maxLongSide: 2048, quality: 0.8)
        #expect(imagePixelSize(smallOut) == CGSize(width: 800, height: 600))
        #expect(bigOut.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test func locationMetadataIsNotUploaded() throws {
        let media = try TempMedia(); defer { media.remove() }
        let url = media.fileURL(forRelativePath: try media.writeJPEG("gps.jpg", width: 1000, height: 800, gps: true))
        #expect(imageHasGPS(try Data(contentsOf: url)))   // the source has GPS
        let out = try AIEvidencePreparer.downsampledJPEG(at: url, maxLongSide: 2048, quality: 0.8)
        #expect(!imageHasGPS(out))
    }

    // MARK: Documents

    @Test func pdfPagesAreRenderedInOrder() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        let doc = addDocument(try media.writePDF("appraisal.pdf", pages: 3), type: "PDF", to: item, context)

        let prepared = try await AIEvidencePreparer(media: media)
            .prepare(for: item, selection: AIEvidenceSelection(documentIDs: [doc.documentId]))
        #expect(prepared.primaryJPEG == nil)
        #expect(prepared.supplementary.map(\.kind) == [.documentPage, .documentPage, .documentPage])
        #expect(prepared.supplementary.map(\.page) == [1, 2, 3])
        #expect(prepared.supplementary.allSatisfy { $0.pageCount == 3 && $0.documentIndex == 1 })
        for page in prepared.supplementary {
            #expect(page.data.starts(with: [0xFF, 0xD8, 0xFF]))
            let size = imagePixelSize(page.data)!
            #expect(max(size.width, size.height) == 2400)        // pilot setting
        }
    }

    @Test func longPdfIsTruncatedToTenPagesAndReportedBeforeAnalysis() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        let doc = addDocument(try media.writePDF("long.pdf", pages: 12), type: "PDF", to: item, context)
        let selection = AIEvidenceSelection(documentIDs: [doc.documentId])

        let plan = try AIEvidencePreparer(media: media).plan(for: item, selection: selection)
        #expect(plan.documents.first?.totalPages == 12)
        #expect(plan.documents.first?.pagesToSend == 10)
        #expect(plan.documents.first?.isTruncated == true)
        #expect(plan.truncatedDocuments.count == 1)

        let prepared = try await AIEvidencePreparer(media: media).prepare(for: item, selection: selection)
        #expect(prepared.documentPageCount == 10)
        #expect(prepared.supplementary.last?.page == 10)
        #expect(prepared.supplementary.last?.pageCount == 12)
    }

    @Test func lockedMalformedAndUnsupportedDocuments() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        let locked = addDocument(try media.writePDF("locked.pdf", pages: 2, password: "secret"), type: "PDF", to: item, context)
        let broken = addDocument(try media.writeBytes("broken.pdf", Data("%PDF-garbage".utf8)), type: "PDF", to: item, context)
        let text = addDocument(try media.writeBytes("notes.txt", Data("hello".utf8)), type: "TXT", to: item, context)
        let preparer = AIEvidencePreparer(media: media)

        #expect(throws: AIEvidenceError.documentLocked) {
            try preparer.plan(for: item, selection: AIEvidenceSelection(documentIDs: [locked.documentId]))
        }
        #expect(throws: AIEvidenceError.documentUnreadable) {
            try preparer.plan(for: item, selection: AIEvidenceSelection(documentIDs: [broken.documentId]))
        }
        #expect(throws: AIEvidenceError.documentUnsupportedType) {
            try preparer.plan(for: item, selection: AIEvidenceSelection(documentIDs: [text.documentId]))
        }
        await #expect(throws: AIEvidenceError.documentLocked) {
            try await preparer.prepare(for: item, selection: AIEvidenceSelection(documentIDs: [locked.documentId]))
        }
    }

    @Test func imageDocumentIsOnePage() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        let doc = addDocument(try media.writeJPEG("receipt.jpg", width: 3000, height: 4000), type: "Image", to: item, context)
        let prepared = try await AIEvidencePreparer(media: media)
            .prepare(for: item, selection: AIEvidenceSelection(documentIDs: [doc.documentId]))
        #expect(prepared.supplementary.count == 1)
        #expect(prepared.supplementary[0].kind == .documentPage)
        #expect(prepared.supplementary[0].page == 1 && prepared.supplementary[0].pageCount == 1)
        #expect(imagePixelSize(prepared.supplementary[0].data) == CGSize(width: 1800, height: 2400))
    }

    @Test func onlyOneDocumentAllowed() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        let a = addDocument(try media.writePDF("a.pdf", pages: 1), type: "PDF", to: item, context)
        let b = addDocument(try media.writePDF("b.pdf", pages: 1), type: "PDF", to: item, context)
        await #expect(throws: AIEvidenceError.tooManyDocuments(max: 1)) {
            try await AIEvidencePreparer(media: media)
                .prepare(for: item, selection: AIEvidenceSelection(documentIDs: [a.documentId, b.documentId]))
        }
    }

    // MARK: Size budget

    @Test func overBudgetReencodesSmallerAndOtherwiseFailsClearly() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        addPhoto(try media.writeJPEG("noisy0.jpg", width: 3000, height: 2250, noisy: true), offset: 0, to: item, context)
        let extra = addPhoto(try media.writeJPEG("noisy1.jpg", width: 3000, height: 2250, noisy: true), offset: 1, to: item, context)
        let selection = AIEvidenceSelection(supplementaryImageIDs: [extra.imageId])

        let full = try await AIEvidencePreparer(media: media).prepare(for: item, selection: selection)

        var tighter = AIEvidenceLimits.standard
        tighter.totalUploadBudgetBytes = full.totalBytes - 1
        let reduced = try await AIEvidencePreparer(limits: tighter, media: media).prepare(for: item, selection: selection)
        #expect(reduced.totalBytes <= tighter.totalUploadBudgetBytes)
        #expect(reduced.supplementary.count == 1)            // nothing dropped

        var tiny = AIEvidenceLimits.standard
        tiny.totalUploadBudgetBytes = 10_000
        await #expect(throws: AIEvidenceError.self) {
            try await AIEvidencePreparer(limits: tiny, media: media).prepare(for: item, selection: selection)
        }
        do {
            _ = try await AIEvidencePreparer(limits: tiny, media: media).prepare(for: item, selection: selection)
        } catch let error as AIEvidenceError {
            if case .uploadTooLarge(_, let limit) = error { #expect(limit == 10_000) } else { Issue.record("wrong error \(error)") }
        }
    }

    @Test func preparationWritesNoFiles() async throws {
        let media = try TempMedia(); defer { media.remove() }
        let context = try makeContext()
        let item = makeItem(context)
        addPhoto(try media.writeJPEG("p0.jpg", width: 1000, height: 1000), offset: 0, to: item, context)
        let doc = addDocument(try media.writePDF("doc.pdf", pages: 4), type: "PDF", to: item, context)
        let before = media.fileCount()
        _ = try await AIEvidencePreparer(media: media).prepare(for: item, selection: AIEvidenceSelection(documentIDs: [doc.documentId]))
        #expect(media.fileCount() == before)
    }
}
