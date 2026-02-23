//
//  OutreachPacketModels.swift
//  LegacyTreasureChest
//
//  Outreach Packet v1 models (snapshot + value policy).
//  Pure data structures used by composer + PDF renderer + bundle builder.
//

import Foundation
import SwiftData

// MARK: - Value Range

struct OutreachValueRange: Equatable {
    let low: Double
    let high: Double

    var isEmpty: Bool { low <= 0 && high <= 0 }
}

enum OutreachValuePolicy {
    /// Range-only valuation policy for external packets.
    /// v1 uses a conservative spread around a best-effort estimate.
    static func range(forEstimatedValue value: Double) -> OutreachValueRange {
        let v = max(value, 0)
        if v <= 0 { return OutreachValueRange(low: 0, high: 0) }

        // Conservative spread (tunable later).
        let low = v * 0.80
        let high = v * 1.20
        return OutreachValueRange(low: low, high: high)
    }
}

// MARK: - Snapshot

struct OutreachPacketSnapshot {
    let targetDisplayName: String
    let generatedAt: Date

    let setCount: Int
    let looseItemCount: Int

    let packetValueRange: OutreachValueRange

    let sets: [OutreachSetSnapshot]
    let looseItems: [OutreachItemSnapshot]

    // Asset indexes (used for appendices + bundle copy)
    let audioIndex: [OutreachAudioRef]
    let documentIndex: [OutreachDocumentRef]
}

struct OutreachSetSnapshot: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let description: String
    let itemCount: Int
    let valueRange: OutreachValueRange
    let items: [OutreachItemSnapshot]
}

struct OutreachItemSnapshot: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let category: String
    let description: String
    let quantity: Int
    let valueRange: OutreachValueRange

    /// Best available export-safe summary (1–2 sentences), if present.
    let ownerNoteSummary: String?

    let hasAudio: Bool
    let hasDocuments: Bool
}

// MARK: - Asset Refs (bundle builder + appendices)

struct OutreachAudioRef: Identifiable {
    let id: UUID

    let itemName: String
    let duration: Double

    /// Relative path stored in SwiftData: e.g. "Media/Audio/<uuid>.m4a"
    let relativePath: String

    /// Filename we will use inside the bundle's /Audio folder.
    let bundleFilename: String

    /// Optional export-safe summary (1–2 sentences).
    let summaryText: String?
}

struct OutreachDocumentRef: Identifiable {
    let id: UUID

    let itemName: String
    let documentType: String

    /// Original filename when imported (if known).
    let originalFilename: String?

    /// Relative path stored in SwiftData: e.g. "Media/Documents/<uuid>_receipt.pdf"
    let relativePath: String

    /// Filename we will use inside the bundle's /Documents folder.
    let bundleFilename: String
}
