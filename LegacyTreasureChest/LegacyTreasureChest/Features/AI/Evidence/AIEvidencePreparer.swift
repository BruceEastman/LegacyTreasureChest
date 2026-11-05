//
//  AIEvidencePreparer.swift
//  LegacyTreasureChest
//
//  Prepares Improve with AI evidence in memory:
//  - the item's primary photo (always, when present),
//  - explicitly selected additional photos (up to 3, in the order selected),
//  - one explicitly selected document: a PDF rendered page by page to JPEG
//    (first 10 pages), or an image document as one page.
//
//  Photos are downsampled with ImageIO (the full-size image is never decoded)
//  and re-encoded as JPEG without metadata, so location and camera details are
//  not uploaded. Rendered pages exist only in memory; nothing is written to
//  disk. Rendering a page does not remove what is printed on it.
//
//  If the result is over the upload budget, everything is re-encoded at lower
//  quality and then smaller sizes; if it is still over, preparation fails with
//  a clear error rather than dropping anything.
//

import Foundation
import ImageIO
import PDFKit
import SwiftData
import UIKit
import UniformTypeIdentifiers

// MARK: - Media access

/// Where attachment files live. The app uses MediaStorage; tests supply files
/// in a temporary directory.
nonisolated protocol AIEvidenceMediaSource: Sendable {
    func fileURL(forRelativePath path: String) -> URL
}

/// MediaStorage-backed files. Captures the media root on the main actor so
/// file URLs can be resolved during off-main preparation.
nonisolated struct StoredMediaSource: AIEvidenceMediaSource {
    let baseDirectory: URL

    @MainActor
    init() {
        baseDirectory = MediaStorage.baseDirectory
    }

    func fileURL(forRelativePath path: String) -> URL {
        baseDirectory.appendingPathComponent(path)
    }
}

// MARK: - Preparer

nonisolated struct AIEvidencePreparer: Sendable {

    var limits: AIEvidenceLimits
    var media: any AIEvidenceMediaSource

    @MainActor
    init(limits: AIEvidenceLimits = .standard, media: (any AIEvidenceMediaSource)? = nil) {
        self.limits = limits
        self.media = media ?? StoredMediaSource()
    }

    /// Plain values captured from the item on the main actor, so preparation
    /// can run off the main thread without touching SwiftData objects.
    struct Snapshot: Sendable {
        struct Photo: Sendable { let id: UUID; let path: String }
        struct Doc: Sendable { let id: UUID; let path: String; let type: String; let name: String }

        let primary: Photo?
        let selectedPhotos: [Photo]
        let selectedDocuments: [Doc]
    }

    // MARK: Snapshot + validation (main actor)

    /// Validates the selection against the item and captures file paths.
    @MainActor
    func snapshot(for item: LTCItem, selection: AIEvidenceSelection) throws -> Snapshot {
        let primary = item.primaryImage
        let primaryID = primary?.imageId

        // The primary photo is always included, so selecting it again is ignored;
        // duplicates keep their first position.
        var seen = Set<UUID>()
        let photoIDs = selection.supplementaryImageIDs.filter { id in
            id != primaryID && seen.insert(id).inserted
        }
        guard photoIDs.count <= limits.maxSupplementaryPhotos else {
            throw AIEvidenceError.tooManyPhotos(max: limits.maxSupplementaryPhotos)
        }

        let liveImages = item.images.filter { !$0.isDeleted }
        let photos: [Snapshot.Photo] = try photoIDs.map { id in
            guard let image = liveImages.first(where: { $0.imageId == id }) else {
                throw AIEvidenceError.photoNotFound
            }
            return Snapshot.Photo(id: id, path: image.filePath)
        }

        var seenDocs = Set<UUID>()
        let documentIDs = selection.documentIDs.filter { seenDocs.insert($0).inserted }
        guard documentIDs.count <= limits.maxDocuments else {
            throw AIEvidenceError.tooManyDocuments(max: limits.maxDocuments)
        }
        let liveDocuments = item.documents.filter { !$0.isDeleted }
        let documents: [Snapshot.Doc] = try documentIDs.map { id in
            guard let doc = liveDocuments.first(where: { $0.documentId == id }) else {
                throw AIEvidenceError.documentNotFound
            }
            let name = (doc.originalFilename?.isEmpty == false) ? doc.originalFilename! : (doc.filePath as NSString).lastPathComponent
            return Snapshot.Doc(id: id, path: doc.filePath, type: doc.documentType, name: name)
        }

        return Snapshot(
            primary: primary.map { Snapshot.Photo(id: $0.imageId, path: $0.filePath) },
            selectedPhotos: photos,
            selectedDocuments: documents
        )
    }

    // MARK: Plan (no rendering)

    /// What will be sent, for display before analysis. Opens selected PDFs to
    /// read their page count (and fails early on locked or unreadable files).
    @MainActor
    func plan(for item: LTCItem, selection: AIEvidenceSelection) throws -> AIEvidencePlan {
        try plan(for: snapshot(for: item, selection: selection))
    }

    func plan(for snapshot: Snapshot) throws -> AIEvidencePlan {
        let docs = try snapshot.selectedDocuments.map { doc -> AIEvidencePlan.DocumentPlan in
            let total = try pageCount(of: doc)
            return AIEvidencePlan.DocumentPlan(
                documentId: doc.id,
                displayName: doc.name,
                totalPages: total,
                pagesToSend: min(total, limits.maxDocumentPages)
            )
        }
        return AIEvidencePlan(
            includesPrimaryPhoto: snapshot.primary != nil,
            supplementaryImageIDs: snapshot.selectedPhotos.map(\.id),
            documents: docs
        )
    }

    // MARK: Prepare (renders; runs off the main actor)

    @MainActor
    func prepare(for item: LTCItem, selection: AIEvidenceSelection) async throws -> PreparedEvidence {
        let snapshot = try snapshot(for: item, selection: selection)
        let preparer = self
        return try await Task.detached(priority: .userInitiated) {
            try preparer.prepare(snapshot)
        }.value
    }

    /// Encoding settings tried in order until the upload fits the budget.
    struct EncodingLevel: Equatable {
        let photoLongSide: CGFloat
        let pageLongSide: CGFloat
        let photoQuality: CGFloat
        let pageQuality: CGFloat
    }

    var encodingLevels: [EncodingLevel] {
        [
            EncodingLevel(photoLongSide: limits.photoMaxLongSide, pageLongSide: limits.pageMaxLongSide,
                          photoQuality: limits.photoJPEGQuality, pageQuality: limits.pageJPEGQuality),
            EncodingLevel(photoLongSide: limits.photoMaxLongSide, pageLongSide: limits.pageMaxLongSide,
                          photoQuality: 0.65, pageQuality: 0.6),
            EncodingLevel(photoLongSide: min(1600, limits.photoMaxLongSide), pageLongSide: min(1920, limits.pageMaxLongSide),
                          photoQuality: 0.6, pageQuality: 0.55),
            EncodingLevel(photoLongSide: min(1280, limits.photoMaxLongSide), pageLongSide: min(1600, limits.pageMaxLongSide),
                          photoQuality: 0.5, pageQuality: 0.5),
        ]
    }

    func prepare(_ snapshot: Snapshot) throws -> PreparedEvidence {
        let plan = try plan(for: snapshot)
        var lastSize = 0

        for level in encodingLevels {
            try Task.checkCancellation()
            let prepared = try encode(snapshot, plan: plan, level: level)
            lastSize = prepared.totalBytes
            if lastSize <= limits.totalUploadBudgetBytes {
                return prepared
            }
        }
        throw AIEvidenceError.uploadTooLarge(bytes: lastSize, limit: limits.totalUploadBudgetBytes)
    }

    private func encode(_ snapshot: Snapshot, plan: AIEvidencePlan, level: EncodingLevel) throws -> PreparedEvidence {
        let primaryJPEG: Data? = try snapshot.primary.map { photo in
            try Self.downsampledJPEG(at: media.fileURL(forRelativePath: photo.path),
                                     maxLongSide: level.photoLongSide, quality: level.photoQuality)
        }

        var items: [SupplementaryEvidenceDTO] = []
        for photo in snapshot.selectedPhotos {
            try Task.checkCancellation()
            let jpeg = try Self.downsampledJPEG(at: media.fileURL(forRelativePath: photo.path),
                                                maxLongSide: level.photoLongSide, quality: level.photoQuality)
            items.append(.photo(jpeg))
        }

        for (offset, doc) in snapshot.selectedDocuments.enumerated() {
            let number = offset + 1
            let url = media.fileURL(forRelativePath: doc.path)
            if Self.isPDF(doc) {
                let rendered = try Self.renderPDFPages(at: url, maxPages: limits.maxDocumentPages,
                                                       maxLongSide: level.pageLongSide, quality: level.pageQuality)
                for (index, page) in rendered.pages.enumerated() {
                    items.append(.documentPage(page, document: number, page: index + 1, of: rendered.totalPages))
                }
            } else {
                let jpeg = try Self.downsampledJPEG(at: url, maxLongSide: level.pageLongSide,
                                                    quality: level.pageQuality, unreadable: .documentUnreadable)
                items.append(.documentPage(jpeg, document: number, page: 1, of: 1))
            }
        }

        return PreparedEvidence(primaryJPEG: primaryJPEG, supplementary: items, plan: plan)
    }

    // MARK: - Documents

    static func isPDF(_ doc: Snapshot.Doc) -> Bool {
        if doc.type.uppercased() == "PDF" { return true }
        return UTType(filenameExtension: (doc.path as NSString).pathExtension)?.conforms(to: .pdf) ?? false
    }

    static func isImage(_ doc: Snapshot.Doc) -> Bool {
        if doc.type.uppercased() == "IMAGE" { return true }
        return UTType(filenameExtension: (doc.path as NSString).pathExtension)?.conforms(to: .image) ?? false
    }

    private func pageCount(of doc: Snapshot.Doc) throws -> Int {
        if Self.isPDF(doc) {
            let pdf = try Self.openPDF(at: media.fileURL(forRelativePath: doc.path))
            return pdf.pageCount
        }
        guard Self.isImage(doc) else { throw AIEvidenceError.documentUnsupportedType }
        return 1
    }

    static func openPDF(at url: URL) throws -> PDFDocument {
        guard let pdf = PDFDocument(url: url) else { throw AIEvidenceError.documentUnreadable }
        if pdf.isLocked { throw AIEvidenceError.documentLocked }
        guard pdf.pageCount > 0 else { throw AIEvidenceError.documentHasNoPages }
        return pdf
    }

    /// Renders the first `maxPages` pages to JPEG on a white background.
    /// Returns the JPEGs (in page order) and the document's total page count.
    static func renderPDFPages(at url: URL, maxPages: Int, maxLongSide: CGFloat,
                               quality: CGFloat) throws -> (pages: [Data], totalPages: Int) {
        let pdf = try openPDF(at: url)
        let total = pdf.pageCount
        var pages: [Data] = []

        for index in 0..<min(total, maxPages) {
            try Task.checkCancellation()
            let data: Data? = autoreleasepool {
                guard let page = pdf.page(at: index) else { return nil }
                var size = page.bounds(for: .mediaBox).size
                if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
                guard size.width > 0, size.height > 0 else { return nil }

                let scale = maxLongSide / max(size.width, size.height)
                let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
                let thumbnail = page.thumbnail(of: target, for: .mediaBox)

                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let image = UIGraphicsImageRenderer(size: thumbnail.size, format: format).image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: thumbnail.size))
                    thumbnail.draw(at: .zero)
                }
                guard let cg = image.cgImage else { return nil }
                return jpegData(from: cg, quality: quality)
            }
            guard let data else { throw AIEvidenceError.documentUnreadable }
            pages.append(data)
        }
        return (pages, total)
    }

    // MARK: - Images

    /// Downsamples the image file so its long side is at most `maxLongSide`
    /// (never upscaled), applies its orientation, and encodes a metadata-free
    /// JPEG.
    static func downsampledJPEG(at url: URL, maxLongSide: CGFloat, quality: CGFloat,
                                unreadable: AIEvidenceError = .photoUnreadable) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxLongSide.rounded())),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let data = jpegData(from: image, quality: quality) else {
            throw unreadable
        }
        return data
    }

    /// JPEG without any metadata (no EXIF, GPS or camera details).
    static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
