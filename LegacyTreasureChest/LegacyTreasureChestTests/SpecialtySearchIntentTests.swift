//
//  SpecialtySearchIntentTests.swift
//  LegacyTreasureChestTests
//
//  B1: Search Intent suggestions (strategy from the saved Plan, wording from the
//  Brief's specialty block or safe fallbacks), validation that mirrors the
//  Gateway, minimal requests, external search links and prompts, and decoding
//  of the extended provider results.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

private let leicaSpecialty = LiquidationSpecialtyDTO(
    itemKind: "vintage film camera",
    detailTerms: ["rangefinder", "Summicron 50mm", "chrome"],
    brand: "Leica", model: "M3", isSpecialistItem: true
)

// MARK: - Suggestions

@MainActor
struct SearchIntentSuggestionTests {

    @Test func strategyFollowsTheChosenApproach() {
        #expect(DispositionSearchStrategy(path: .pathA_maximizePrice) == .maximizePrice)
        #expect(DispositionSearchStrategy(path: .pathB_delegateConsign) == .consignment)
        #expect(DispositionSearchStrategy(path: .pathC_quickExit) == .quickSale)
        #expect(DispositionSearchStrategy(path: .donate) == .donation)
        #expect(DispositionSearchStrategy(path: .needsInfo) == nil)
        #expect(SearchIntentBuilder.suggest(approach: .needsInfo, specialty: nil, itemName: "x", category: "Art") == nil)
    }

    @Test func specialtyBlockGivesTheWordingAndDetails() throws {
        let s = try #require(SearchIntentBuilder.suggest(
            approach: .pathB_delegateConsign, specialty: leicaSpecialty,
            itemName: "Grandpa Joe's Leica M3", category: "Electronics"))
        #expect(s.strategy == .consignment)
        #expect(s.phrase == "vintage film camera")
        #expect(s.detailTerms == ["Leica", "M3", "rangefinder", "Summicron 50mm"])
        #expect(s.geoScope == .local)
        #expect(s.phraseSource == .specialty)

        let quick = try #require(SearchIntentBuilder.suggest(
            approach: .pathC_quickExit, specialty: leicaSpecialty, itemName: "x", category: "Electronics"))
        #expect(quick.strategy == .quickSale)
        #expect(quick.phrase == s.phrase)
    }

    @Test func briefsWithoutSpecialtyStillProduceUsefulWording() throws {
        func phrase(_ name: String, _ category: String) -> String? {
            SearchIntentBuilder.suggest(approach: .pathB_delegateConsign, specialty: nil,
                                        itemName: name, category: category)?.phrase
        }
        #expect(phrase("Oak dining table and six chairs", "Furniture") == "furniture")
        #expect(phrase("Oil landscape painting", "Art") == "art")
        #expect(phrase("Grandma Ruth's Leica M3 camera with 50mm lens", "Electronics") == "Leica M3 camera")
        #expect(phrase("Mom's sewing machine", "Other") == "sewing machine")
        #expect(phrase("Commercial embroidery machine (Brother PR1050X)", "Uncategorized") == "Commercial embroidery machine")
        #expect(phrase("Stereo receiver SN 123456789 call jane@example.com", "Electronics") == "Stereo receiver SN call")
        #expect(phrase("", "Other") == "household items")
        #expect(SearchIntentBuilder.suggest(approach: .donate, specialty: nil, itemName: "", category: "Other")?
            .phraseSource == .fallback)
    }

    @Test func setsAndClosetLotPiles() throws {
        func set(_ type: SetType, pile: String? = nil, approach: LiquidationPathDTO = .pathB_delegateConsign,
                 specialty: LiquidationSpecialtyDTO? = nil) -> SearchIntentSuggestion? {
            SearchIntentBuilder.suggest(approach: approach, specialty: specialty, setName: "Mom's things",
                                        setType: type, pile: pile)
        }
        let luxury = try #require(set(.closetLot, pile: "luxury"))
        #expect((luxury.phrase, luxury.strategy, luxury.geoScope) == ("designer clothing", .consignment, .national))
        let contemporary = try #require(set(.closetLot, pile: "contemporary"))
        #expect((contemporary.phrase, contemporary.geoScope) == ("clothing", .local))
        let donate = try #require(set(.closetLot, pile: "donate"))
        #expect((donate.phrase, donate.strategy) == ("clothing", .donation))
        let discard = try #require(set(.closetLot, pile: "discard"))
        #expect((discard.phrase, discard.strategy) == ("textile recycling", .donation))
        #expect(set(.china)?.phrase == "china dinnerware")
        #expect(set(.china, specialty: LiquidationSpecialtyDTO(itemKind: "Noritake china", brand: "Noritake"))?.phrase
                == "Noritake china")
        #expect(set(.other)?.phrase == "things")  // "Mom's" removed
    }

    @Test func findHelpRequestUsesTheSavedPlanNotTheRecommendation() async throws {
        let container = try ModelContainer(for: LTCItem.self, LTCItemSet.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let item = LTCItem(name: "Leica M3", itemDescription: "Private notes about Grandpa.", category: "Electronics", value: 1800)
        context.insert(item)
        let brief = LiquidationBriefDTO(
            scope: .item, recommendedPath: .pathB_delegateConsign, reasoning: "r",
            pathOptions: [.init(path: .pathC_quickExit, label: "Sell to a local shop", effort: .low)],
            actionSteps: [], specialty: leicaSpecialty)
        let briefRecord = try LiquidationWorkflow.recordNewBrief(brief, owner: .item(item), context: context)
        let plan = try await LiquidationWorkflow.createPlan(
            owner: .item(item), chosen: .pathC, briefRecord: briefRecord, brief: brief, context: context
        ) { LiquidationPlanChecklistDTO(schemaVersion: 2, items: [.init(order: 1, text: "Find a buyer", action: "findSpecialtyHelp")]) }
        let step = try #require(LiquidationWorkflow.checklist(of: plan)?.items.first)

        let request = LiquidationWorkflow.findHelpRequest(plan: plan, step: step, action: .findSpecialtyHelp)
        let s = try #require(SearchIntentBuilder.suggestion(for: request, owner: .item(item)))
        #expect(s.strategy == .quickSale)          // the homeowner's choice, not the Brief's Consignment
        #expect(s.phrase == "vintage film camera")
        #expect(s.detailTerms.contains("Leica"))

        let intent = try s.intent()
        #expect(intent.valueBand == nil)
        let body = String(decoding: try JSONEncoder().encode(intent), as: UTF8.self)
        #expect(!body.contains("Grandpa") && !body.contains("1800") && !body.contains("Private"))
    }
}

// MARK: - Validation and requests

struct SearchIntentValidationTests {

    private func intent(_ phrase: String, terms: [String] = [], strategy: String = "consignment",
                        scope: String = "local") -> DispositionSearchIntentDTO {
        DispositionSearchIntentDTO(strategy: strategy, phrase: phrase, detailTerms: terms, geoScope: scope)
    }

    @Test func rejectsWhatTheGatewayRejects() {
        let bad: [(String, SearchIntentValidator.ValidationError)] = [
            ("   ", .empty),
            (String(repeating: "x", count: 61), .tooLong),
            ("one two three four five six seven eight nine", .tooManyWords),
            ("email jane@example.com", .containsContactOrWebAddress),
            ("see www.example.com", .containsContactOrWebAddress),
            ("call 208-555-1234", .containsLongNumber),
            ("serial 123456789", .containsLongNumber),
            ("camera <script>", .unsupportedCharacters),
        ]
        for (phrase, expected) in bad {
            #expect(throws: expected) { try SearchIntentValidator.validated(intent(phrase)) }
        }
        #expect(throws: SearchIntentValidator.ValidationError.tooManyDetailTerms) {
            try SearchIntentValidator.validated(intent("camera", terms: ["a", "b", "c", "d", "e"]))
        }
        #expect(throws: SearchIntentValidator.ValidationError.unknownStrategy) {
            try SearchIntentValidator.validated(intent("camera", strategy: "needsInfo"))
        }
        #expect(throws: SearchIntentValidator.ValidationError.unknownScope) {
            try SearchIntentValidator.validated(intent("camera", scope: "worldwide"))
        }
    }

    @Test func acceptsOrdinaryWordingAndCleansIt() throws {
        for phrase in ["Leica M3 rangefinder", "women's clothing", "1978 guitar", "50mm f/2 lens", "arts & crafts lamp"] {
            #expect(try SearchIntentValidator.validated(intent(phrase)).phrase == phrase)
        }
        let v = try SearchIntentValidator.validated(intent("  film   camera ", terms: ["Leica", "leica", "M3"]))
        #expect(v.phrase == "film camera")
        #expect(v.detailTerms == ["Leica", "M3"])
    }

    @Test func intentRequestsCarryOnlyTheIntentAndLocation() throws {
        let loc = DispositionLocationDTO(city: "Boise", region: "ID", countryCode: "US", radiusMiles: 25,
                                         latitude: 43.6, longitude: -116.2)
        let req = try DispositionAIService.buildIntentRequest(intent: intent("film camera", terms: ["Leica"]), location: loc)
        #expect(req.searchIntent?.phrase == "film camera")
        #expect(req.hints == nil)
        #expect(req.chosenPath == nil)
        #expect(req.scenario.valueBand == .UNKNOWN)
        #expect(req.scenario.category == "")

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any]
        #expect(json?["hints"] == nil)
        #expect((json?["searchIntent"] as? [String: Any])?["valueBand"] == nil)

        var opted = intent("film camera")
        opted.valueBand = "HIGH"
        #expect(try DispositionAIService.buildIntentRequest(intent: opted, location: loc).scenario.valueBand == .HIGH)
        #expect(throws: SearchIntentValidator.ValidationError.containsLongNumber) {
            try DispositionAIService.buildIntentRequest(intent: intent("call 2085551234"), location: loc)
        }
    }
}

// MARK: - External search

struct ExternalSearchLinkTests {

    private func intent(_ strategy: DispositionSearchStrategy, _ scope: DispositionGeoScope,
                        phrase: String = "film camera", terms: [String] = []) -> DispositionSearchIntentDTO {
        DispositionSearchIntentDTO(strategy: strategy.rawValue, phrase: phrase, detailTerms: terms, geoScope: scope.rawValue)
    }

    @Test func queriesFollowStrategyAndScope() {
        #expect(ExternalSearchLinks.webSearchQuery(for: intent(.consignment, .local), city: "Boise", region: "ID")
                == "film camera consignment near Boise, ID")
        #expect(ExternalSearchLinks.webSearchQuery(for: intent(.maximizePrice, .regional, phrase: "vintage guitar"),
                                                   region: "Colorado")
                == "sell vintage guitar specialist dealer in Colorado")
        #expect(ExternalSearchLinks.webSearchQuery(for: intent(.consignment, .national, phrase: "designer handbag"))
                == "designer handbag consignment mail-in nationwide")
        #expect(ExternalSearchLinks.webSearchQuery(for: intent(.donation, .national, phrase: "kitchenware"))
                == "donate kitchenware")
        #expect(ExternalSearchLinks.webSearchQuery(for: intent(.quickSale, .local)) == "sell film camera buyer")
    }

    @Test func urlsAreEncodedAndRoundTrip() throws {
        let i = intent(.consignment, .local, phrase: "arts & crafts lamp + shade")
        let url = try #require(ExternalSearchLinks.webSearchURL(for: i, city: "Coeur d'Alene", region: "ID"))
        #expect(url.scheme == "https")
        #expect(url.host == "www.google.com")
        #expect(url.path == "/search")
        #expect(!url.absoluteString.contains(" "))
        #expect(url.absoluteString.contains("%26"))  // "&" never splits the query
        #expect(url.absoluteString.contains("%2B"))  // "+" never reads as a space
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value
        #expect(q == "arts & crafts lamp + shade consignment near Coeur d'Alene, ID")
    }

    @Test func promptIsSpecificButPrivate() {
        let p = ExternalSearchLinks.discoveryPrompt(for: intent(.consignment, .national, terms: ["Leica", "M3"]))
        #expect(p.contains("consign my film camera (Leica, M3)"))
        #expect(p.contains("anywhere in the United States"))
        #expect(p.contains("link to each one's own website"))
        #expect(p.contains("confirm they accept my item"))
        #expect(!p.contains("$"))
        let donation = ExternalSearchLinks.discoveryPrompt(for: intent(.donation, .local, phrase: "kitchenware"),
                                                           city: "Boise", region: "ID")
        #expect(donation.contains("donate my kitchenware to an organization that accepts it, near Boise, ID"))
        #expect(donation.contains("donation receipt"))
    }
}

// MARK: - Provider results

struct ProviderResultDecodingTests {

    @Test func intentResultsDecodeAndLegacyResultsStillDo() throws {
        let json = """
        {"schemaVersion": 1, "generatedAt": "2026-10-16T12:00:00.123456Z", "scenarioId": "intent.consignment.local",
         "partnerTypes": ["business"], "disclaimer": "d", "localDiscoveryStatus": "ok",
         "searchScope": "local", "directoryStatus": "not_applicable",
         "results": [
          {"partnerId": "gplaces:abc", "name": "Boise Camera & Video", "partnerType": "business",
           "contact": {"phone": "(208) 555-1234", "website": null, "address": "1 Main St, Boise, ID"},
           "distanceMiles": 1.2, "rating": 4.7, "userRatingsTotal": 80,
           "trust": {"trustScore": 0.8, "claimLevel": "listing", "gates": [], "signals": []},
           "ranking": {"score": 0.8, "reasons": ["Listing mentions camera"]},
           "whyRecommended": "Listing mentions camera. Confirm they accept your item.", "questionsToAsk": [],
           "source": "google_places", "placeId": "abc", "googleMapsUri": "https://maps.google.com/?cid=abc",
           "serviceEvidence": {"consignment": "not_mentioned", "buysOutright": "not_mentioned"},
           "evidenceSource": "google_places_name_and_type",
           "relevance": {"level": "specialist", "matchedTerms": ["camera"]},
           "geoScope": "local", "areaMatch": "in_area", "acceptanceStatus": "unknown", "attribution": "google_maps"},
          {"partnerId": "directory:keh", "name": "KEH Camera", "partnerType": "buyer",
           "contact": {"website": "https://www.keh.com/"}, "source": "ltc_directory", "directoryId": "directory:keh",
           "serviceEvidence": {"buysOutright": "offered"}, "serviceArea": "Nationwide (mail-in), US",
           "intakeModel": "mail_in", "verifiedAt": "2026-10-16", "acceptanceStatus": "unknown"}
         ]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? Date()
        }
        let r = try decoder.decode(DispositionPartnersSearchResponse.self, from: Data(json.utf8))
        #expect(r.searchScope == "local")
        #expect(r.hasGooglePlacesResults)
        let place = r.results[0]
        #expect(place.placeId == "abc")
        #expect(place.googleMapsUri == "https://maps.google.com/?cid=abc")
        #expect(place.contact.website == nil)
        #expect(place.serviceEvidence?["consignment"] == "not_mentioned")
        #expect(place.relevance == DispositionRelevance(level: "specialist", matchedTerms: ["camera"]))
        #expect(place.acceptanceStatus == "unknown")
        #expect(r.results[1].verifiedAt == "2026-10-16")

        let legacy = """
        {"schemaVersion": 1, "generatedAt": "2026-10-16T12:00:00Z", "partnerTypes": [], "results": [
          {"partnerId": "gplaces:x", "name": "Shop", "partnerType": "consignment", "contact": {}}]}
        """
        let old = try decoder.decode(DispositionPartnersSearchResponse.self, from: Data(legacy.utf8))
        #expect(old.results[0].source == nil && old.searchScope == nil)
    }
}
