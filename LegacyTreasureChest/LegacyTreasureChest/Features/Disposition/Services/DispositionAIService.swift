//
//  DispositionAIService.swift
//  LegacyTreasureChest
//
//  Builds Disposition Engine requests from item context and calls the backend.
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

    // MARK: - Mapping

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
