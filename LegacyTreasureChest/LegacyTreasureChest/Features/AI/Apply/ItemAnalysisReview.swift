//
//  ItemAnalysisReview.swift
//  LegacyTreasureChest
//
//  What Improve with AI proposes, compared with the item as it is, plus the
//  default choices and the warnings shown on the review screen (LTC 1.3).
//
//  Defaults are conservative:
//  - Owner-written or edited descriptions are kept unless the owner opts in.
//  - Attributes already in the item that the AI would change are kept: the
//    generated details line may have been edited by the owner, and that
//    cannot be detected, so changes are offered but not preselected.
//  - When a document was analyzed, no text suggestion is preselected: the
//    owner decides what document-derived text to save.
//  - A valuation whose unit looks inconsistent with the item's quantity is
//    not preselected.
//  Nothing is applied until the owner taps Apply.
//

import Foundation

struct ItemAnalysisReview: Equatable {

    // MARK: Current vs proposed

    struct TextChange: Equatable {
        let current: String
        let proposed: String
        var isChange: Bool { current != proposed }
    }

    enum AttributeKind: Equatable {
        /// The AI identified something the item does not have yet.
        case new
        /// The AI's value differs from the item's existing value.
        case changed
        /// Same value (ignoring case and spacing).
        case same
        /// The item has it; the AI did not mention it. It is kept.
        case notMentioned
    }

    struct AttributeRow: Equatable, Identifiable {
        let label: String
        let current: String?
        let proposed: String?
        let kind: AttributeKind
        var id: String { label }
        /// Rows the owner can accept (new or changed values).
        var isSelectable: Bool { kind == .new || kind == .changed }
    }

    /// What one catalog unit the AI's figures cover, relative to the item's
    /// quantity. LTC establishes this; the owner only accepts or declines.
    enum ValuationBasis: Equatable {
        /// The figures are for one unit (always when quantity is 1: the unit is
        /// the whole catalog entry, e.g. a complete china service).
        case perUnit
        /// The figures price all `size` units together, and `size` equals the
        /// item's quantity: LTC allocates them equally per unit.
        case group(size: Int)
        /// LTC cannot establish a per-unit figure; nothing is applied.
        case ambiguous(AmbiguityReason)
    }

    enum AmbiguityReason: Equatable {
        /// The AI did not say what its estimate covers.
        case unstated
        /// The AI priced a group whose size differs from the item's quantity.
        case conflictingCount(Int)
        /// The AI priced a set or group without a usable count.
        case unclearGroup
    }

    struct Valuation: Equatable {
        let quantity: Int
        let currentUnitValue: Double?
        let basis: ValuationBasis
        /// The AI's figures as returned (per unit, or for the whole group).
        let aiLow: Double?
        let aiEstimate: Double?
        let aiHigh: Double?
        let unit: String?
        let confidenceLabel: String?
        let explanation: String?

        var hasEstimate: Bool { aiEstimate != nil }
        var isAllocation: Bool { if case .group = basis { return true } else { return false } }
        var isAmbiguous: Bool { if case .ambiguous = basis { return true } else { return false } }
        /// Whether this valuation may be applied at all.
        var canApply: Bool { hasEstimate && !isAmbiguous }

        private var divisor: Double {
            if case .group(let size) = basis { return Double(max(size, 1)) }
            return 1
        }

        /// Per-unit figures LTC would apply (nil when not applicable).
        var proposedLow: Double? { canApply ? aiLow.map { $0 / divisor } : nil }
        var proposedEstimate: Double? { canApply ? aiEstimate.map { $0 / divisor } : nil }
        var proposedHigh: Double? { canApply ? aiHigh.map { $0 / divisor } : nil }

        var proposedTotal: Double? {
            guard quantity > 1, let proposedEstimate else { return nil }
            return proposedEstimate * Double(quantity)
        }
        var currentTotal: Double? {
            guard quantity > 1, let currentUnitValue else { return nil }
            return currentUnitValue * Double(quantity)
        }
    }

    enum Warning: Equatable, Identifiable {
        /// LTC could not establish a per-unit estimate; the value is not applied.
        case valuationUnclear(quantity: Int, unit: String?)
        /// The AI priced all units together; LTC shows an equal allocation.
        case groupAllocation(quantity: Int)
        /// The AI noted conflicts between evidence, owner notes and earlier details.
        case conflict(String)
        /// Proposed text contains what may be a report/certificate number or
        /// personal details.
        case possibleIdentifier
        /// A document was analyzed; text suggestions may come from it.
        case documentDerived
        /// The proposed value differs from the current value by 3× or more.
        case largeValueChange(current: Double, proposed: Double)
        /// Quantity is 1 and nothing in the item says it is a set, but the AI
        /// priced a group ("set of six chairs"). Shown, and not preselected.
        case singleItemGroupPrice(unit: String)

        var id: String {
            switch self {
            case .valuationUnclear: return "unit"
            case .groupAllocation: return "allocation"
            case .conflict(let text): return "conflict-\(text)"
            case .possibleIdentifier: return "identifier"
            case .documentDerived: return "document"
            case .largeValueChange: return "value"
            case .singleItemGroupPrice: return "single-group"
            }
        }
    }

    let title: TextChange
    let category: TextChange
    let saved: SavedDescription
    let currentDescription: String
    let proposedParagraph: String
    let attributes: [AttributeRow]
    let valuation: Valuation
    /// The value hints to store if the owner accepts the valuation: per-unit
    /// (allocated for a group estimate, with the group basis in the notes).
    /// Nil when the valuation cannot be applied.
    let valueHintsToApply: ValueHints?
    let warnings: [Warning]
    let defaults: ItemAnalysisApplier.Choices
    let includedDocument: Bool

    // MARK: Building

    @MainActor
    init(item: LTCItem, analysis: ItemAnalysis, includedDocument: Bool) {
        self.init(
            currentTitle: item.name,
            currentCategory: item.category,
            currentDescription: item.itemDescription,
            llmGeneratedDescription: item.llmGeneratedDescription,
            quantity: max(item.quantity, 1),
            currentUnitValue: item.estimatedUnitValue,
            analysis: analysis,
            includedDocument: includedDocument,
            ownerNotes: item.valuation?.userNotes
        )
    }

    init(currentTitle: String, currentCategory: String, currentDescription: String,
         llmGeneratedDescription: String?, quantity: Int, currentUnitValue: Double?,
         analysis: ItemAnalysis, includedDocument: Bool, ownerNotes: String? = nil) {
        let proposedTitle = analysis.title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = TextChange(current: currentTitle, proposed: proposedTitle)
        category = TextChange(current: currentCategory, proposed: LTCItem.normalizeCategory(analysis.category))
        self.currentDescription = currentDescription
        self.includedDocument = includedDocument
        saved = SavedDescription.classify(description: currentDescription, llmGeneratedDescription: llmGeneratedDescription)
        proposedParagraph = analysis.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        // Attributes: existing generated details vs the AI's.
        let proposedAttributes = GeneratedDetailsLine.attributes(from: analysis)
        let existing = saved.generatedAttributes
        attributes = GeneratedDetailsLine.keys.compactMap { label in
            let current = existing[label]
            let proposed = proposedAttributes[label]
            switch (current, proposed) {
            case (nil, nil): return nil
            case (nil, .some): return AttributeRow(label: label, current: nil, proposed: proposed, kind: .new)
            case (.some, nil): return AttributeRow(label: label, current: current, proposed: nil, kind: .notMentioned)
            case let (.some(c), .some(p)):
                let same = Self.normalized(c) == Self.normalized(p)
                return AttributeRow(label: label, current: c, proposed: p, kind: same ? .same : .changed)
            }
        }

        // Valuation.
        let hints = analysis.valueHints
        let estimate: Double? = {
            if let e = hints?.estimatedValue { return e }
            if let l = hints?.valueLow, let h = hints?.valueHigh { return (l + h) / 2 }
            return hints?.valueLow ?? hints?.valueHigh
        }()
        let unitText = analysis.valuationUnit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = (unitText?.isEmpty ?? true) ? nil : unitText
        let basis = Self.valuationBasis(quantity: quantity, unit: unit)
        let builtValuation = Valuation(
            quantity: quantity,
            currentUnitValue: currentUnitValue,
            basis: basis,
            aiLow: hints?.valueLow,
            aiEstimate: estimate,
            aiHigh: hints?.valueHigh,
            unit: unit,
            confidenceLabel: estimate == nil ? nil : ItemValuationPresentation.confidenceLabel(for: hints?.confidenceScore),
            explanation: hints?.aiNotes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        valuation = builtValuation
        valueHintsToApply = hints.flatMap { Self.perUnitHints($0, valuation: builtValuation) }

        // Warnings.
        var warnings: [Warning] = []
        if valuation.hasEstimate {
            switch basis {
            case .ambiguous: warnings.append(.valuationUnclear(quantity: quantity, unit: unit))
            case .group: warnings.append(.groupAllocation(quantity: quantity))
            case .perUnit: break
            }
        }
        // Name and owner notes only: narrative descriptions ("passed down through four
        // generations") are too loose to say whether the entry is a set.
        let itemText = [currentTitle, ownerNotes ?? ""].joined(separator: " ")
        let singleItemGroup = valuation.hasEstimate && quantity == 1 && Self.unitNamesGroup(unit)
            && !Self.itemTextDescribesSet(itemText)
        if singleItemGroup, let unit { warnings.append(.singleItemGroupPrice(unit: unit)) }
        for conflict in (analysis.conflicts ?? []) {
            let text = conflict.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { warnings.append(.conflict(text)) }
        }
        let proposedText = ([proposedTitle, proposedParagraph] + proposedAttributes.values).joined(separator: "\n")
        if Self.containsPossibleIdentifier(proposedText) {
            warnings.append(.possibleIdentifier)
        }
        if includedDocument {
            warnings.append(.documentDerived)
        }
        if let current = currentUnitValue, current > 0, let perUnit = valuation.proposedEstimate, perUnit > 0,
           max(current, perUnit) / min(current, perUnit) >= 3 {
            warnings.append(.largeValueChange(current: current, proposed: perUnit))
        }
        self.warnings = warnings

        // Default choices.
        var choices = ItemAnalysisApplier.Choices()
        let textPreselected = !includedDocument
        choices.title = textPreselected && title.isChange && !proposedTitle.isEmpty
        let uncategorized = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || currentCategory == "Uncategorized"
        choices.category = category.isChange && uncategorized
        if textPreselected && !proposedParagraph.isEmpty {
            switch saved.origin {
            case .empty, .aiGenerated: choices.paragraph = .useAI
            case .ownerWritten, .mixed: choices.paragraph = .keep
            }
        }
        // A specific year in Era is often an owner claim, a maker's anniversary date or a
        // purchase date rather than a verified manufacturing year: shown, never preselected.
        choices.attributeLabels = textPreselected
            ? Set(attributes.filter { $0.kind == .new && !($0.label == "Era" && Self.namesSpecificYear($0.proposed)) }
                .map(\.label))
            : []
        // Per-unit estimates are preselected; an allocated group estimate needs a
        // deliberate choice; an ambiguous one cannot be applied.
        // A group price for what the item describes as one object needs a deliberate choice.
        choices.valuation = valuation.canApply && basis == .perUnit && !singleItemGroup
        defaults = choices
    }

    // MARK: Derived

    /// The value cannot be applied because its unit is unclear.
    var hasUnitWarning: Bool { valuation.hasEstimate && valuation.isAmbiguous }

    var categoryChanged: Bool { category.isChange }

    /// How the description toggle reads, by where the current text came from.
    var paragraphActionLabel: String {
        switch saved.origin {
        case .empty: return "Use the AI description"
        case .aiGenerated: return "Replace the earlier AI description"
        case .ownerWritten: return "Add the AI description above yours"
        case .mixed: return "Replace your current description"
        }
    }

    /// Plain description of where the current text came from.
    var currentDescriptionOrigin: String {
        switch saved.origin {
        case .empty: return "No description yet"
        case .aiGenerated: return saved.otherText == nil ? "Earlier AI suggestion" : "Earlier AI suggestion with your additions"
        case .ownerWritten: return "Written by you"
        case .mixed: return "Edited after an AI suggestion"
        }
    }

    /// True when choosing the AI paragraph removes current text.
    var paragraphReplacesOwnerText: Bool { saved.origin == .mixed }

    /// The description that would be saved with `choices`.
    func previewDescription(analysis: ItemAnalysis, llmGeneratedDescription: String?,
                            choices: ItemAnalysisApplier.Choices) -> String {
        ItemAnalysisApplier.composeDescription(
            current: currentDescription,
            llmGeneratedDescription: llmGeneratedDescription,
            analysis: analysis,
            paragraph: choices.paragraph,
            acceptedAttributeLabels: choices.attributeLabels
        ).description
    }

    // MARK: Heuristics

    static func normalized(_ text: String) -> String {
        text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Establishes what the AI's figures cover. Quantity 1 is always per unit
    /// (the catalog entry is the unit). For quantity > 1: a stated group count
    /// equal to the quantity is a group estimate; a different count, a set or
    /// group without a count, or no unit at all is ambiguous; otherwise the
    /// figures are per unit ("one stool", "each", "stool").
    static func valuationBasis(quantity: Int, unit: String?) -> ValuationBasis {
        guard quantity > 1 else { return .perUnit }
        guard let unit, !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .ambiguous(.unstated)
        }
        let text = " " + unit.lowercased().replacingOccurrences(of: "-", with: " - ") + " "

        if let count = groupCount(in: text) {
            if count == quantity { return .group(size: count) }
            if count == 1 { return .perUnit }
            return .ambiguous(.conflictingCount(count))
        }
        let single = ["^\\s*(one|a|an|single|each|per)\\b", "\\beach\\b", "\\bper (item|unit|piece)\\b"]
        if single.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) {
            return .perUnit
        }
        let groupWords = ["set", "service", "collection", "lot", "group", "all", "total", "together", "combined"]
        if groupWords.contains(where: { text.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }) {
            return .ambiguous(.unclearGroup)
        }
        return .perUnit
    }

    /// At quantity 1: the AI's unit names a group of several things ("set of six
    /// chairs", "pair of lamps", "4 stools", "collection"). The approved rule still
    /// treats it as the whole catalog entry; this only decides whether to flag it.
    static func unitNamesGroup(_ unit: String?) -> Bool {
        guard let unit, !unit.isEmpty else { return false }
        let text = " " + unit.lowercased().replacingOccurrences(of: "-", with: " - ") + " "
        if let n = groupCount(in: text) { return n >= 2 }
        return ["set", "collection", "lot", "group", "pair", "suite"]
            .contains { text.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }
    }

    /// The owner's own text (the item name and owner notes) says this entry is several
    /// things cataloged together: a set word, or a count of 2 or more before a plural noun.
    static func itemTextDescribesSet(_ text: String) -> Bool {
        let t = " " + text.lowercased().replacingOccurrences(of: "—", with: " ").replacingOccurrences(of: "-", with: " ") + " "
        let setWords = ["set", "sets", "pair", "pairs", "service", "collection", "lot", "group", "suite", "settings",
                        "pieces", "piece", "matching", "both", "dozen", "assortment", "assorted"]
        if setWords.contains(where: { t.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }) { return true }
        let numbers = "two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|[2-9]|[1-9][0-9]+"
        // A count followed by a plural noun ("6 chairs", "ten place settings"); not "Four-poster bed".
        return t.range(of: "\\b(\(numbers))\\s+(?:[a-z]+\\s+)?[a-z]+s\\b", options: .regularExpression) != nil
    }

    /// The number of items a unit description names as priced together, e.g.
    /// "set of four stools" → 4, "4 stools" → 4, "all 6" → 6, "pair" → 2.
    static func groupCount(in text: String) -> Int? {
        let patterns = [
            "\\b(?:set|group|lot|collection|pair) of (\\w+)\\b",
            "\\b(?:all|both) (\\w+)\\b",
            "^\\s*(\\w+) (?:identical |matching )?[a-z]+s\\b",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            if let n = number(String(text[range])) { return n }
        }
        if text.range(of: "\\b(pair|both)\\b", options: .regularExpression) != nil { return 2 }
        return nil
    }

    static func number(_ word: String) -> Int? {
        if let n = Int(word) { return n }
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
                     "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "dozen": 12]
        return words[word]
    }

    /// Value hints to store on acceptance: unchanged for a per-unit estimate;
    /// divided equally for a group estimate, with the group basis recorded in
    /// the notes; nil when the valuation cannot be applied.
    static func perUnitHints(_ hints: ValueHints, valuation: Valuation) -> ValueHints? {
        guard valuation.canApply else { return nil }
        guard case .group(let size) = valuation.basis else { return hints }
        var perUnit = hints
        perUnit.valueLow = valuation.proposedLow
        perUnit.estimatedValue = valuation.proposedEstimate
        perUnit.valueHigh = valuation.proposedHigh
        let group = [valuation.aiLow, valuation.aiHigh].compactMap { $0 }.map { CurrencyFormat.dollars($0) }.joined(separator: "–")
        let each = [valuation.proposedLow, valuation.proposedHigh].compactMap { $0 }.map { CurrencyFormat.dollars($0) }.joined(separator: "–")
        var note = "Allocated from a group estimate: the AI estimated all \(size) together at \(group)"
        if let mid = valuation.aiEstimate { note += " (midpoint \(CurrencyFormat.dollars(mid)))" }
        note += ". LTC divided it equally: \(each) per item"
        if let mid = valuation.proposedEstimate { note += " (midpoint \(CurrencyFormat.dollars(mid)))" }
        note += ". This is an allocation, not a separately established selling price for one item."
        if let original = hints.aiNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !original.isEmpty {
            note += "\n\n" + original
        }
        perUnit.aiNotes = note
        return perUnit
    }

    /// Long digit runs (report/certificate/account numbers), labeled report or
    /// certificate numbers, email addresses, phone numbers or street
    /// addresses. Heuristic only; the owner reviews the text either way.
    static func containsPossibleIdentifier(_ text: String) -> Bool {
        if containsLongDigitRun(text) { return true }
        let patterns = [
            "(?i)\\b(report|certificate|cert|appraisal|policy|account|serial)\\s*(no\\.?|number|#)\\s*[:#]?\\s*[A-Z0-9-]{4,}",
            "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
            "\\(?\\b\\d{3}\\)?[ .-]\\d{3}[ .-]\\d{4}\\b",
            "(?i)\\b\\d{1,5}\\s+[A-Za-z]+(\\s[A-Za-z]+)?\\s+(street|st|avenue|ave|road|rd|lane|ln|drive|dr|blvd|court|ct)\\b",
        ]
        return patterns.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// A run of 8+ digits (dashes allowed inside), except a historical year range such as
    /// "1857-2007": two 4-digit years from 1000 to 2099, the second not earlier than the first.
    static func containsLongDigitRun(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "\\b\\d[\\d-]{6,}\\d\\b") else { return false }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).contains { match in
            !isYearRange(ns.substring(with: match.range))
        }
    }

    static func isYearRange(_ token: String) -> Bool {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 4 }),
              let from = Int(parts[0]), let to = Int(parts[1]) else { return false }
        return (1000...2099).contains(from) && (1000...2099).contains(to) && to >= from
    }

    /// True when an Era value names a specific year ("1890", "circa 1925", "2007"), not a broad era.
    static func namesSpecificYear(_ era: String?) -> Bool {
        guard let era else { return false }
        return era.range(of: "\\b(1[0-9]|20)[0-9]{2}\\b(?!s)", options: .regularExpression) != nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
