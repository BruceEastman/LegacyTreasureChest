//
//  ItemAnalysisApplier.swift
//  LegacyTreasureChest
//
//  Applies an AI ItemAnalysis to an LTCItem (Improve with AI "Apply
//  Suggestions") and builds the description for items created by Batch Add.
//
//  Description rules (no schema change):
//
//  1. Generated details line. Identification attributes returned by the AI
//     (brand, model, maker, materials, style, origin, era, dimensions,
//     condition, features) are saved as ONE line in a fixed format and key
//     order, e.g. "Brand: Lexington • Materials: cherry • Condition: Good".
//     Apply removes any earlier generated line and writes one merged line, so
//     repeated analyses never stack lines. A value the new analysis returns
//     replaces the earlier value; an attribute it does not mention keeps its
//     earlier value. An earlier line is recognized only when an AI paragraph
//     has been recorded, every segment is a known key, and the line has two
//     or more segments. A single "Key: value" line (for example an owner's
//     "Dimensions: 36 inches") is always kept as text; it is dropped only if
//     it exactly repeats a value in the new generated line.
//
//  2. Where the description text came from. `llmGeneratedDescription` records
//     the AI paragraph that Apply (or Batch Add) last wrote. It is the only
//     provenance the existing data provides:
//     - empty:        no prose.
//     - ownerWritten: no AI paragraph has ever been applied, so the prose is the
//                     owner's.
//     - aiGenerated:  the prose starts with the recorded AI paragraph. Text after
//                     it (a new paragraph) was added later and is kept.
//     - mixed:        an AI paragraph was applied and the text was edited
//                     afterwards. Which sentences came from whom cannot be
//                     recovered, so the text is treated conservatively.
//
//  3. Preservation (until the Stage 4 review screen lets the owner choose):
//     - empty / aiGenerated: the new AI paragraph replaces the earlier AI
//       paragraph; later additions are kept below it.
//     - ownerWritten: the new AI paragraph is placed first and the owner's text
//       is kept, word for word, below it.
//     - mixed: the prose is left unchanged; only the details line is updated.
//     Owner notes (ItemValuation.userNotes) are never written here.
//

import Foundation

// MARK: - Generated details line

enum GeneratedDetailsLine {

    static let separator = " • "

    /// Canonical key order. Includes every key older app versions wrote
    /// (Maker, Materials, Style, Condition, Features) so their lines are
    /// recognized and replaced rather than duplicated.
    static let keys: [String] = [
        "Brand", "Model", "Maker", "Materials", "Style",
        "Origin", "Era", "Dimensions", "Condition", "Features"
    ]

    /// Parses a single line produced by `build`. Returns nil unless every
    /// segment is "Key: value" with a known key (each key at most once).
    static func parse(_ line: String) -> [String: String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var result: [String: String] = [:]
        for segment in trimmed.components(separatedBy: separator) {
            guard let colon = segment.range(of: ": ") else { return nil }
            let key = String(segment[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(segment[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard keys.contains(key), !value.isEmpty, result[key] == nil else { return nil }
            result[key] = value
        }
        return result.isEmpty ? nil : result
    }

    /// Builds the line in canonical key order. Nil when there is nothing to show.
    static func build(_ attributes: [String: String]) -> String? {
        let parts = keys.compactMap { key -> String? in
            guard let value = attributes[key].map({ sanitize($0) }), !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }

    /// Attributes an analysis returned, keyed by the canonical labels.
    static func attributes(from analysis: ItemAnalysis) -> [String: String] {
        var result: [String: String] = [:]

        func set(_ key: String, _ value: String?) {
            guard let value = value.map({ sanitize($0) }), !value.isEmpty else { return }
            result[key] = value
        }
        func set(_ key: String, _ values: [String]?) {
            let joined = (values ?? [])
                .map { sanitize($0) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            set(key, joined)
        }

        let brand = analysis.brand.map { sanitize($0) }.flatMap { $0.isEmpty ? nil : $0 }
        let maker = analysis.maker.map { sanitize($0) }.flatMap { $0.isEmpty ? nil : $0 }

        // The gateway returns `brand`; `maker` is kept for older responses.
        set("Brand", brand ?? maker)
        if let brand, let maker, brand.caseInsensitiveCompare(maker) != .orderedSame {
            set("Maker", maker)
        }
        set("Model", analysis.modelNumber)
        set("Materials", analysis.materials)
        set("Style", analysis.style)
        set("Origin", analysis.origin)
        set("Era", analysis.eraOrYear)
        set("Dimensions", analysis.dimensions)
        set("Condition", analysis.condition)
        set("Features", analysis.features)
        return result
    }

    /// Keeps a value on one line and free of the separator so the line stays
    /// parseable.
    static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "•", with: "·")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Saved description classification

struct SavedDescription: Equatable {

    enum Origin: Equatable {
        case empty
        case ownerWritten
        case aiGenerated
        case mixed
    }

    let origin: Origin

    /// The recorded AI paragraph (aiGenerated only).
    let aiParagraph: String?

    /// Prose that is not the recorded AI paragraph: the whole text for
    /// ownerWritten and mixed, later additions for aiGenerated.
    let otherText: String?

    /// The full prose without the generated details line.
    let prose: String

    /// Attributes parsed from generated details line(s), if any.
    let generatedAttributes: [String: String]

    static func classify(description: String, llmGeneratedDescription: String?) -> SavedDescription {
        let normalized = description
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let recorded = llmGeneratedDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let aiParagraph = (recorded?.isEmpty ?? true) ? nil : recorded

        // A generated details line exists only after an AI apply (Apply and
        // Batch Add record the AI paragraph). A line is treated as generated
        // only when an AI paragraph is recorded, it parses, and it has two or
        // more " • "-separated segments, a format owners do not type. A single
        // "Key: value" line, such as an owner's "Dimensions: 36 inches", is
        // always kept as text, wherever it appears, so it can never be absorbed
        // into or overwritten by the generated line.
        var attributes: [String: String] = [:]
        var proseLines: [String] = []
        if aiParagraph != nil {
            for line in normalized.components(separatedBy: "\n") {
                if let parsed = GeneratedDetailsLine.parse(line), parsed.count >= 2 {
                    attributes.merge(parsed) { _, later in later }
                } else {
                    proseLines.append(line)
                }
            }
        } else {
            proseLines = normalized.components(separatedBy: "\n")
        }
        let prose = collapseBlankLines(proseLines.joined(separator: "\n"))

        guard !prose.isEmpty else {
            return SavedDescription(origin: .empty, aiParagraph: nil, otherText: nil,
                                    prose: "", generatedAttributes: attributes)
        }

        guard let aiParagraph else {
            return SavedDescription(origin: .ownerWritten, aiParagraph: nil, otherText: prose,
                                    prose: prose, generatedAttributes: attributes)
        }

        if prose == aiParagraph {
            return SavedDescription(origin: .aiGenerated, aiParagraph: aiParagraph, otherText: nil,
                                    prose: prose, generatedAttributes: attributes)
        }

        // Unedited AI paragraph followed by text added on a new line.
        if prose.hasPrefix(aiParagraph + "\n") {
            let remainder = String(prose.dropFirst(aiParagraph.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return SavedDescription(origin: .aiGenerated, aiParagraph: aiParagraph,
                                    otherText: remainder.isEmpty ? nil : remainder,
                                    prose: prose, generatedAttributes: attributes)
        }

        return SavedDescription(origin: .mixed, aiParagraph: nil, otherText: prose,
                                prose: prose, generatedAttributes: attributes)
    }

    /// Trims and reduces runs of blank lines to a single blank line.
    static func collapseBlankLines(_ text: String) -> String {
        var output: [String] = []
        var previousBlank = false
        for line in text.components(separatedBy: "\n") {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if !previousBlank && !output.isEmpty { output.append("") }
            } else {
                output.append(line)
            }
            previousBlank = isBlank
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Applier

enum ItemAnalysisApplier {

    struct ComposedDescription: Equatable {
        /// The description to save.
        let description: String
        /// The AI paragraph written into it, or nil when the prose was kept
        /// unchanged. Saved as `llmGeneratedDescription` when non-nil.
        let appliedAIParagraph: String?
    }

    /// Builds the description to save after applying `analysis`.
    static func composeDescription(
        current: String,
        llmGeneratedDescription: String?,
        analysis: ItemAnalysis
    ) -> ComposedDescription {
        let saved = SavedDescription.classify(
            description: current,
            llmGeneratedDescription: llmGeneratedDescription
        )

        var attributes = saved.generatedAttributes
        attributes.merge(GeneratedDetailsLine.attributes(from: analysis)) { _, new in new }
        let detailsLine = GeneratedDetailsLine.build(attributes)

        let newParagraph = analysis.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        let prose: String
        let applied: String?
        if newParagraph.isEmpty {
            prose = saved.prose
            applied = nil
        } else {
            switch saved.origin {
            case .aiGenerated:
                // A one-segment generated line (an analysis that returned one
                // attribute) is not recognized on the next run and comes back as
                // text. Drop such a line only when it repeats, exactly, a value
                // now in the generated line, so repeated runs stay stable and no
                // information is lost.
                let others = saved.otherText.map { dropLinesRepeating(attributes, in: $0) }
                prose = join([newParagraph, others])
                applied = newParagraph
            case .empty, .ownerWritten:
                prose = join([newParagraph, saved.otherText])
                applied = newParagraph
            case .mixed:
                prose = saved.prose
                applied = nil
            }
        }

        return ComposedDescription(
            description: join([prose, detailsLine]),
            appliedAIParagraph: applied
        )
    }

    // MARK: - Selective apply (Stage 4 review)

    /// What to do with the description paragraph.
    enum ParagraphChoice: Equatable, Sendable {
        /// Leave the existing prose exactly as it is.
        case keep
        /// Use the AI paragraph. By origin: replaces an empty description or
        /// the earlier AI paragraph (owner additions kept); goes above an
        /// owner-written description (kept below); replaces a mixed one.
        case useAI
    }

    /// Builds the description for the owner's review choices. Nothing is
    /// changed unless chosen: with `.keep` and no accepted attributes the
    /// original text is returned unchanged. Owner text is never merged away
    /// (unlike `composeDescription`, single "Key: value" lines that repeat a
    /// generated value are kept).
    static func composeDescription(
        current: String,
        llmGeneratedDescription: String?,
        analysis: ItemAnalysis,
        paragraph: ParagraphChoice,
        acceptedAttributeLabels: Set<String>
    ) -> ComposedDescription {
        let saved = SavedDescription.classify(
            description: current,
            llmGeneratedDescription: llmGeneratedDescription
        )

        let proposed = GeneratedDetailsLine.attributes(from: analysis)
        var attributes = saved.generatedAttributes
        for (label, value) in proposed where acceptedAttributeLabels.contains(label) {
            attributes[label] = value
        }
        let attributesChanged = attributes != saved.generatedAttributes

        let newParagraph = analysis.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let useAI = paragraph == .useAI && !newParagraph.isEmpty

        if !useAI && !attributesChanged {
            return ComposedDescription(description: current, appliedAIParagraph: nil)
        }

        let prose: String
        if useAI {
            switch saved.origin {
            case .empty, .aiGenerated:
                prose = join([newParagraph, saved.otherText])
            case .ownerWritten:
                prose = join([newParagraph, saved.prose])
            case .mixed:
                prose = newParagraph
            }
        } else {
            prose = saved.prose
        }

        return ComposedDescription(
            description: join([prose, GeneratedDetailsLine.build(attributes)]),
            appliedAIParagraph: useAI ? newParagraph : nil
        )
    }

    /// The owner's choices from the review screen.
    struct Choices: Equatable, Sendable {
        var title = false
        var category = false
        var paragraph: ParagraphChoice = .keep
        var attributeLabels: Set<String> = []
        var valuation = false

        var isEmpty: Bool {
            !title && !category && paragraph == .keep && attributeLabels.isEmpty && !valuation
        }
    }

    /// Applies only what the owner chose. Anything not chosen is left exactly
    /// as it was: a declined valuation keeps the stored value, range,
    /// confidence and notes; a kept description is not rewritten. Owner notes
    /// are never touched.
    static func apply(_ analysis: ItemAnalysis, to item: LTCItem, choices: Choices) {
        let title = analysis.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if choices.title, !title.isEmpty {
            item.name = analysis.title
            item.llmGeneratedTitle = analysis.title
        }

        if choices.category {
            item.category = LTCItem.normalizeCategory(analysis.category)
        }

        let composed = composeDescription(
            current: item.itemDescription,
            llmGeneratedDescription: item.llmGeneratedDescription,
            analysis: analysis,
            paragraph: choices.paragraph,
            acceptedAttributeLabels: choices.attributeLabels
        )
        if composed.description != item.itemDescription {
            item.itemDescription = composed.description
        }
        if let paragraph = composed.appliedAIParagraph {
            item.llmGeneratedDescription = paragraph
        }

        if choices.valuation, let valueHints = analysis.valueHints {
            applyValuation(valueHints, to: item)
        }

        if !choices.isEmpty {
            item.updatedAt = .now
        }
    }

    /// Improve with AI "Apply Suggestions": writes the analysis into the item.
    /// Title, category, value and valuation behave as before; the description
    /// follows the preservation rules above. Owner notes are not touched.
    static func apply(_ analysis: ItemAnalysis, to item: LTCItem) {
        item.name = analysis.title
        item.category = LTCItem.normalizeCategory(analysis.category)

        let composed = composeDescription(
            current: item.itemDescription,
            llmGeneratedDescription: item.llmGeneratedDescription,
            analysis: analysis
        )
        item.itemDescription = composed.description
        if let paragraph = composed.appliedAIParagraph {
            item.llmGeneratedDescription = paragraph
        }

        if let valueHints = analysis.valueHints {
            applyValuation(valueHints, to: item)
        }

        item.llmGeneratedTitle = analysis.title
    }

    // MARK: - Helpers

    /// Writes the AI estimate: per-unit value (midpoint), suggested prices and
    /// the stored valuation (range, confidence, notes, missing details).
    private static func applyValuation(_ valueHints: ValueHints, to item: LTCItem) {
        let mid: Double? = {
            if let est = valueHints.estimatedValue { return est }
            if let low = valueHints.valueLow, let high = valueHints.valueHigh { return (low + high) / 2.0 }
            if let low = valueHints.valueLow { return low }
            if let high = valueHints.valueHigh { return high }
            return nil
        }()

        // A missing estimate leaves the current value untouched; an explicit
        // AI estimate of $0 is stored (see LTCItem.estimatedUnitValue).
        if let mid {
            item.value = max(mid, 0)
        }

        if let high = valueHints.valueHigh {
            item.suggestedPriceNew = high
        } else if let est = valueHints.estimatedValue {
            item.suggestedPriceNew = est
        }

        if let low = valueHints.valueLow {
            item.suggestedPriceUsed = low
        } else if let est = valueHints.estimatedValue {
            item.suggestedPriceUsed = est
        }

        upsertValuation(on: item, from: valueHints)
    }

    private static func upsertValuation(on item: LTCItem, from hints: ValueHints) {
        let valuation: ItemValuation
        if let existing = item.valuation {
            valuation = existing
        } else {
            valuation = ItemValuation(currencyCode: hints.currencyCode)
            item.valuation = valuation
        }

        valuation.valueLow = hints.valueLow
        valuation.estimatedValue = hints.estimatedValue
        valuation.valueHigh = hints.valueHigh
        valuation.currencyCode = hints.currencyCode
        valuation.confidenceScore = hints.confidenceScore
        valuation.aiProvider = hints.aiProvider
        valuation.aiNotes = hints.aiNotes
        valuation.missingDetails = hints.missingDetails ?? valuation.missingDetails

        if let dateString = hints.valuationDate {
            valuation.valuationDate = ISO8601DateFormatter().date(from: dateString)
        }

        valuation.updatedAt = .now
    }

    /// Removes lines that are a single "Key: value" exactly equal to an entry
    /// of `attributes` (the generated line being written). Every other line,
    /// including a single "Key: value" with a different value, is kept.
    private static func dropLinesRepeating(_ attributes: [String: String], in text: String) -> String {
        let kept = text.components(separatedBy: "\n").filter { line in
            guard let parsed = GeneratedDetailsLine.parse(line),
                  parsed.count == 1,
                  let (key, value) = parsed.first else { return true }
            return attributes[key] != value
        }
        return SavedDescription.collapseBlankLines(kept.joined(separator: "\n"))
    }

    /// Joins non-empty paragraphs with one blank line between them.
    private static func join(_ parts: [String?]) -> String {
        parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
