//
//  ExecutorMasterPacketBundleBuilder.swift
//  LegacyTreasureChest
//
//  Builds the Executor Master Packet bundle folder and produces a ZIP (bundle-first).
//  v1: ZIP is intentional for executor/attorney/CPA forwarding.
//

import Foundation

enum ExecutorMasterPacketBundleBuilder {

    enum BuildError: Error, LocalizedError {
        case hardBlockExceeded(totalBytes: Int64)

        var errorDescription: String? {
            switch self {
            case .hardBlockExceeded(let totalBytes):
                return "Executor Master Packet is too large to generate (\(ExportSizeEstimator.formatBytes(totalBytes))). Reduce included assets or use an explicit override for Files/AirDrop."
            }
        }
    }

    struct Preflight {
        let estimate: ExportSizeEstimator.Estimate
        let guardrail: ExportSizeEstimator.Guardrail
        let shareRecommendation: ExportSizeEstimator.ShareRecommendation
    }

    struct Result {
        let folderURL: URL
        let snapshotPDFURL: URL
        let inventoryPDFURL: URL
        let zipURL: URL
        let preflight: Preflight
    }

    static func preflight(
        snapshot: ExecutorMasterPacketComposer.Snapshot,
        pdfBytes: Int64,
        options: ExecutorMasterPacketComposer.InclusionOptions
    ) -> Preflight {
        let estimate = ExportSizeEstimator.estimateExecutorMasterPacket(
            snapshot: snapshot,
            pdfBytes: pdfBytes,
            options: options
        )

        let guardrail = ExportSizeEstimator.guardrail(forTotalBytes: estimate.totalBytes)
        let shareRec = ExportSizeEstimator.recommendShareTarget(forTotalBytes: estimate.totalBytes)

        return Preflight(estimate: estimate, guardrail: guardrail, shareRecommendation: shareRec)
    }

    /// Builds:
    /// - folder: ExecutorMasterPacket_<Estate>_<YYYY-MM-DD>/
    /// - ExecutorSnapshot.pdf
    /// - DetailedInventory.pdf
    /// - optional Audio/, SupportingDocs/, Images/
    /// Then produces:
    /// - ExecutorMasterPacket_<Estate>_<YYYY-MM-DD>.zip
    ///
    /// - Parameters:
    ///   - allowHardBlockOverride: set true only when the user explicitly chooses a safe local share path (e.g., Files/AirDrop).
    static func buildBundle(
        snapshot: ExecutorMasterPacketComposer.Snapshot,
        snapshotPDFData: Data,
        inventoryPDFData: Data,
        options: ExecutorMasterPacketComposer.InclusionOptions,
        allowHardBlockOverride: Bool = false
    ) throws -> Result {

        // --- Preflight / guardrails ---
        let pdfBytes = Int64(snapshotPDFData.count + inventoryPDFData.count)
        let pf = preflight(snapshot: snapshot, pdfBytes: pdfBytes, options: options)

        if pf.guardrail == .hardBlock, !allowHardBlockOverride {
            throw BuildError.hardBlockExceeded(totalBytes: pf.estimate.totalBytes)
        }

        // --- Build folder ---
        let baseDir = FileManager.default.temporaryDirectory

        let date = bundleDateString(snapshot.generatedAt)
        let safeName = sanitizeFilename(snapshot.estateDisplayName)

        let folderName = "ExecutorMasterPacket_\(safeName)_\(date)"
        let folderURL = baseDir.appendingPathComponent(folderName, isDirectory: true)

        if FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.removeItem(at: folderURL)
        }

        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Write PDFs (always)
        let snapshotPDFURL = folderURL.appendingPathComponent("ExecutorSnapshot.pdf")
        try snapshotPDFData.write(to: snapshotPDFURL, options: [.atomic])

        let inventoryPDFURL = folderURL.appendingPathComponent("DetailedInventory.pdf")
        try inventoryPDFData.write(to: inventoryPDFURL, options: [.atomic])

        // Supporting Docs
        if options.includeSupportingDocs, !snapshot.documentIndex.isEmpty {
            let docsFolder = folderURL.appendingPathComponent("SupportingDocs", isDirectory: true)
            try FileManager.default.createDirectory(at: docsFolder, withIntermediateDirectories: true, attributes: nil)

            for ref in snapshot.documentIndex {
                let sourceURL = MediaStorage.absoluteURL(from: ref.relativePath)
                let destURL = docsFolder.appendingPathComponent(ref.bundleFilename)

                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }

                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
            }
        }

        // Audio
        if options.includeAudio, !snapshot.audioIndex.isEmpty {
            let audioFolder = folderURL.appendingPathComponent("Audio", isDirectory: true)
            try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true, attributes: nil)

            for ref in snapshot.audioIndex {
                let sourceURL = MediaStorage.audioURL(from: ref.relativePath)
                let destURL = audioFolder.appendingPathComponent(ref.bundleFilename)

                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }

                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
            }
        }

        // Images
        if options.includeImages, !snapshot.imageIndex.isEmpty {
            let imagesFolder = folderURL.appendingPathComponent("Images", isDirectory: true)
            try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true, attributes: nil)

            for ref in snapshot.imageIndex {
                let sourceURL = MediaStorage.absoluteURL(from: ref.relativePath)
                let destURL = imagesFolder.appendingPathComponent(ref.bundleFilename)

                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }

                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
            }
        }

        // --- Produce ZIP ---
        let zipFilename = "ExecutorMasterPacket_\(safeName)_\(date).zip"
        let zipURL = baseDir.appendingPathComponent(zipFilename)

        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }

        try createZip(fromDirectory: folderURL, finalZipURL: zipURL)

        return Result(
            folderURL: folderURL,
            snapshotPDFURL: snapshotPDFURL,
            inventoryPDFURL: inventoryPDFURL,
            zipURL: zipURL,
            preflight: pf
        )
    }

    // MARK: - ZIP (Foundation-only)

    private static func createZip(fromDirectory directoryURL: URL, finalZipURL: URL) throws {
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw NSError(domain: "ExecutorMasterPacketBundleBuilder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Expected a directory URL for ZIP creation."
            ])
        }

        let coordinator = NSFileCoordinator()

        var coordinationError: NSError?
        var copyError: Error?

        coordinator.coordinate(readingItemAt: directoryURL, options: .forUploading, error: &coordinationError) { zippedSnapshotURL in
            do {
                if FileManager.default.fileExists(atPath: finalZipURL.path) {
                    try FileManager.default.removeItem(at: finalZipURL)
                }
                try FileManager.default.copyItem(at: zippedSnapshotURL, to: finalZipURL)
            } catch {
                copyError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    // MARK: - Helpers

    private static func bundleDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func sanitizeFilename(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Estate" }

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
