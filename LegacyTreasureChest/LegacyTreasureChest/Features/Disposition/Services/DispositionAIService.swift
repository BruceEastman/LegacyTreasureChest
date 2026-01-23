//
//  DispositionAIService.swift
//  LegacyTreasureChest
//
//  Builds Disposition Engine requests from item + set context and calls the backend.
//  Includes simple in-memory caching (TTL) for fast iteration/testing.
//

import Foundation

@MainActor
final class DispositionAIService {

    private let backend: BackendAIProvider

    // Simple in-memory cache with TTL
    private struct Cached {
        let response: DispositionPartnersSearchResponse
        let storedAt: Date
    }

    private var cache: [String: Cached] = [:]
    private let ttlSeconds: TimeInterval = 10 * 60 // 10 minutes

    init(backend: BackendAIProvider = BackendAIProvider()) {
        self.backend = backend
    }

    // MARK: - Item scope (existing)

    func searchPartners(
        item: LTCItem,
        location: DispositionLocationDTO,
        radiusMiles: Int
    ) async throws -> DispositionPartnersSearchResponse {

        let request = buildSearchRequest(item: item, location: location, radiusMiles: radiusMiles)
        let key = cacheKey(for: request)

        if let cached = cache[key], Date().timeIntervalSince(cached.storedAt) < ttlSeconds {
            return cached.response
        }

        let response = try await backend.dispositionPartnersSearch(request: request)
        cache[key] = Cached(response: response, storedAt: Date())
        return response
    }

    // MARK: - Set scope (new)

    enum SetPartnerBlock: String, Codable {
        case luxury
        case contemporary
    }

    func searchPartners(
        itemSet: LTCItemSet,
        block: SetPartnerBlock,
        chosenPath: DispositionChosenPath?,
        location: DispositionLocationDTO,
        radiusMiles: Int
    ) async throws -> DispositionPartnersSearchResponse {

        let request = buildSearchRequest(
            itemSet: itemSet,
            block: block,
            chosenPath: chosenPath,
            location: location,
            radiusMiles: radiusMiles
        )

        let key = cacheKey(for: request)

        if let cached = cache[key], Date().timeIntervalSince(cached.storedAt) < ttlSeconds {
            return cached.response
        }

        let response = try await backend.dispositionPartnersSearch(request: request)
        cache[key] = Cached(response: response, storedAt: Date())
        return response
    }

    // MARK: - Mapping (item)

    func buildSearchRequest(
        item: LTCItem,
        location: DispositionLocationDTO,
        radiusMiles: Int
    ) -> DispositionPartnersSearchRequest {

        let unitValue = max(item.valuation?.estimatedValue ?? item.value, 0)
        let qty = Double(max(item.quantity, 1))
        let totalValue = unitValue * qty

        let valueBand: DispositionValueBand = {
            if totalValue < 100 { return .LOW }
            if totalValue < 500 { return .MED }
            return .HIGH
        }()

        let bulky: Bool = {
            let cat = item.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["furniture", "appliance", "rug", "rugs", "electronics"].contains(cat)
        }()

        let chosenPath: DispositionChosenPath? = {
            guard let path = item.liquidationState?.activePlan?.chosenPath else { return nil }
            switch path {
            case .pathA: return .A
            case .pathB: return .B
            case .pathC: return .C
            case .donate: return .donate
            case .needsInfo: return .needsInfo
            }
        }()

        let constraints: [String]? = bulky ? ["pickup_required"] : nil

        let scenario = DispositionScenarioDTO(
            category: item.category,
            valueBand: valueBand,
            bulky: bulky,
            goal: .balanced,
            constraints: constraints
        )

        let keywords = extractKeywords(from: item)

        let hints = DispositionHintsDTO(
            keywords: keywords.isEmpty ? nil : keywords,
            notes: item.name
        )

        var loc = location
        loc.radiusMiles = radiusMiles

        return DispositionPartnersSearchRequest(
            schemaVersion: 1,
            scope: .item,
            chosenPath: chosenPath,
            scenario: scenario,
            location: loc,
            hints: hints
        )
    }

    // MARK: - Mapping (set)

    func buildSearchRequest(
        itemSet: LTCItemSet,
        block: SetPartnerBlock,
        chosenPath: DispositionChosenPath?,
        location: DispositionLocationDTO,
        radiusMiles: Int
    ) -> DispositionPartnersSearchRequest {

        let totalValue = estimateSetTotalValue(itemSet)

        let valueBand: DispositionValueBand = {
            if totalValue < 200 { return .LOW }
            if totalValue < 1000 { return .MED }
            return .HIGH
        }()

        // Closet lots are not bulky
        let bulky = false

        // Constraints + keywords tuned by execution block
        let constraints: [String]? = {
            switch block {
            case .luxury:
                // Used by backend matrix/prompt logic (string-based constraints are OK v1)
                return ["hub_mailin"]
            case .contemporary:
                // Often local consignment / resale channels
                return nil
            }
        }()

        let category: String = {
            switch itemSet.setType {
            case .closetLot:
                return "clothing"
            default:
                return itemSet.setType.rawValue
            }
        }()

        let scenario = DispositionScenarioDTO(
            category: category,
            valueBand: valueBand,
            bulky: bulky,
            goal: (block == .luxury) ? .maximizePrice : .balanced,
            constraints: constraints
        )

        let keywords = extractKeywords(from: itemSet, block: block)

        let notes = "Set: \(itemSet.name) • type: \(itemSet.setType.rawValue) • block: \(block.rawValue)"

        let hints = DispositionHintsDTO(
            keywords: keywords.isEmpty ? nil : keywords,
            notes: notes
        )

        var loc = location
        loc.radiusMiles = radiusMiles

        return DispositionPartnersSearchRequest(
            schemaVersion: 1,
            scope: .item, // TEMP: backend may not accept "set" yet; keep search working
            chosenPath: chosenPath,
            scenario: scenario,
            location: loc,
            hints: hints
        )
    }

    private func estimateSetTotalValue(_ itemSet: LTCItemSet) -> Double {
        // Best-effort v1: sum member item values * quantities (if present).
        // If items have no value, this will be 0 and map to LOW.
        var total: Double = 0
        for m in itemSet.memberships {
            guard let item = m.item else { continue }
            let qty = Double(max(m.quantityInSet ?? item.quantity, 1))
            total += max(item.value, 0) * qty
        }
        return total
    }

    private func extractKeywords(from itemSet: LTCItemSet, block: SetPartnerBlock) -> [String] {
        var out: [String] = []

        // Set type cue
        out.append(itemSet.setType.rawValue)

        // Block cues
        switch block {
        case .luxury:
            out.append(contentsOf: [
                "luxury consignment",
                "designer resale",
                "authenticated designer",
                "mail-in luxury consignment"
            ])
        case .contemporary:
            out.append(contentsOf: [
                "consignment",
                "resale",
                "women's clothing consignment",
                "clothing resale"
            ])
        }

        // Set name tokens (light heuristic)
        let name = itemSet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            let first = name.split(separator: " ").first.map(String.init) ?? ""
            if first.count >= 3 { out.append(first) }
        }

        return Array(Set(out)).sorted()
    }

    private func extractKeywords(from item: LTCItem) -> [String] {
        // v1 heuristic: pull capitalized “brand-like” token from name if present
        // and also include the category.
        var out: [String] = []

        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            // first word often brand (Thomasville Dining Chair)
            let first = name.split(separator: " ").first.map(String.init) ?? ""
            if first.count >= 3 { out.append(first) }
        }

        let cat = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cat.isEmpty { out.append(cat) }

        // de-dupe
        return Array(Set(out)).sorted()
    }

    // MARK: - Cache key

    private func cacheKey(for req: DispositionPartnersSearchRequest) -> String {
        // Stable-enough for v1: encode then hash
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(req)) ?? Data()
        return String(data: data, encoding: .utf8) ?? UUID().uuidString
    }
}
