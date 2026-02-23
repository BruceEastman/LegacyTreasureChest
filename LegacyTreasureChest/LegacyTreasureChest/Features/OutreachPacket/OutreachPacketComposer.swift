//
//  OutreachPacketComposer.swift
//  LegacyTreasureChest
//
//  Composes an OutreachPacketSnapshot from a Set or Batch.
//  No network calls. Uses persisted data only.
//

import Foundation
import SwiftData

enum OutreachPacketComposer {

    enum Target {
        case set(LTCItemSet)
        case batch(LiquidationBatch)

        var displayName: String {
            switch self {
            case .set(let s):
                return s.name.isEmpty ? "Set" : s.name
            case .batch(let b):
                return b.name.isEmpty ? "Batch" : b.name
            }
        }
    }

    /// Base snapshot (structure + values + flags + per-item summary text).
    /// Asset indexes (audio/doc appendices + bundle copying) are added by `composeWithAudioIndex(...)` (kept name for compatibility).
    static func compose(target: Target) -> OutreachPacketSnapshot {
        let generatedAt = Date()

        switch target {
        case .set(let set):
            let setSnapshot = composeSet(set)
            return OutreachPacketSnapshot(
                targetDisplayName: setSnapshot.name,
                generatedAt: generatedAt,
                setCount: 1,
                looseItemCount: 0,
                packetValueRange: setSnapshot.valueRange,
                sets: [setSnapshot],
                looseItems: [],
                audioIndex: [],
                documentIndex: []
            )

        case .batch(let batch):
            let setSnapshots: [OutreachSetSnapshot] = batch.sets.compactMap { bs in
                guard let s = bs.itemSet else { return nil }
                return composeSet(s)
            }

            let looseItemSnapshots: [OutreachItemSnapshot] = batch.items.compactMap { bi in
                guard let item = bi.item else { return nil }
                return composeItem(item)
            }

            var totalEstimatedMidpoint: Double = 0
            for s in setSnapshots { totalEstimatedMidpoint += midpoint(of: s.valueRange) }
            for it in looseItemSnapshots { totalEstimatedMidpoint += midpoint(of: it.valueRange) }

            let packetRange = OutreachValuePolicy.range(forEstimatedValue: totalEstimatedMidpoint)

            return OutreachPacketSnapshot(
                targetDisplayName: target.displayName,
                generatedAt: generatedAt,
                setCount: setSnapshots.count,
                looseItemCount: looseItemSnapshots.count,
                packetValueRange: packetRange,
                sets: setSnapshots,
                looseItems: looseItemSnapshots,
                audioIndex: [],
                documentIndex: []
            )
        }
    }

    // MARK: - Compose helpers

    private static func composeSet(_ set: LTCItemSet) -> OutreachSetSnapshot {
        let name = set.name.isEmpty ? "Unnamed Set" : set.name
        let description = set.notes ?? ""

        let items: [OutreachItemSnapshot] = set.memberships.compactMap { m in
            guard let item = m.item else { return nil }
            let qty = max(m.quantityInSet ?? item.quantity, 1)
            return composeItem(item, overrideQuantity: qty)
        }

        var estimatedTotalMidpoint: Double = 0
        for it in items { estimatedTotalMidpoint += midpoint(of: it.valueRange) }
        let range = OutreachValuePolicy.range(forEstimatedValue: estimatedTotalMidpoint)

        return OutreachSetSnapshot(
            id: set.persistentModelID,
            name: name,
            description: description,
            itemCount: items.count,
            valueRange: range,
            items: items
        )
    }

    private static func composeItem(_ item: LTCItem, overrideQuantity: Int? = nil) -> OutreachItemSnapshot {
        let name = item.name.isEmpty ? "Unnamed Item" : item.name
        let category = item.category
        let description = item.itemDescription ?? ""
        let qty = max(overrideQuantity ?? item.quantity, 1)

        let unitEstimated = effectiveUnitValue(for: item)
        let totalEstimated = unitEstimated * Double(qty)
        let range = OutreachValuePolicy.range(forEstimatedValue: totalEstimated)

        // Primary image (embed in PDF)
        let primaryImagePath = selectPrimaryImageRelativePath(for: item)

        // Audio flags + summary selection
        let recordings = item.audioRecordings
        let hasAudio = !recordings.isEmpty
        let summary = bestAvailableAudioSummary(from: recordings)

        // Documents
        let hasDocuments = !item.documents.isEmpty

        return OutreachItemSnapshot(
            id: item.persistentModelID,
            name: name,
            category: category,
            description: description,
            quantity: qty,
            valueRange: range,
            primaryImageRelativePath: primaryImagePath,
            ownerNoteSummary: summary,
            hasAudio: hasAudio,
            hasDocuments: hasDocuments
        )
    }

    private static func selectPrimaryImageRelativePath(for item: LTCItem) -> String? {
        // Stable choice: earliest created image (or nil if none)
        let sorted = item.images.sorted { $0.createdAt < $1.createdAt }
        guard let first = sorted.first else { return nil }
        let rel = first.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return rel.isEmpty ? nil : rel
    }

    private static func bestAvailableAudioSummary(from recordings: [AudioRecording]) -> String? {
        // Prefer summaryStatusRaw == "ready" with non-empty summaryText.
        // Fall back to any non-empty summaryText if status is nil/unknown.
        let ready = recordings.first(where: {
            ($0.summaryStatusRaw ?? "missing") == "ready"
            && !($0.summaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        if let ready, let text = ready.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        let any = recordings.first(where: { !($0.summaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        if let any, let text = any.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        return nil
    }

    // MARK: - Model-backed asset indexes

    private static func buildAudioIndexFromModels(itemsInOrder: [LTCItem]) -> [OutreachAudioRef] {
        var result: [OutreachAudioRef] = []
        var counter = 1

        for item in itemsInOrder {
            let itemName = item.name.isEmpty ? "Unnamed Item" : item.name

            for recording in item.audioRecordings {
                let rel = recording.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rel.isEmpty else { continue }

                let prefix = String(format: "%02d", counter)
                let sanitizedItem = sanitizeFilename(itemName)

                // Keep extension from stored path (usually .m4a)
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
                    OutreachAudioRef(
                        id: recording.audioRecordingId,
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

    private static func buildDocumentIndexFromModels(itemsInOrder: [LTCItem]) -> [OutreachDocumentRef] {
        var result: [OutreachDocumentRef] = []
        var counter = 1

        for item in itemsInOrder {
            let itemName = item.name.isEmpty ? "Unnamed Item" : item.name

            // Keep deterministic order for stability
            let docs = item.documents.sorted { $0.createdAt < $1.createdAt }

            for doc in docs {
                let rel = doc.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rel.isEmpty else { continue }

                let prefix = String(format: "%02d", counter)
                let sanitizedItem = sanitizeFilename(itemName)
                let sanitizedType = sanitizeFilename(doc.documentType.isEmpty ? "Document" : doc.documentType)

                // Prefer original filename extension, else stored path extension.
                let extFromOriginal = ((doc.originalFilename ?? "") as NSString).pathExtension
                let extFromPath = (rel as NSString).pathExtension
                let ext = !extFromOriginal.isEmpty ? extFromOriginal : extFromPath

                let finalExt = ext.isEmpty ? "dat" : ext
                let bundleFilename = "\(prefix)_\(sanitizedItem)_\(sanitizedType).\(finalExt)"

                result.append(
                    OutreachDocumentRef(
                        id: doc.documentId,
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

    /// NOTE: kept name for backward compatibility — includes *both* audio and documents indexes.
    static func composeWithAudioIndex(target: Target) -> OutreachPacketSnapshot {
        let base = compose(target: target)

        // Walk models in a deterministic order:
        // - Sets first (membership order), then loose items.
        let orderedItems: [LTCItem] = {
            switch target {
            case .set(let set):
                return set.memberships.compactMap { $0.item }
            case .batch(let batch):
                var items: [LTCItem] = []
                // sets first
                for bs in batch.sets {
                    if let s = bs.itemSet {
                        items.append(contentsOf: s.memberships.compactMap { $0.item })
                    }
                }
                // then loose
                items.append(contentsOf: batch.items.compactMap { $0.item })
                return items
            }
        }()

        let audioIndex = buildAudioIndexFromModels(itemsInOrder: orderedItems)
        let documentIndex = buildDocumentIndexFromModels(itemsInOrder: orderedItems)

        return OutreachPacketSnapshot(
            targetDisplayName: base.targetDisplayName,
            generatedAt: base.generatedAt,
            setCount: base.setCount,
            looseItemCount: base.looseItemCount,
            packetValueRange: base.packetValueRange,
            sets: base.sets,
            looseItems: base.looseItems,
            audioIndex: audioIndex,
            documentIndex: documentIndex
        )
    }

    // MARK: - Helpers

    private static func effectiveUnitValue(for item: LTCItem) -> Double {
        if let estimated = item.valuation?.estimatedValue, estimated > 0 {
            return estimated
        }
        return max(item.value, 0)
    }

    private static func midpoint(of range: OutreachValueRange) -> Double {
        (range.low + range.high) / 2.0
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
