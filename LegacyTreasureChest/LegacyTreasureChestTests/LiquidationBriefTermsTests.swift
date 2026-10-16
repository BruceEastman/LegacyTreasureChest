//
//  LiquidationBriefTermsTests.swift
//  LegacyTreasureChestTests
//
//  A1: customer-facing approach names, legacy Brief compatibility, the optional
//  specialty block, offline fallback labels, and the shared Brief presentation.
//

import Foundation
import Testing
@testable import LegacyTreasureChest

// MARK: - Fixtures

/// A Brief exactly as app 1.2 stored it from the offline fallback: no specialty,
/// "Path A — …" labels, and an identifier in the reasoning.
private let legacyStoredBriefJSON = """
{
  "schemaVersion": 1,
  "scope": "item",
  "generatedAt": "2026-09-01T12:00:00Z",
  "aiProvider": "local",
  "aiModel": "heuristic-min",
  "recommendedPath": "pathB_delegateConsign",
  "reasoning": "pathB_delegateConsign suits this better than Path A.",
  "pathOptions": [
    {"id": "11111111-1111-1111-1111-111111111111", "path": "pathA_maximizePrice",
     "label": "Path A — Maximize Price", "effort": "high", "timeEstimate": "1–4 weeks",
     "risks": ["Returns"], "logisticsNotes": "More work, potentially higher net.",
     "netProceeds": {"currencyCode": "USD", "low": 700, "likely": 900, "high": 1100}},
    {"id": "22222222-2222-2222-2222-222222222222", "path": "pathB_delegateConsign",
     "label": "Path B — Luxury Mail-in Hub", "effort": "low", "risks": ["Commission"],
     "netProceeds": {"currencyCode": "USD", "low": 600, "likely": 750, "high": 900}},
    {"id": "33333333-3333-3333-3333-333333333333", "path": "pathC_quickExit",
     "label": "Path C — Quick Exit", "effort": "medium", "risks": []}
  ],
  "actionSteps": ["Confirm details."],
  "missingDetails": ["Serial number"],
  "assumptions": ["Local fallback used"],
  "confidence": 0.6
}
"""

/// A Brief as the A1 Gateway returns it (fractional-second date, specialty block).
private let gatewayBriefJSON = """
{
  "schemaVersion": 1,
  "scope": "item",
  "generatedAt": "2026-10-16T18:04:05.123456Z",
  "aiProvider": "gemini",
  "aiModel": "gemini-2.5-flash",
  "recommendedPath": "pathB_delegateConsign",
  "reasoning": "Camera specialists reach collectors who pay more.",
  "pathOptions": [
    {"id": "11111111-1111-1111-1111-111111111111", "path": "pathA_maximizePrice",
     "label": "Sell online yourself", "effort": "high", "risks": []},
    {"id": "22222222-2222-2222-2222-222222222222", "path": "pathB_delegateConsign",
     "label": "Specialist camera consignment", "effort": "medium", "risks": ["Commission"]}
  ],
  "actionSteps": [],
  "missingDetails": [],
  "assumptions": [],
  "inputs": {"goal": "balanced"},
  "specialty": {"itemKind": "film camera", "detailTerms": ["rangefinder", "50mm lens"],
                "brand": "Leica", "model": "M3", "isSpecialistItem": true}
}
"""

private func briefJSON(replacingSpecialtyWith specialty: String) -> String {
    let start = gatewayBriefJSON.range(of: "\"specialty\":")!.lowerBound
    return String(gatewayBriefJSON[..<start]) + "\"specialty\": \(specialty)\n}"
}

/// Decodes a Gateway response the way BackendAIProvider does (ISO 8601, with or without fractions).
private func decodeGatewayBrief(_ json: String) throws -> LiquidationBriefDTO {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { dec in
        let s = try dec.singleValueContainer().decode(String.self)
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: s) { return d }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: s))
    }
    return try decoder.decode(LiquidationBriefDTO.self, from: Data(json.utf8))
}

private func containsInternalIdentifier(_ s: String) -> Bool {
    s.range(of: #"[Pp]ath ?[ABC]\b|[Pp]ath[ABC]_|needsInfo|delegateConsign|quickExit|maximizePrice"#,
            options: .regularExpression) != nil
}

private func makeBrief(recommended: LiquidationPathDTO, scope: LiquidationScopeDTO = .item) -> LiquidationBriefDTO {
    LiquidationBriefDTO(
        scope: scope,
        recommendedPath: recommended,
        reasoning: "Reasoning.",
        pathOptions: [
            .init(path: .pathA_maximizePrice, label: "Sell it yourself online", effort: .high),
            .init(path: .pathB_delegateConsign, label: "Specialist camera consignment", effort: .medium),
            .init(path: .pathC_quickExit, label: "Quick Sale", effort: .low),
            .init(path: .donate, label: "Donate locally", effort: .low),
        ],
        actionSteps: []
    )
}

// MARK: - Terminology

struct LiquidationApproachNameTests {

    @Test func everyBriefPathHasTheApprovedName() {
        let expected: [LiquidationPathDTO: String] = [
            .pathA_maximizePrice: "Maximize Price",
            .pathB_delegateConsign: "Consignment",
            .pathC_quickExit: "Quick Sale",
            .donate: "Donation",
            .needsInfo: "More Information Needed",
        ]
        for (path, name) in expected {
            #expect(path.displayName == name)
            #expect(UserFacingTerms.Liquidation.approachName(path) == name)
        }
    }

    @Test func persistedPathsUseTheSameNamesAndRoundTrip() {
        for path in LiquidationPath.allCases {
            #expect(path.displayName == path.briefPath.displayName)
            #expect(path.briefPath.appPath == path)
            #expect(!containsInternalIdentifier(path.displayName))
            #expect(path.displayName != path.rawValue)
        }
        // Persisted raw values are unchanged.
        #expect(LiquidationPath.pathB.rawValue == "PathB_DelegateConsign")
        #expect(LiquidationPathDTO.pathB_delegateConsign.rawValue == "pathB_delegateConsign")
    }

    @Test func planTitlesAndStatusesReadAsWords() {
        #expect(UserFacingTerms.Liquidation.planTitle(.pathB) == "Consignment Plan")
        #expect(UserFacingTerms.Liquidation.planTitle(.donate) == "Donation Plan")
        #expect(UserFacingTerms.Liquidation.planTitle(.needsInfo) == "Plan")
        for status in LiquidationStatus.allCases {
            #expect(UserFacingTerms.Liquidation.statusName(status) != status.rawValue || status == .completed)
        }
        #expect(UserFacingTerms.Liquidation.statusName(LiquidationStatus.hasBrief) == "Brief ready")
        #expect(UserFacingTerms.Liquidation.statusName(PlanStatus.inProgress) == "In progress")
    }

    @Test func customerTextReplacesIdentifiersButNotProse() {
        let t = UserFacingTerms.Liquidation.self
        #expect(t.customerText("pathB_delegateConsign beats PathA_MaximizePrice") == "Consignment beats Maximize Price")
        #expect(t.customerText("Path C is fastest; needsInfo otherwise.") == "Quick Sale is fastest; More Information Needed otherwise.")
        #expect(t.customerText("There is a path a buyer could take.") == "There is a path a buyer could take.")
        #expect(t.customerLabel("Path B — Luxury Mail-in Hub") == "Luxury Mail-in Hub")
    }
}

// MARK: - Legacy and Gateway Briefs

struct LiquidationBriefCompatibilityTests {

    @Test func legacyStoredBriefDecodesAndPresentsWithoutIdentifiers() throws {
        let dto = try #require(LiquidationJSONCoding.tryDecode(
            LiquidationBriefDTO.self, from: Data(legacyStoredBriefJSON.utf8)))
        #expect(dto.specialty == nil)

        let p = LiquidationBriefPresentation(dto: dto)
        #expect(p.headline == "Recommended: Consignment")
        #expect(p.specificRecommendation == "Luxury Mail-in Hub")
        #expect(p.reasoning == "Consignment suits this better than Maximize Price.")
        #expect(p.options.map(\.path) == [.pathB_delegateConsign, .pathA_maximizePrice, .pathC_quickExit])
        // "Path A — Maximize Price" only repeats the approach name.
        #expect(p.options[1].specificRecommendation == nil)

        let visible = [p.headline, p.reasoning] + p.missingDetails
            + p.options.flatMap { [$0.name, $0.specificRecommendation ?? "", $0.notes ?? ""] + $0.risks }
        for s in visible { #expect(!containsInternalIdentifier(s), "\(s)") }
    }

    @Test func gatewaySpecialtySurvivesDecodeAndLocalRoundTrip() throws {
        let dto = try decodeGatewayBrief(gatewayBriefJSON)
        let expected = LiquidationSpecialtyDTO(itemKind: "film camera", detailTerms: ["rangefinder", "50mm lens"],
                                               brand: "Leica", model: "M3", isSpecialistItem: true)
        #expect(dto.specialty == expected)

        // Stored in SwiftData via LiquidationJSONCoding, then read back.
        let stored = try LiquidationJSONCoding.encode(dto)
        let reread = try #require(LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: stored))
        #expect(reread.specialty == expected)
    }

    @Test func missingOrNullSpecialtyIsNil() throws {
        #expect(try decodeGatewayBrief(briefJSON(replacingSpecialtyWith: "null")).specialty == nil)
        let legacy = try #require(LiquidationJSONCoding.tryDecode(
            LiquidationBriefDTO.self, from: Data(legacyStoredBriefJSON.utf8)))
        #expect(legacy.specialty == nil)
    }

    @Test func malformedSpecialtyNeverMakesTheBriefUnreadable() throws {
        for bad in [#""film camera""#, "[1, 2]", "42",
                    #"{"itemKind": 7, "detailTerms": "rangefinder", "isSpecialistItem": "yes"}"#] {
            let dto = try decodeGatewayBrief(briefJSON(replacingSpecialtyWith: bad))
            #expect(dto.recommendedPath == .pathB_delegateConsign)
            #expect(dto.specialty?.isEmpty ?? true)
            #expect((dto.specialty?.isSpecialistItem ?? false) == false)
        }
    }
}

// MARK: - Offline fallback labels

struct LiquidationFallbackLabelTests {

    @Test func offlineBriefUsesApprovedNames() {
        let req = LiquidationBriefRequest(scope: .item, title: "Mantel clock", category: "Decor",
                                          quantity: 1, unitValue: 400)
        let dto = LocalLiquidationBriefGenerator().generate(from: req)
        let labels = Dictionary(uniqueKeysWithValues: dto.pathOptions.map { ($0.path, $0.label) })
        #expect(labels[.pathA_maximizePrice] == "Maximize Price")
        #expect(labels[.pathB_delegateConsign] == "Consignment")
        #expect(labels[.pathC_quickExit] == "Quick Sale")
        for opt in dto.pathOptions { #expect(!containsInternalIdentifier(opt.label)) }
        #expect(!containsInternalIdentifier(dto.reasoning))
    }

    @Test func offlineBriefWithoutValueAsksForMoreInformation() {
        let req = LiquidationBriefRequest(scope: .item, title: "Figurine", category: "Decor", quantity: 1)
        let dto = LocalLiquidationBriefGenerator().generate(from: req)
        let p = LiquidationBriefPresentation(dto: dto)
        #expect(p.needsMoreInformation)
        #expect(p.headline == "More Information Needed")
        #expect(!p.missingDetails.isEmpty)
        #expect(!containsInternalIdentifier(p.reasoning))
    }
}

// MARK: - Presentation

struct LiquidationBriefPresentationTests {

    @Test func recommendationMatchesItsOptionAndIsFirst() {
        for rec in [LiquidationPathDTO.pathA_maximizePrice, .pathB_delegateConsign, .pathC_quickExit, .donate] {
            let p = LiquidationBriefPresentation(dto: makeBrief(recommended: rec))
            #expect(p.options.first?.path == rec)
            #expect(p.recommendedOption?.path == rec)
            #expect(p.options.filter(\.isRecommended).count == 1)
            #expect(p.headline == "Recommended: \(rec.displayName)")
        }
        let consign = LiquidationBriefPresentation(dto: makeBrief(recommended: .pathB_delegateConsign))
        #expect(consign.specificRecommendation == "Specialist camera consignment")
        #expect(consign.options.map(\.path) == [.pathB_delegateConsign, .pathA_maximizePrice, .pathC_quickExit, .donate])
        // A label equal to the approach name is not repeated.
        #expect(consign.options.first(where: { $0.path == .pathC_quickExit })?.specificRecommendation == nil)
    }

    @Test func homeownerCanChooseAnyApproachWithRecommendationFirst() {
        #expect(LiquidationBriefPresentation.selectableApproaches(recommended: .pathC_quickExit)
                == [.pathC, .pathA, .pathB, .donate])
        // More Information Needed is not an approach; all four stay available.
        #expect(LiquidationBriefPresentation.selectableApproaches(recommended: .needsInfo)
                == [.pathA, .pathB, .pathC, .donate])
    }

    @Test func itemAndSetBriefsPresentIdentically() {
        let item = LiquidationBriefPresentation(dto: makeBrief(recommended: .pathB_delegateConsign, scope: .item))
        let set = LiquidationBriefPresentation(dto: makeBrief(recommended: .pathB_delegateConsign, scope: .set))
        #expect(item.headline == set.headline)
        #expect(item.specificRecommendation == set.specificRecommendation)
        #expect(item.options.map(\.path) == set.options.map(\.path))
        #expect(item.options.map(\.name) == set.options.map(\.name))
    }

    @Test func estimatesAreShownOnlyWhenTheBriefHasThem() {
        #expect(LiquidationBriefPresentation.estimatedNet(nil) == nil)
        #expect(LiquidationBriefPresentation.estimatedNet(MoneyRangeDTO()) == nil)
        #expect(LiquidationBriefPresentation.estimatedNet(MoneyRangeDTO(likely: 500)) == "About \(CurrencyFormat.dollars(500))")
        #expect(LiquidationBriefPresentation.estimatedNet(MoneyRangeDTO(low: 400, likely: 500, high: 600))
                == CurrencyFormat.dollarsRange(low: 400, high: 600))
    }
}
