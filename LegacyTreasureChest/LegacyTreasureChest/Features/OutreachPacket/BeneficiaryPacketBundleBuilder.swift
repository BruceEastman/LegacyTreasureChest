//
//  BeneficiaryPacketBundleBuilder.swift
//  LegacyTreasureChest
//
//  Builds the Beneficiary Packet bundle folder and produces a ZIP (bundle-first).
//  v1: ZIP is intentional for family/heirs.
//

import Foundation

enum BeneficiaryPacketBundleBuilder {

    enum BuildError: Error, LocalizedError {
        case hardBlockExceeded(totalBytes: Int64)

        var errorDescription: String? {
            switch self {
            case .hardBlockExceeded(let totalBytes):
                return "Beneficiary Packet is too large to generate (\(ExportSizeEstimator.formatBytes(totalBytes))). Reduce included assets or use an explicit override for Files/AirDrop."
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
        let pdfURL: URL
        let zipURL: URL

        /// Returned so UI can display exactly what was generated.
        let preflight: Preflight
    }

    /// Preflight only (no files written). Useful for UI “Estimate bundle size” before generation.
    static func preflight(
        snapshot: BeneficiaryPacketComposer.Snapshot,
        pdfBytes: Int64,
        options: BeneficiaryPacketComposer.InclusionOptions
    ) -> Preflight {
        let estimate = ExportSizeEstimator.estimateBeneficiaryPacket(
            snapshot: snapshot,
            pdfBytes: pdfBytes,
            options: options
        )

        let guardrail = ExportSizeEstimator.guardrail(forTotalBytes: estimate.totalBytes)
        let shareRec = ExportSizeEstimator.recommendShareTarget(forTotalBytes: estimate.totalBytes)

        return Preflight(estimate: estimate, guardrail: guardrail, shareRecommendation: shareRec)
    }

    /// Builds:
    /// - folder: BeneficiaryPacket_<Name>_<YYYY-MM-DD>/
    /// - Packet.pdf
    /// - optional Audio/, Documents/, Images/
    /// Then produces:
    /// - BeneficiaryPacket_<Name>_<YYYY-MM-DD>.zip
    ///
    /// - Parameters:
    ///   - allowHardBlockOverride: set true only when the user explicitly chooses a safe local share path (e.g., Files/AirDrop).
    static func buildBundle(
        snapshot: BeneficiaryPacketComposer.Snapshot,
        pdfData: Data,
        options: BeneficiaryPacketComposer.InclusionOptions,
        allowHardBlockOverride: Bool = false
    ) throws -> Result {

        // --- Preflight / guardrails ---
        let pf = preflight(
            snapshot: snapshot,
            pdfBytes: Int64(pdfData.count),
            options: options
        )

        if pf.guardrail == .hardBlock, !allowHardBlockOverride {
            throw BuildError.hardBlockExceeded(totalBytes: pf.estimate.totalBytes)
        }

        // --- Build folder ---
        let baseDir = FileManager.default.temporaryDirectory

        let date = bundleDateString(snapshot.generatedAt)
        let safeName = sanitizeFilename(snapshot.beneficiaryDisplayName)

        let folderName = "BeneficiaryPacket_\(safeName)_\(date)"
        let folderURL = baseDir.appendingPathComponent(folderName, isDirectory: true)

        // Overwrite existing folder if present
        if FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.removeItem(at: folderURL)
        }

        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Write PDF (always)
        let pdfURL = folderURL.appendingPathComponent("Packet.pdf")
        try pdfData.write(to: pdfURL, options: [.atomic])

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

        // Documents
        if options.includeDocuments, !snapshot.documentIndex.isEmpty {
            let docsFolder = folderURL.appendingPathComponent("Documents", isDirectory: true)
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

        // Images (selected vs full-res handled upstream by composer index)
        if !snapshot.imageIndex.isEmpty {
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

        // --- Produce ZIP (Foundation-only) ---
        let zipFilename = "BeneficiaryPacket_\(safeName)_\(date).zip"
        let zipURL = baseDir.appendingPathComponent(zipFilename)

        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }

        try createZip(fromDirectory: folderURL, finalZipURL: zipURL)

        return Result(folderURL: folderURL, pdfURL: pdfURL, zipURL: zipURL, preflight: pf)
    }

    // MARK: - ZIP (Foundation-only)

    /// Creates a ZIP archive of a directory using NSFileCoordinator reading option `.forUploading`.
    private static func createZip(fromDirectory directoryURL: URL, finalZipURL: URL) throws {
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw NSError(domain: "BeneficiaryPacketBundleBuilder", code: 1, userInfo: [
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
        if trimmed.isEmpty { return "Beneficiary" }

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
