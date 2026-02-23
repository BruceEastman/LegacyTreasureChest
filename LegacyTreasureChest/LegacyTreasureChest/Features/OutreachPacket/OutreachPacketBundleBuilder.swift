//
//  OutreachPacketBundleBuilder.swift
//  LegacyTreasureChest
//
//  Builds the Outreach Packet bundle folder (PDF + optional assets).
//  v1: folder-first. Zip can be added later if needed.
//

import Foundation

enum OutreachPacketBundleBuilder {

    struct Result {
        let folderURL: URL
        let pdfURL: URL
    }

    static func buildBundle(snapshot: OutreachPacketSnapshot, pdfData: Data) throws -> Result {
        let baseDir = FileManager.default.temporaryDirectory

        let date = bundleDateString(snapshot.generatedAt)
        let safeName = sanitizeFilename(snapshot.targetDisplayName)
        let folderName = "OutreachPacket_\(safeName)_\(date)"
        let folderURL = baseDir.appendingPathComponent(folderName, isDirectory: true)

        // Overwrite existing
        if FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.removeItem(at: folderURL)
        }

        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Write PDF
        let pdfURL = folderURL.appendingPathComponent("Packet.pdf")
        try pdfData.write(to: pdfURL, options: [.atomic])

        // Copy audio files if present
        if !snapshot.audioIndex.isEmpty {
            let audioFolder = folderURL.appendingPathComponent("Audio", isDirectory: true)
            try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true, attributes: nil)

            for ref in snapshot.audioIndex {
                let sourceURL = MediaStorage.audioURL(from: ref.relativePath)
                let destURL = audioFolder.appendingPathComponent(ref.bundleFilename)

                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }

                // Only copy if source exists (avoid hard fail if a file was deleted externally)
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
            }
        }

        // Copy documents if present
        if !snapshot.documentIndex.isEmpty {
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

        return Result(folderURL: folderURL, pdfURL: pdfURL)
    }

    private static func bundleDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func sanitizeFilename(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Target" }

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
