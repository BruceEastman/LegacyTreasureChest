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

    var id: String { partnerId }
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
