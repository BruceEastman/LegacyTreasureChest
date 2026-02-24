//
//  ExportSizeEstimator.swift
//  LegacyTreasureChest
//
//  Estimates export bundle size (bytes) before generation.
//

import Foundation

enum ExportSizeEstimator {

    struct Estimate: Equatable {
        let totalBytes: Int64
        let pdfBytes: Int64
        let audioBytes: Int64
        let documentBytes: Int64
        let imageBytes: Int64
    }

    enum Guardrail: Equatable {
        case ok
        case softWarning   // >= 50MB
        case strongWarning // >= 100MB
        case hardBlock     // >= 250MB
    }

    static func guardrail(forTotalBytes bytes: Int64) -> Guardrail {
        let mb50: Int64 = 50 * 1024 * 1024
        let mb100: Int64 = 100 * 1024 * 1024
        let mb250: Int64 = 250 * 1024 * 1024

        if bytes >= mb250 { return .hardBlock }
        if bytes >= mb100 { return .strongWarning }
        if bytes >= mb50 { return .softWarning }
        return .ok
    }

    enum ShareRecommendation: Equatable {
        case mailOkay
        case preferFilesOrAirDrop
        case requireFilesOrAirDrop
    }

    static func recommendShareTarget(forTotalBytes bytes: Int64) -> ShareRecommendation {
        // Practical cutoffs. Mail often struggles with big attachments; many servers cap at ~25MB.
        let mb25: Int64 = 25 * 1024 * 1024
        let mb50: Int64 = 50 * 1024 * 1024

        if bytes <= mb25 { return .mailOkay }
        if bytes <= mb50 { return .preferFilesOrAirDrop }
        return .requireFilesOrAirDrop
    }

    static func estimateBeneficiaryPacket(
        snapshot: BeneficiaryPacketComposer.Snapshot,
        pdfBytes: Int64,
        options: BeneficiaryPacketComposer.InclusionOptions
    ) -> Estimate {
        let audio = options.includeAudio ? sumFileSizes(relativePaths: snapshot.audioIndex.map { $0.relativePath },
                                                        resolver: { MediaStorage.audioURL(from: $0) }) : 0

        let docs = options.includeDocuments ? sumFileSizes(relativePaths: snapshot.documentIndex.map { $0.relativePath },
                                                          resolver: { MediaStorage.absoluteURL(from: $0) }) : 0

        // Images: snapshot.imageIndex already reflects “selected vs full-res” choice in the composer
        let images = sumFileSizes(relativePaths: snapshot.imageIndex.map { $0.relativePath },
                                  resolver: { MediaStorage.absoluteURL(from: $0) })

        let total = pdfBytes + audio + docs + images

        return Estimate(
            totalBytes: total,
            pdfBytes: pdfBytes,
            audioBytes: audio,
            documentBytes: docs,
            imageBytes: images
        )
    }

    // MARK: - Helpers

    private static func sumFileSizes(relativePaths: [String], resolver: (String) -> URL) -> Int64 {
        var total: Int64 = 0
        for rel in relativePaths {
            let trimmed = rel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let url = resolver(trimmed)
            if let size = fileSize(url: url) {
                total += size
            }
        }
        return total
    }

    private static func fileSize(url: URL) -> Int64? {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize {
                return Int64(size)
            }
            return nil
        } catch {
            return nil
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
