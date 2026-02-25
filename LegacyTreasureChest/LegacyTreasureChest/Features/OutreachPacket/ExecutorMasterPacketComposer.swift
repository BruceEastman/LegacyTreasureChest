//
//  ExecutorMasterPacketComposer.swift
//  LegacyTreasureChest
//
//  Composes an Executor Master Packet snapshot from the full estate dataset.
//  v1: no network calls. Uses persisted data only.
//

import Foundation
import SwiftData

enum ExecutorMasterPacketComposer {

    struct InclusionOptions: Equatable {
        var includeAudio: Bool
        var includeSupportingDocs: Bool
        var includeImages: Bool
        /// If includeImages is true, this determines “all images vs selected (primary-only)”.
        var includeFullResolutionImages: Bool

        static let pdfOnly = InclusionOptions(
            includeAudio: false,
            includeSupportingDocs: false,
            includeImages: false,
            includeFullResolutionImages: false
        )
    }

    struct Snapshot {
        let estateDisplayName: String
        let generatedAt: Date

        let itemCount: Int
        let setCount: Int
        let batchCount: Int

        let audioIndex: [AudioRef]
        let documentIndex: [DocumentRef]
        let imageIndex: [ImageRef]
    }

    struct AudioRef: Identifiable {
        let id: String
        let itemName: String
        let duration: Double
        let relativePath: String
        let bundleFilename: String
        let summaryText: String?
    }

    struct DocumentRef: Identifiable {
        let id: String
        let itemName: String
        let documentType: String
        let originalFilename: String?
        let relativePath: String
        let bundleFilename: String
    }

    struct ImageRef: Identifiable {
        let id: String
        let itemName: String
        let relativePath: String
        let bundleFilename: String
        let isPrimary: Bool
    }

    static func composeWithAssetIndexes(
        estateDisplayName: String,
        generatedAt: Date = Date(),
        items: [LTCItem],
        itemSets: [LTCItemSet],
        batches: [LiquidationBatch],
        options: InclusionOptions
    ) -> Snapshot {

        let orderedItems = items.sorted {
            if $0.category == $1.category {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending
        }

        let audioIndex = options.includeAudio ? buildAudioIndexFromModels(itemsInOrder: orderedItems) : []
        let documentIndex = options.includeSupportingDocs ? buildDocumentIndexFromModels(itemsInOrder: orderedItems) : []
        let imageIndex: [ImageRef] = {
            guard options.includeImages else { return [] }
            return buildImageIndexFromModels(itemsInOrder: orderedItems, includeAllImages: options.includeFullResolutionImages)
        }()

        return Snapshot(
            estateDisplayName: estateDisplayName,
            generatedAt: generatedAt,
            itemCount: items.count,
            setCount: itemSets.count,
            batchCount: batches.count,
            audioIndex: audioIndex,
            documentIndex: documentIndex,
            imageIndex: imageIndex
        )
    }

    // MARK: - Model-backed asset indexes

    private static func buildAudioIndexFromModels(itemsInOrder: [LTCItem]) -> [AudioRef] {
        var result: [AudioRef] = []
        var counter = 1

        for item in itemsInOrder {
            let itemName = item.name.isEmpty ? "Unnamed Item" : item.name

            for recording in item.audioRecordings {
                let rel = recording.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rel.isEmpty else { continue }

                let prefix = String(format: "%04d", counter)
                let sanitizedItem = sanitizeFilename(itemName)

                let ext = (rel as NSString).pathExtension
                let suffixExt = ext.isEmpty ? "m4a" : ext
                let bundleFilename = "\(prefix)_\(sanitizedItem).\(suffixExt)"

                let summary: String? = {
                    let status = recording.summaryStatusRaw ?? "missing"
                    let text = recording.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if status == "ready", let text, !text.isEmpty { return text }
                    if let text, !text.isEmpty { return text }
                    return nil
                }()

                result.append(
                    AudioRef(
                        id: recording.audioRecordingId.uuidString,
                        itemName: itemName,
                        duration: recording.duration,
                        relativePath: rel,
                        bundleFilename: bundleFilename,
                        summaryText: summary
                    )
                )

                counter += 1
            }
        }

        return result
    }

    private static func buildDocumentIndexFromModels(itemsInOrder: [LTCItem]) -> [DocumentRef] {
        var result: [DocumentRef] = []
        var counter = 1

        for item in itemsInOrder {
            let itemName = item.name.isEmpty ? "Unnamed Item" : item.name
            let docs = item.documents.sorted { $0.createdAt < $1.createdAt }

            for doc in docs {
                let rel = doc.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rel.isEmpty else { continue }

                let prefix = String(format: "%04d", counter)
                let sanitizedItem = sanitizeFilename(itemName)
                let sanitizedType = sanitizeFilename(doc.documentType.isEmpty ? "Document" : doc.documentType)

                let extFromOriginal = ((doc.originalFilename ?? "") as NSString).pathExtension
                let extFromPath = (rel as NSString).pathExtension
                let ext = !extFromOriginal.isEmpty ? extFromOriginal : extFromPath
                let finalExt = ext.isEmpty ? "dat" : ext

                let bundleFilename = "\(prefix)_\(sanitizedItem)_\(sanitizedType).\(finalExt)"

                result.append(
                    DocumentRef(
                        id: doc.documentId.uuidString,
                        itemName: itemName,
                        documentType: doc.documentType,
                        originalFilename: doc.originalFilename,
                        relativePath: rel,
                        bundleFilename: bundleFilename
                    )
                )

                counter += 1
            }
        }

        return result
    }

    private static func buildImageIndexFromModels(itemsInOrder: [LTCItem], includeAllImages: Bool) -> [ImageRef] {
        var result: [ImageRef] = []
        var counter = 1

        for item in itemsInOrder {
            let itemName = item.name.isEmpty ? "Unnamed Item" : item.name
            let sanitizedItem = sanitizeFilename(itemName)

            let sortedImages = item.images.sorted { $0.createdAt < $1.createdAt }
            guard !sortedImages.isEmpty else { continue }

            let primaryIdString: String? = sortedImages.first?.imageId.uuidString
            let chosenImages = includeAllImages ? sortedImages : Array(sortedImages.prefix(1))

            for img in chosenImages {
                let rel = img.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rel.isEmpty else { continue }

                let prefix = String(format: "%04d", counter)
                let ext = (rel as NSString).pathExtension
                let finalExt = ext.isEmpty ? "jpg" : ext

                let bundleFilename = "\(prefix)_\(sanitizedItem).\(finalExt)"
                let imgIdString = img.imageId.uuidString
                let isPrimary = (imgIdString == primaryIdString)

                result.append(
                    ImageRef(
                        id: imgIdString,
                        itemName: itemName,
                        relativePath: rel,
                        bundleFilename: bundleFilename,
                        isPrimary: isPrimary
                    )
                )

                counter += 1
            }
        }

        return result
    }

    // MARK: - Helpers

    private static func sanitizeFilename(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Item" }

        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let underscore: UnicodeScalar = "_"

        let cleanedScalars = trimmed.unicodeScalars.map { scalar -> UnicodeScalar in
            invalid.contains(scalar) ? underscore : scalar
        }

        let cleaned = String(String.UnicodeScalarView(cleanedScalars))
        let collapsed = cleaned.replacingOccurrences(of: " ", with: "_")
        return String(collapsed.prefix(60))
    }
}
