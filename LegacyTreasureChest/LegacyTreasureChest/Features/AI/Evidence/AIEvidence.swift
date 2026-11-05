//
//  AIEvidence.swift
//  LegacyTreasureChest
//
//  Types for Improve with AI supplementary evidence (LTC 1.3).
//
//  The item's primary photo is always included when it exists. Additional
//  photos and a document are included only when the owner selects them
//  (Stage 4 UI). Evidence is prepared in memory for one request: photos are
//  downscaled, document pages are rendered to JPEG, and nothing new is stored.
//

import Foundation
import CoreGraphics

// MARK: - Limits

/// Approved 1.3 limits and preparation settings. The gateway enforces the
/// same counts independently.
nonisolated struct AIEvidenceLimits: Equatable, Sendable {
    var maxSupplementaryPhotos = 3
    var maxDocuments = 1
    var maxDocumentPages = 10

    /// Long side for the primary and supplementary photos.
    var photoMaxLongSide: CGFloat = 2048
    /// Long side for rendered document pages (the pilot's readable setting).
    var pageMaxLongSide: CGFloat = 2400
    var photoJPEGQuality: CGFloat = 0.8
    var pageJPEGQuality: CGFloat = 0.75

    /// Total decoded bytes (primary + evidence) the app will upload. The
    /// gateway's hard limit is higher; staying under this keeps uploads
    /// reasonable on cellular connections.
    var totalUploadBudgetBytes = 8 * 1024 * 1024

    static let standard = AIEvidenceLimits()
}

// MARK: - Selection

/// What the owner chose to include, in order. The primary photo is never
/// listed here; it is always included when present.
nonisolated struct AIEvidenceSelection: Equatable, Sendable {
    var supplementaryImageIDs: [UUID] = []
    var documentIDs: [UUID] = []

    var isEmpty: Bool { supplementaryImageIDs.isEmpty && documentIDs.isEmpty }

    init(supplementaryImageIDs: [UUID] = [], documentIDs: [UUID] = []) {
        self.supplementaryImageIDs = supplementaryImageIDs
        self.documentIDs = documentIDs
    }
}

// MARK: - Plan (shown to the owner before analysis)

/// What an analysis will send, computed without rendering anything, so the
/// Stage 4 UI can tell the owner before they analyze (for example that only
/// the first 10 of 14 pages of a document will be used).
nonisolated struct AIEvidencePlan: Equatable, Sendable {
    struct DocumentPlan: Equatable, Sendable {
        let documentId: UUID
        let displayName: String
        let totalPages: Int
        let pagesToSend: Int
        var isTruncated: Bool { pagesToSend < totalPages }
    }

    let includesPrimaryPhoto: Bool
    let supplementaryImageIDs: [UUID]
    let documents: [DocumentPlan]

    var supplementaryPhotoCount: Int { supplementaryImageIDs.count }
    var documentPageCount: Int { documents.reduce(0) { $0 + $1.pagesToSend } }
    var hasSupplementaryEvidence: Bool { !supplementaryImageIDs.isEmpty || !documents.isEmpty }
    var isTextOnly: Bool { !includesPrimaryPhoto && !hasSupplementaryEvidence }
    var truncatedDocuments: [DocumentPlan] { documents.filter(\.isTruncated) }
}

// MARK: - Prepared evidence (ready to send)

/// One supplementary image as sent to the gateway. `data` is JPEG bytes and is
/// base64-encoded only when the request body is encoded.
nonisolated struct SupplementaryEvidenceDTO: Encodable, Equatable, Sendable {
    enum Kind: String, Encodable, Sendable {
        case photo
        case documentPage
    }

    let kind: Kind
    let mimeType: String
    let data: Data
    let documentIndex: Int?
    let page: Int?
    let pageCount: Int?

    static func photo(_ jpeg: Data) -> SupplementaryEvidenceDTO {
        SupplementaryEvidenceDTO(kind: .photo, mimeType: "image/jpeg", data: jpeg,
                                 documentIndex: nil, page: nil, pageCount: nil)
    }

    static func documentPage(_ jpeg: Data, document: Int, page: Int, of pageCount: Int) -> SupplementaryEvidenceDTO {
        SupplementaryEvidenceDTO(kind: .documentPage, mimeType: "image/jpeg", data: jpeg,
                                 documentIndex: document, page: page, pageCount: pageCount)
    }

    enum CodingKeys: String, CodingKey {
        case kind, mimeType, dataBase64, documentIndex, page, pageCount
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(mimeType, forKey: .mimeType)
        try c.encode(data.base64EncodedString(), forKey: .dataBase64)
        try c.encodeIfPresent(documentIndex, forKey: .documentIndex)
        try c.encodeIfPresent(page, forKey: .page)
        try c.encodeIfPresent(pageCount, forKey: .pageCount)
    }
}

/// Everything prepared for one analysis request. Held in memory only.
nonisolated struct PreparedEvidence: Sendable {
    let primaryJPEG: Data?
    let supplementary: [SupplementaryEvidenceDTO]
    let plan: AIEvidencePlan

    var totalBytes: Int {
        (primaryJPEG?.count ?? 0) + supplementary.reduce(0) { $0 + $1.data.count }
    }
    var supplementaryPhotoCount: Int { supplementary.filter { $0.kind == .photo }.count }
    var documentPageCount: Int { supplementary.filter { $0.kind == .documentPage }.count }
}

// MARK: - Errors

/// Problems preparing evidence on the device. Messages are safe to show.
nonisolated enum AIEvidenceError: LocalizedError, Equatable {
    case tooManyPhotos(max: Int)
    case tooManyDocuments(max: Int)
    case photoNotFound
    case photoUnreadable
    case documentNotFound
    case documentUnsupportedType
    case documentUnreadable
    case documentLocked
    case documentHasNoPages
    case uploadTooLarge(bytes: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .tooManyPhotos(let max):
            return "You can include up to \(max) additional photos in one analysis."
        case .tooManyDocuments(let max):
            return max == 1
                ? "You can include one document in one analysis."
                : "You can include up to \(max) documents in one analysis."
        case .photoNotFound:
            return "One of the selected photos is no longer attached to this item."
        case .photoUnreadable:
            return "One of the selected photos couldn't be read."
        case .documentNotFound:
            return "The selected document is no longer attached to this item."
        case .documentUnsupportedType:
            return "Only PDF documents and images can be included."
        case .documentUnreadable:
            return "The selected PDF couldn't be opened."
        case .documentLocked:
            return "The selected PDF is password-protected. Remove the password and attach it again."
        case .documentHasNoPages:
            return "The selected PDF has no pages."
        case .uploadTooLarge:
            return "The selected photos and pages are too large to send together. Remove some and try again."
        }
    }
}
