//
//  DispositionDTOs.swift
//  LegacyTreasureChest
//
//  DTOs for Disposition Engine v1 endpoints.
//  Matches backend schemaVersion = 1.
//

import Foundation

// MARK: - Request

struct DispositionPartnersSearchRequest: Codable {
    var schemaVersion: Int = 1
    var scope: DispositionScope = .item
    var chosenPath: DispositionChosenPath?
    var scenario: DispositionScenarioDTO
    var location: DispositionLocationDTO
    var hints: DispositionHintsDTO?
    /// B1: a homeowner-reviewed specialty search. When present the Gateway uses
    /// intent-based discovery; app 1.2 never sends it.
    var searchIntent: DispositionSearchIntentDTO? = nil
}

/// What a specialty search looks for. Built by SearchIntentBuilder, shown to the
/// homeowner for review (B2), and sent only after that review.
struct DispositionSearchIntentDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    /// maximizePrice | consignment | quickSale | donation (DispositionSearchStrategy)
    var strategy: String
    /// Short, item-specific wording, e.g. "film camera".
    var phrase: String
    /// Optional identifying terms, e.g. brand and model (used for ranking).
    var detailTerms: [String] = []
    /// local | regional | national (DispositionGeoScope)
    var geoScope: String
    /// LOW | MED | HIGH, only when the homeowner opts in. Omitted by default.
    var valueBand: String? = nil
}

enum DispositionScope: String, Codable {
    case item
    case set
    case batch
}

enum DispositionChosenPath: String, Codable {
    case A
    case B
    case C
    case donate
    case needsInfo
}

struct DispositionScenarioDTO: Codable {
    var category: String
    var valueBand: DispositionValueBand
    var bulky: Bool
    var goal: DispositionGoal
    var constraints: [String]?
}

enum DispositionValueBand: String, Codable {
    case LOW
    case MED
    case HIGH
    /// No value estimate exists; must not be treated as a known low value.
    case UNKNOWN
}

enum DispositionGoal: String, Codable {
    case balanced
    case maximizePrice
    case speed
    case minimizeWork
}

struct DispositionLocationDTO: Codable {
    var city: String
    var region: String
    var countryCode: String
    var radiusMiles: Int
    var latitude: Double?
    var longitude: Double?
}

struct DispositionHintsDTO: Codable {
    var keywords: [String]?
    var notes: String?
}

// MARK: - Response

struct DispositionPartnersSearchResponse: Codable {
    var schemaVersion: Int
    var generatedAt: Date
    var scenarioId: String?
    var partnerTypes: [String]
    var results: [DispositionPartnerResult]

    // Optional so older/curated responses still decode.
    var disclaimer: String? = nil
    /// ok | no_results | unavailable | disabled | limited | not_applicable
    var localDiscoveryStatus: String? = nil
    /// User-facing explanation when local results are missing for a reason.
    var notice: String? = nil
    /// B1 (intent searches): local | regional | national
    var searchScope: String? = nil
    /// B1 (intent searches): ok | no_match | not_applicable
    var directoryStatus: String? = nil

    /// True when any result came from Google Places (attribution required).
    var hasGooglePlacesResults: Bool {
        results.contains { $0.partnerId.hasPrefix("gplaces:") }
    }
}

struct DispositionPartnerResult: Codable, Identifiable {
    var partnerId: String
    var name: String
    var partnerType: String
    var contact: DispositionPartnerContact
    var distanceMiles: Double?
    var rating: Double?
    var userRatingsTotal: Int?
    var trust: DispositionTrust?
    var ranking: DispositionRanking?
    var whyRecommended: String?
    var questionsToAsk: [String]?

    // B1 (optional; intent searches only)

    /// google_places | ltc_directory
    var source: String? = nil
    /// Google place ID (the only Places field that may be stored).
    var placeId: String? = nil
    var directoryId: String? = nil
    /// The Google Maps listing, distinct from the business's own website.
    var googleMapsUri: String? = nil
    /// What the listing or directory says the business does, e.g.
    /// ["consignment": "mentioned"]. Never proof it accepts a particular item.
    var serviceEvidence: [String: String]? = nil
    var evidenceSource: String? = nil
    var relevance: DispositionRelevance? = nil
    var geoScope: String? = nil
    /// in_area | outside_area | unknown
    var areaMatch: String? = nil
    var serviceArea: String? = nil
    var intakeModel: String? = nil
    /// Directory entries: date last checked (yyyy-MM-dd).
    var verifiedAt: String? = nil
    /// Always "unknown": only the business can confirm it accepts an item.
    var acceptanceStatus: String? = nil
    /// "google_maps" when the data comes from Google Places.
    var attribution: String? = nil

    var id: String { partnerId }
}

struct DispositionRelevance: Codable, Equatable {
    /// specialist | general
    var level: String
    var matchedTerms: [String]
}

struct DispositionPartnerContact: Codable {
    var phone: String?
    var website: String?
    var email: String?
    var address: String?
    var city: String?
    var region: String?
}

struct DispositionTrust: Codable {
    var trustScore: Double?
    var claimLevel: String?
    var gates: [DispositionTrustGate]?
    var signals: [DispositionTrustSignal]?
}

struct DispositionTrustGate: Codable, Identifiable {
    var id: String
    var mode: String
    var status: String
    var source: String?
    var strength: Double?

    var gateId: String { id } // keep unique id accessible if needed
}

struct DispositionTrustSignal: Codable, Hashable {
    var type: String?
    var label: String?
    var source: String?
}

struct DispositionRanking: Codable {
    var score: Double?
    var reasons: [String]?
}
