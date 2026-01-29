//
//  ReadinessChecklistLibrary.swift
//  LegacyTreasureChest
//
//  v1: Bundle-backed, key-addressable readiness checklist loader.
//  - Loads Luxury_Readiness_Checklists_v1.md from Bundle.main
//  - Extracts a checklist block by <!-- checklist_key: ... -->
//  - Returns raw markdown for rendering (parsing into checkbox UI comes later)
//

import Foundation

enum ReadinessChecklistError: LocalizedError {
    case resourceNotFound(name: String, ext: String)
    case unreadableResource(url: URL)
    case checklistKeyNotFound(key: String)
    case malformedChecklistBlock(key: String)

    var errorDescription: String? {
        switch self {
        case let .resourceNotFound(name, ext):
            return "Readiness checklist resource not found: \(name).\(ext)"
        case let .unreadableResource(url):
            return "Readiness checklist resource could not be read: \(url.lastPathComponent)"
        case let .checklistKeyNotFound(key):
            return "Readiness checklist key not found in markdown: \(key)"
        case let .malformedChecklistBlock(key):
            return "Readiness checklist block is malformed for key: \(key)"
        }
    }
}

/// Minimal model for v1. We return raw markdown.
/// Later we can extend this with parsed sections/items and per-item completion state.
struct ReadinessChecklist {
    let key: String
    let title: String?
    let markdown: String
}

final class ReadinessChecklistLibrary {

    static let shared = ReadinessChecklistLibrary()

    // MARK: - Resource

    private let resourceName = "Luxury_Readiness_Checklists_v1"
    private let resourceExtension = "md"

    private var cachedMarkdown: String?

    private init() {}

    // MARK: - Public API

    /// Load a checklist by machine key, e.g. "luxury_clothing_shoes_boots"
    func checklist(forKey key: String) throws -> ReadinessChecklist {
        let full = try loadMarkdown()

        guard let range = findChecklistBlockRange(in: full, key: key) else {
            throw ReadinessChecklistError.checklistKeyNotFound(key: key)
        }

        let rawBlock = String(full[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawBlock.isEmpty else {
            throw ReadinessChecklistError.malformedChecklistBlock(key: key)
        }

        let title = inferTitle(in: full, blockStartIndex: range.lowerBound)

        // Clean the markdown for UI rendering:
        // - Remove <!-- checklist_key: ... --> markers
        // - Remove the top "# Title" line (UI already provides the header)
        let cleaned = cleanChecklistMarkdown(rawBlock)

        return ReadinessChecklist(key: key, title: title, markdown: cleaned)
    }

    // MARK: - Convenience accessors (v1)

    /// Luxury Clothing → Shoes / Boots
    func luxuryClothingShoesBoots() throws -> ReadinessChecklist {
        try checklist(forKey: "luxury_clothing_shoes_boots")
    }

    /// Luxury Clothing → Designer Apparel
    func luxuryClothingDesignerApparel() throws -> ReadinessChecklist {
        try checklist(forKey: "luxury_clothing_designer_apparel")
    }

    /// Luxury Personal Items → Watches
    func luxuryPersonalItemsWatches() throws -> ReadinessChecklist {
        try checklist(forKey: "luxury_personal_items_watches")
    }

    /// Luxury Personal Items → Handbags
    func luxuryPersonalItemsHandbags() throws -> ReadinessChecklist {
        try checklist(forKey: "luxury_personal_items_handbags")
    }

    /// Luxury Personal Items → Jewelry
    func luxuryPersonalItemsJewelry() throws -> ReadinessChecklist {
        try checklist(forKey: "luxury_personal_items_jewelry")
    }

    // MARK: - Load / Cache

    private func loadMarkdown() throws -> String {
        if let cachedMarkdown { return cachedMarkdown }

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw ReadinessChecklistError.resourceNotFound(name: resourceName, ext: resourceExtension)
        }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            self.cachedMarkdown = text
            return text
        } catch {
            throw ReadinessChecklistError.unreadableResource(url: url)
        }
    }

    // MARK: - Extraction logic

    /// Finds the range of markdown belonging to the checklist identified by key.
    ///
    /// We use the marker:
    /// <!-- checklist_key: SOME_KEY -->
    ///
    /// Block starts at the *heading line* immediately preceding the marker if present,
    /// otherwise starts at the marker itself.
    ///
    /// Block ends at the next checklist_key marker, or end-of-file.
    private func findChecklistBlockRange(in full: String, key: String) -> Range<String.Index>? {
        let marker = "<!-- checklist_key: \(key) -->"

        guard let markerRange = full.range(of: marker) else {
            return nil
        }

        // Prefer start at the nearest preceding "# " heading (the checklist title line)
        let startIndex = findNearestHeadingStart(in: full, before: markerRange.lowerBound) ?? markerRange.lowerBound

        // End at the next checklist_key marker after this marker
        let searchStart = markerRange.upperBound
        let remainder = full[searchStart...]
        if let nextMarkerRange = remainder.range(of: "<!-- checklist_key:") {
            return startIndex..<nextMarkerRange.lowerBound
        } else {
            return startIndex..<full.endIndex
        }
    }

    /// Find the start index of the nearest markdown H1 heading ("# ") before a given index.
    /// Returns nil if not found.
    private func findNearestHeadingStart(in full: String, before index: String.Index) -> String.Index? {
        // Search backward line-by-line
        var i = index
        while i > full.startIndex {
            // Move to the start of the current line
            let lineStart = full[..<i].lastIndex(of: "\n").map { full.index(after: $0) } ?? full.startIndex
            let lineEnd = full[lineStart...].firstIndex(of: "\n") ?? full.endIndex
            let line = full[lineStart..<lineEnd]

            if line.hasPrefix("# ") {
                return lineStart
            }

            // Move i to just before this lineStart (previous line)
            if lineStart == full.startIndex { break }
            i = full.index(before: lineStart)
        }
        return nil
    }

    /// Infers the checklist title by looking at the first line of the block if it is "# ...".
    private func inferTitle(in full: String, blockStartIndex: String.Index) -> String? {
        let lineEnd = full[blockStartIndex...].firstIndex(of: "\n") ?? full.endIndex
        let firstLine = String(full[blockStartIndex..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard firstLine.hasPrefix("# ") else { return nil }
        return String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Markdown cleanup (v1)

    private func cleanChecklistMarkdown(_ rawBlock: String) -> String {
        // 1) Remove checklist_key marker lines entirely
        var lines = rawBlock.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("<!-- checklist_key:")
        }

        // 2) Remove the top H1 title line ("# ...") if present (UI header already shows)
        if let firstNonEmptyIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let first = lines[firstNonEmptyIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if first.hasPrefix("# ") {
                lines.remove(at: firstNonEmptyIndex)

                // Also remove a single blank line immediately following the title, if present
                if firstNonEmptyIndex < lines.count {
                    let next = lines[firstNonEmptyIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    if next.isEmpty {
                        lines.remove(at: firstNonEmptyIndex)
                    }
                }
            }
        }

        // 3) Trim extra whitespace at ends
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

