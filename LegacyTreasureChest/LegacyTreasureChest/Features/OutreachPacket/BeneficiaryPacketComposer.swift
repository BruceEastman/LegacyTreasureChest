//
//  BeneficiaryPacketComposer.swift
//  LegacyTreasureChest
//
//  Composes a BeneficiaryPacketSnapshot from a Set, Batch, or explicit Items list.
//  v1: no network calls. Uses persisted data only.
//

import Foundation
import SwiftData

enum BeneficiaryPacketComposer {

    enum Target {
        case set(LTCItemSet)
        case batch(LiquidationBatch)
        case items([LTCItem])

        var displayName: String {
            switch self {
            case .set(let s):
                return s.name.isEmpty ? "Set" : s.name
            case .batch(let b):
                return b.name.isEmpty ? "Batch" : b.name
            case .items(let items):
                return items.count == 1 ? "1 Item" : "\(items.count) Items"
            }
        }
    }

    /// Inclusion toggles for bundle build.
    /// PDF is always included by design.
    struct InclusionOptions: Equatable {
        var includeAudio: Bool
        var includeDocuments: Bool
        /// If true, include *all* images for included items.
        /// If false, include only "selected" images (v1: primary image per item, if present).
        var includeFullResolutionImages: Bool

        static let pdfOnly = InclusionOptions(
            includeAudio: false,
            includeDocuments: false,
            includeFullResolutionImages: false
        )
    }

    // MARK: - Snapshot models (Beneficiary v1)

    struct Snapshot {
        let beneficiaryDisplayName: String
        let generatedAt: Date

        let setCount: Int
        let looseItemCount: Int

        let estimatedTotalValue: Double

        let sets: [SetSnapshot]
        let looseItems: [ItemSnapshot]

        let audioIndex: [AudioRef]
        let documentIndex: [DocumentRef]
        let imageIndex: [ImageRef]
    }

    struct SetSnapshot {
        let id: PersistentIdentifier
        let name: String
        let description: String
        let itemCount: Int
        let estimatedTotalValue: Double
        let items: [ItemSnapshot]
    }

    struct ItemSnapshot {
        let id: PersistentIdentifier
        let name: String
        let category: String
        let description: String
        let quantity: Int
        let estimatedTotalValue: Double

        let primaryImageRelativePath: String?
        let ownerNoteSummary: String?

        let hasAudio: Bool
        let hasDocuments: Bool
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
        // Keep String to avoid UUID/String mismatches across the app.
        let id: String
        let itemName: String
        let relativePath: String
        let bundleFilename: String
        let isPrimary: Bool
    }

    // MARK: - Public compose

    static func compose(target: Target, beneficiaryDisplayName: String) -> Snapshot {
        let generatedAt = Date()

        switch target {
        case .set(let set):
            let setSnapshot = composeSet(set)
            let total = setSnapshot.estimatedTotalValue

            return Snapshot(
                beneficiaryDisplayName: beneficiaryDisplayName,
                generatedAt: generatedAt,
                setCount: 1,
                looseItemCount: 0,
                estimatedTotalValue: total,
                sets: [setSnapshot],
                looseItems: [],
                audioIndex: [],
                documentIndex: [],
                imageIndex: []
            )

        case .batch(let batch):
            let setSnapshots: [SetSnapshot] = batch.sets.compactMap { bs in
                guard let s = bs.itemSet else { return nil }
                return composeSet(s)
            }

            let looseItemSnapshots: [ItemSnapshot] = batch.items.compactMap { bi in
                guard let item = bi.item else { return nil }
                return composeItem(item)
            }

            var total: Double = 0
            for s in setSnapshots { total += s.estimatedTotalValue }
            for it in looseItemSnapshots { total += it.estimatedTotalValue }

            return Snapshot(
                beneficiaryDisplayName: beneficiaryDisplayName,
                generatedAt: generatedAt,
                setCount: setSnapshots.count,
                looseItemCount: looseItemSnapshots.count,
                estimatedTotalValue: total,
                sets: setSnapshots,
                looseItems: looseItemSnapshots,
                audioIndex: [],
                documentIndex: [],
                imageIndex: []
            )

        case .items(let items):
            let itemSnapshots: [ItemSnapshot] = items.map { composeItem($0) }
            let total = itemSnapshots.reduce(0) { $0 + $1.estimatedTotalValue }

            return Snapshot(
                beneficiaryDisplayName: beneficiaryDisplayName,
                generatedAt: generatedAt,
                setCount: 0,
                looseItemCount: itemSnapshots.count,
                estimatedTotalValue: total,
                sets: [],
                looseItems: itemSnapshots,
                audioIndex: [],
                documentIndex: [],
                imageIndex: []
            )
        }
    }

    static func composeWithAssetIndexes(
        target: Target,
        beneficiaryDisplayName: String,
        options: InclusionOptions
    ) -> Snapshot {
        let base = compose(target: target, beneficiaryDisplayName: beneficiaryDisplayName)

        let orderedItems: [LTCItem] = {
            switch target {
            case .set(let set):
                return set.memberships.compactMap { $0.item }

            case .batch(let batch):
                var items: [LTCItem] = []
                for bs in batch.sets {
                    if let s = bs.itemSet {
                        items.append(contentsOf: s.memberships.compactMap { $0.item })
                    }
                }
                items.append(contentsOf: batch.items.compactMap { $0.item })
                return items

            case .items(let items):
                return items
            }
        }()

        let audioIndex = options.includeAudio ? buildAudioIndexFromModels(itemsInOrder: orderedItems) : []
        let documentIndex = options.includeDocuments ? buildDocumentIndexFromModels(itemsInOrder: orderedItems) : []
        let imageIndex = buildImageIndexFromModels(itemsInOrder: orderedItems, includeAllImages: options.includeFullResolutionImages)

        return Snapshot(
            beneficiaryDisplayName: base.beneficiaryDisplayName,
            generatedAt: base.generatedAt,
            setCount: base.setCount,
            looseItemCount: base.looseItemCount,
            estimatedTotalValue: base.estimatedTotalValue,
            sets: base.sets,
            looseItems: base.looseItems,
            audioIndex: audioIndex,
            documentIndex: documentIndex,
            imageIndex: imageIndex
        )
    }

    // MARK: - Compose helpers

    private static func composeSet(_ set: LTCItemSet) -> SetSnapshot {
        let name = set.name.isEmpty ? "Unnamed Set" : set.name
        let description = set.notes ?? ""

        let items: [ItemSnapshot] = set.memberships.compactMap { m in
            guard let item = m.item else { return nil }
            let qty = max(m.quantityInSet ?? item.quantity, 1)
            return composeItem(item, overrideQuantity: qty)
        }

        let total = items.reduce(0) { $0 + $1.estimatedTotalValue }

        return SetSnapshot(
            id: set.persistentModelID,
            name: name,
            description: description,
            itemCount: items.count,
            estimatedTotalValue: total,
            items: items
        )
    }

    private static func composeItem(_ item: LTCItem, overrideQuantity: Int? = nil) -> ItemSnapshot {
        let name = item.name.isEmpty ? "Unnamed Item" : item.name
        let category = item.category
        let description = item.itemDescription ?? ""
        let qty = max(overrideQuantity ?? item.quantity, 1)

        let unitEstimated = effectiveUnitValue(for: item)
        let totalEstimated = unitEstimated * Double(qty)

        let primaryImagePath = selectPrimaryImageRelativePath(for: item)

        let recordings = item.audioRecordings
        let hasAudio = !recordings.isEmpty
        let summary = bestAvailableAudioSummary(from: recordings)

        let hasDocuments = !item.documents.isEmpty

        return ItemSnapshot(
            id: item.persistentModelID,
            name: name,
            category: category,
            description: description,
            quantity: qty,
            estimatedTotalValue: totalEstimated,
            primaryImageRelativePath: primaryImagePath,
            ownerNoteSummary: summary,
            hasAudio: hasAudio,
            hasDocuments: hasDocuments
        )
    }

    private static func selectPrimaryImageRelativePath(for item: LTCItem) -> String? {
        let sorted = item.images.sorted { $0.createdAt < $1.createdAt }
        guard let first = sorted.first else { return nil }
        let rel = first.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return rel.isEmpty ? nil : rel
    }

    private static func bestAvailableAudioSummary(from recordings: [AudioRecording]) -> String? {
        let ready = recordings.first(where: {
            ($0.summaryStatusRaw ?? "missing") == "ready"
            && !($0.summaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        if let ready, let text = ready.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        let any = recordings.first(where: {
            !($0.summaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        if let any, let text = any.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        return nil
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

                let prefix = String(format: "%02d", counter)
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

                let prefix = String(format: "%02d", counter)
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

                let prefix = String(format: "%02d", counter)
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

    private static func effectiveUnitValue(for item: LTCItem) -> Double {
        if let estimated = item.valuation?.estimatedValue, estimated > 0 {
            return estimated
        }
        return max(item.value, 0)
    }

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
        return String(collapsed.prefix(40))
    }
}
