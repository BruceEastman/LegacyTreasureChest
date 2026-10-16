//
//  SearchIntentBuilder.swift
//  LegacyTreasureChest
//
//  B1: suggests a specialty Search Intent from what LTC already has, so the
//  homeowner can review and edit it (B2) before anything is sent.
//
//  - Deterministic: no network, no AI call, same input gives the same result.
//  - The saved Plan's chosen approach is the authority for the strategy (the
//    Brief's original recommendation is not used).
//  - Wording comes from the Brief's specialty block when present, otherwise
//    from the category, Set type, or a cleaned item name. Personal possessives,
//    long numbers, emails, and web addresses are removed; descriptions, notes,
//    values, IDs, photos, and documents are never used.
//  - SearchIntentValidator mirrors the Gateway's checks (intent.py).
//

import Foundation

enum DispositionSearchStrategy: String, Codable, CaseIterable, Sendable {
    case maximizePrice
    case consignment
    case quickSale
    case donation

    /// The strategy for a chosen approach; nil for More Information Needed.
    init?(path: LiquidationPathDTO) {
        switch path {
        case .pathA_maximizePrice: self = .maximizePrice
        case .pathB_delegateConsign: self = .consignment
        case .pathC_quickExit: self = .quickSale
        case .donate: self = .donation
        case .needsInfo: return nil
        }
    }
}

enum DispositionGeoScope: String, Codable, CaseIterable, Sendable {
    case local
    case regional
    case national
}

/// A suggested intent for the homeowner to review. Not sent until confirmed.
struct SearchIntentSuggestion: Equatable, Sendable {
    var strategy: DispositionSearchStrategy
    var phrase: String
    var detailTerms: [String]
    var geoScope: DispositionGeoScope
    /// Where the wording came from, for the review screen.
    var phraseSource: PhraseSource

    enum PhraseSource: String, Sendable {
        case specialty      // the Brief's specialty block
        case category       // the item category or Set type
        case itemName       // a cleaned item or Set name
        case fallback       // nothing better was available
    }

    /// The intent as it would be sent, after validation. valueBand is never set here.
    func intent() throws -> DispositionSearchIntentDTO {
        try SearchIntentValidator.validated(DispositionSearchIntentDTO(
            strategy: strategy.rawValue,
            phrase: phrase,
            detailTerms: detailTerms,
            geoScope: geoScope.rawValue,
            valueBand: nil
        ))
    }
}

nonisolated enum SearchIntentValidator {
    static let maxPhraseCharacters = 60
    static let maxPhraseWords = 8
    static let maxDetailTerms = 4
    static let maxDetailTermCharacters = 30

    enum ValidationError: LocalizedError, Equatable {
        case empty, tooLong, tooManyWords, containsContactOrWebAddress, containsLongNumber
        case unsupportedCharacters, tooManyDetailTerms, unknownStrategy, unknownScope

        var errorDescription: String? {
            switch self {
            case .empty: return "Enter a few words describing the item."
            case .tooLong, .tooManyWords: return "Use a shorter description (a few words)."
            case .containsContactOrWebAddress: return "Remove email or web addresses from the search."
            case .containsLongNumber: return "Remove long numbers such as phone or serial numbers."
            case .unsupportedCharacters: return "Use only letters, numbers, and simple punctuation."
            case .tooManyDetailTerms: return "Use up to four detail words."
            case .unknownStrategy, .unknownScope: return "This search could not be prepared."
            }
        }
    }

    /// Whitespace-collapsed text, or a validation error (same rules as the Gateway).
    static func clean(_ text: String, maxCharacters: Int, maxWords: Int) throws -> String {
        let s = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !s.isEmpty else { throw ValidationError.empty }
        guard s.count <= maxCharacters else { throw ValidationError.tooLong }
        guard s.split(separator: " ").count <= maxWords else { throw ValidationError.tooManyWords }
        if s.range(of: #"[^\s@]+@[^\s@]+\.[^\s@]+"#, options: .regularExpression) != nil
            || s.range(of: #"(?i)(https?://|www\.)|\b[a-z0-9-]+\.(com|net|org|io|co|us|info|biz)\b"#,
                       options: .regularExpression) != nil {
            throw ValidationError.containsContactOrWebAddress
        }
        if longestDigitRun(in: s) >= 7 { throw ValidationError.containsLongNumber }
        guard s.range(of: #"^[\p{L}\p{N}_\s&'’.,/()+-]+$"#, options: .regularExpression) != nil else {
            throw ValidationError.unsupportedCharacters
        }
        return s
    }

    static func validated(_ intent: DispositionSearchIntentDTO) throws -> DispositionSearchIntentDTO {
        guard DispositionSearchStrategy(rawValue: intent.strategy) != nil else { throw ValidationError.unknownStrategy }
        guard DispositionGeoScope(rawValue: intent.geoScope) != nil else { throw ValidationError.unknownScope }
        var result = intent
        result.phrase = try clean(intent.phrase, maxCharacters: maxPhraseCharacters, maxWords: maxPhraseWords)
        guard intent.detailTerms.count <= maxDetailTerms else { throw ValidationError.tooManyDetailTerms }
        var terms: [String] = []
        for t in intent.detailTerms {
            let term = try clean(t, maxCharacters: maxDetailTermCharacters, maxWords: 4)
            if !terms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) { terms.append(term) }
        }
        result.detailTerms = terms
        if let band = result.valueBand, !["LOW", "MED", "HIGH"].contains(band) { result.valueBand = nil }
        return result
    }

    /// Digits in a run that may include phone/serial separators ("208-555-1234"),
    /// using the same pattern as the Gateway.
    static func longestDigitRun(in text: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: #"\d[\d\s().-]*\d|\d"#) else { return 0 }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range).filter(\.isNumber).count }
            .max() ?? 0
    }
}

enum SearchIntentBuilder {

    /// Categories that already name a kind of item; broad ones fall back to the item name.
    private static let categoryPhrases: [String: String] = [
        "art": "art",
        "furniture": "furniture",
        "jewelry": "jewelry",
        "rug": "rugs",
        "china & crystal": "china and crystal",
        "clothing": "clothing",
        "tools": "tools",
        "luggage": "luggage",
        "appliance": "appliances",
    ]

    private static let setTypePhrases: [SetType: String] = [
        .diningRoom: "dining room furniture",
        .bedroom: "bedroom furniture",
        .china: "china dinnerware",
        .crystal: "crystal stemware",
        .flatware: "silverware",
        .rugCollection: "rugs",
        .furnitureSuite: "furniture",
        .closetLot: "clothing",
    ]

    private static let closetPilePhrases: [String: String] = [
        "luxury": "designer clothing",
        "contemporary": "clothing",
        "donate": "clothing",
        "discard": "textile recycling",
    ]

    // MARK: - Entry point for Find Help (A3 request → B1 suggestion)

    /// The suggestion for a Find Help request opened from a Plan. Nil when the
    /// Plan has no selling approach (More Information Needed) or cannot be read.
    @MainActor
    static func suggestion(for request: LiquidationFindHelpRequest, owner: LiquidationOwner) -> SearchIntentSuggestion? {
        let state = owner.state
        let plan = state?.plans.first(where: { $0.planRecordId == request.planRecordId })
            ?? LiquidationWorkflow.activePlan(state)
        guard let plan else { return nil }
        let context = LiquidationWorkflow.checklist(of: plan)?.context
        let brief = LiquidationWorkflow.originatingBrief(of: plan, in: state).flatMap(LiquidationWorkflow.brief(of:))
        let approach = context?.chosenPath ?? request.approach ?? plan.chosenPath.briefPath

        switch owner {
        case .item(let item):
            return suggest(approach: approach, specialty: context?.specialty ?? brief?.specialty,
                           itemName: item.name, category: item.category)
        case .itemSet(let set):
            return suggest(approach: approach, specialty: context?.specialty ?? brief?.specialty,
                           setName: set.name, setType: set.setType, pile: request.group)
        }
    }

    // MARK: - Items

    static func suggest(
        approach: LiquidationPathDTO,
        specialty: LiquidationSpecialtyDTO?,
        itemName: String,
        category: String
    ) -> SearchIntentSuggestion? {
        guard let strategy = DispositionSearchStrategy(path: approach) else { return nil }
        let (phrase, source) = phraseFor(specialty: specialty, category: category, name: itemName)
        return SearchIntentSuggestion(
            strategy: strategy,
            phrase: phrase,
            detailTerms: detailTerms(specialty: specialty, excluding: phrase),
            geoScope: .local,
            phraseSource: source
        )
    }

    // MARK: - Sets

    /// For a closet-lot pile, the pile decides the wording; donate and discard
    /// piles are donations whatever the Plan's approach. The luxury pile starts
    /// with national scope (mail-in specialists); everything else starts local.
    static func suggest(
        approach: LiquidationPathDTO,
        specialty: LiquidationSpecialtyDTO?,
        setName: String,
        setType: SetType,
        pile: String?
    ) -> SearchIntentSuggestion? {
        guard var strategy = DispositionSearchStrategy(path: approach) else { return nil }
        var scope = DispositionGeoScope.local
        let phrase: String
        let source: SearchIntentSuggestion.PhraseSource

        if setType == .closetLot, let pile, let pilePhrase = closetPilePhrases[pile] {
            phrase = pilePhrase
            source = .category
            if pile == "donate" || pile == "discard" { strategy = .donation }
            if pile == "luxury" && strategy != .donation { scope = .national }
        } else if let kind = cleanedPhrase(specialty?.itemKind) {
            (phrase, source) = (kind, .specialty)
        } else if let typePhrase = setTypePhrases[setType] {
            (phrase, source) = (typePhrase, .category)
        } else if let named = cleanedPhrase(setName) {
            (phrase, source) = (named, .itemName)
        } else {
            (phrase, source) = ("household items", .fallback)
        }

        return SearchIntentSuggestion(
            strategy: strategy,
            phrase: phrase,
            detailTerms: detailTerms(specialty: specialty, excluding: phrase),
            geoScope: scope,
            phraseSource: source
        )
    }

    // MARK: - Wording

    private static func phraseFor(
        specialty: LiquidationSpecialtyDTO?,
        category: String,
        name: String
    ) -> (String, SearchIntentSuggestion.PhraseSource) {
        if let kind = cleanedPhrase(specialty?.itemKind) { return (kind, .specialty) }
        let key = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let phrase = categoryPhrases[key] { return (phrase, .category) }
        if let named = cleanedPhrase(name) { return (named, .itemName) }
        return ("household items", .fallback)
    }

    /// A short, shareable phrase: the item words before any "with …" or
    /// parenthetical, after any possessive ("Grandma Ruth's"), without long
    /// numbers, emails, or web addresses, at most five words. Nil when nothing
    /// usable remains.
    static func cleanedPhrase(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        for cut in [" with ", " w/ ", ",", "(", ";", " - ", ":"] {
            if let r = s.range(of: cut, options: .caseInsensitive) { s = String(s[..<r.lowerBound]) }
        }
        var all = s.split(whereSeparator: \.isWhitespace).map(String.init)
        // "Grandma Ruth's Leica camera" → "Leica camera": whoever owns it stays private.
        if let lastPossessive = all.lastIndex(where: {
            let l = $0.lowercased()
            return l.hasSuffix("'s") || l.hasSuffix("’s") || l.hasSuffix("s'") || l.hasSuffix("s’")
        }) {
            all = Array(all[(lastPossessive + 1)...])
        }
        let words = all.filter { word in
            let lower = word.lowercased()
            if word.contains("@") || lower.contains("www.") || lower.contains("://") { return false }
            if SearchIntentValidator.longestDigitRun(in: word) >= 7 { return false }
            return true
        }
        let trimmed = words.drop(while: { ["a", "an", "the", "my", "our"].contains($0.lowercased()) }).prefix(5)
        let phrase = trimmed.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-.,;:/&")))
        guard phrase.count >= 2,
              (try? SearchIntentValidator.clean(phrase, maxCharacters: SearchIntentValidator.maxPhraseCharacters,
                                                maxWords: SearchIntentValidator.maxPhraseWords)) != nil
        else { return nil }
        return phrase
    }

    /// Brand, model, and identifying terms from the Brief, valid and not already
    /// in the phrase, at most four.
    static func detailTerms(specialty: LiquidationSpecialtyDTO?, excluding phrase: String) -> [String] {
        guard let specialty else { return [] }
        var terms: [String] = []
        for candidate in [specialty.brand, specialty.model].compactMap({ $0 }) + specialty.detailTerms {
            guard let term = try? SearchIntentValidator.clean(
                candidate, maxCharacters: SearchIntentValidator.maxDetailTermCharacters, maxWords: 4) else { continue }
            if phrase.range(of: term, options: .caseInsensitive) != nil { continue }
            if terms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) { continue }
            terms.append(term)
            if terms.count == SearchIntentValidator.maxDetailTerms { break }
        }
        return terms
    }
}
