//
//  ExternalSearchLinks.swift
//  LegacyTreasureChest
//
//  B1: builds (never opens or sends) an item-specific web search and a copyable
//  prompt a homeowner can use to look for specialists themselves. Built only
//  from a reviewed Search Intent plus an optional city/state, so no names,
//  descriptions, values, or identifiers are included. B2 shows these after
//  review and opens the link with the system's normal URL handling.
//

import Foundation

nonisolated enum ExternalSearchLinks {

    /// Words for a web search, e.g. "film camera consignment near Boise, ID".
    static func webSearchQuery(for intent: DispositionSearchIntentDTO, city: String? = nil, region: String? = nil) -> String {
        let phrase = intent.phrase
        let lead: String
        switch DispositionSearchStrategy(rawValue: intent.strategy) ?? .consignment {
        case .consignment: lead = "\(phrase) consignment"
        case .maximizePrice: lead = "sell \(phrase) specialist dealer"
        case .quickSale: lead = "sell \(phrase) buyer"
        case .donation: lead = "donate \(phrase)"
        }

        let place: String?
        switch DispositionGeoScope(rawValue: intent.geoScope) ?? .local {
        case .local:
            let named = [city, region].compactMap(nonEmpty).joined(separator: ", ")
            place = named.isEmpty ? nil : "near \(named)"
        case .regional:
            place = nonEmpty(region).map { "in \($0)" }
        case .national:
            place = intent.strategy == DispositionSearchStrategy.donation.rawValue ? nil : "mail-in nationwide"
        }
        return [lead, place].compactMap { $0 }.joined(separator: " ")
    }

    /// A properly encoded Google web search URL for the query above.
    static func webSearchURL(for intent: DispositionSearchIntentDTO, city: String? = nil, region: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: webSearchQuery(for: intent, city: city, region: region))]
        // URLComponents leaves "+" and "&"-adjacent characters ambiguous in queries; encode them explicitly.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// A prompt the homeowner can paste into a search assistant of their choice.
    static func discoveryPrompt(for intent: DispositionSearchIntentDTO, city: String? = nil, region: String? = nil) -> String {
        let item = intent.detailTerms.isEmpty
            ? intent.phrase
            : "\(intent.phrase) (\(intent.detailTerms.joined(separator: ", ")))"

        let goal: String
        let ask: String
        switch DispositionSearchStrategy(rawValue: intent.strategy) ?? .consignment {
        case .consignment:
            goal = "consign my \(item) with a business that will sell it for me"
            ask = "whether each one takes items on consignment, buys outright, or auctions them, and its usual commission if published"
        case .maximizePrice:
            goal = "sell my \(item) for the best realistic price, through a specialist dealer, auction house, or specialist marketplace"
            ask = "whether each one buys outright, consigns, auctions, or lists items, and its usual fees if published"
        case .quickSale:
            goal = "sell my \(item) quickly to a business that buys items like this"
            ask = "whether each one buys outright and how it makes offers"
        case .donation:
            goal = "donate my \(item) to an organization that accepts it"
            ask = "whether each one accepts this kind of item, offers pickup, and provides a donation receipt"
        }

        let whereText: String
        switch DispositionGeoScope(rawValue: intent.geoScope) ?? .local {
        case .local:
            let place = [city, region].compactMap(nonEmpty).joined(separator: ", ")
            whereText = place.isEmpty ? "near me" : "near \(place)"
        case .regional:
            whereText = nonEmpty(region).map { "in \($0)" } ?? "in my state"
        case .national:
            whereText = "anywhere in the United States (shipping or mail-in is fine)"
        }

        return """
        I want to \(goal), \(whereText). Please suggest specific businesses with a link to each one's own website, and tell me \(ask). Only include businesses you can point to a website for. I will contact them myself to confirm they accept my item before sending or delivering anything.
        """
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
