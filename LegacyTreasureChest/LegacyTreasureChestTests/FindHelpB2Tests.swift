//
//  FindHelpB2Tests.swift
//  LegacyTreasureChestTests
//
//  B2: the shared Find Help screen's rules (FindHelpModel), provider choices
//  saved in the Plan, earlier Set pile choices, the outcome suggestion, and
//  honest failure messages.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

// MARK: - Fixtures

@MainActor
private final class SearchRecorder {
    var calls: [(DispositionSearchIntentDTO, DispositionLocationDTO)] = []
    var result: Result<DispositionPartnersSearchResponse, Error> = .success(response())

    var searcher: FindHelpModel.Searcher {
        { [unowned self] intent, location in
            self.calls.append((intent, location))
            return try self.result.get()
        }
    }
}

@MainActor
private func response(results: [DispositionPartnerResult] = [], local: String = "ok",
                      directory: String = "not_applicable", scope: String = "local") -> DispositionPartnersSearchResponse {
    DispositionPartnersSearchResponse(
        schemaVersion: 1, generatedAt: .now, scenarioId: "intent", partnerTypes: [], results: results,
        disclaimer: nil, localDiscoveryStatus: local, notice: nil, searchScope: scope, directoryStatus: directory)
}

@MainActor
private func googleResult(_ placeId: String = "ChIJabcdefghij123", website: String? = "https://shop.example") -> DispositionPartnerResult {
    DispositionPartnerResult(
        partnerId: "gplaces:\(placeId)", name: "Boise Camera & Video", partnerType: "business",
        contact: DispositionPartnerContact(phone: "(208) 555-0100", website: website, email: nil,
                                           address: "1 Main St, Boise, ID", city: nil, region: nil),
        distanceMiles: 1.2, rating: 4.7, userRatingsTotal: 80, trust: nil, ranking: nil,
        whyRecommended: nil, questionsToAsk: ["Do you take cameras on consignment?"],
        source: "google_places", placeId: placeId, googleMapsUri: "https://maps.google.com/?cid=\(placeId)",
        serviceEvidence: ["consignment": "not_mentioned", "buysOutright": "mentioned"],
        acceptanceStatus: "unknown", attribution: "google_maps")
}

@MainActor
private func directoryResult(_ id: String = "directory:keh", evidence: [String: String] = ["buysOutright": "offered"]) -> DispositionPartnerResult {
    DispositionPartnerResult(
        partnerId: id, name: "KEH Camera", partnerType: "buyer",
        contact: DispositionPartnerContact(phone: nil, website: "https://www.keh.com/", email: nil,
                                           address: nil, city: nil, region: nil),
        distanceMiles: nil, rating: nil, userRatingsTotal: nil, trust: nil, ranking: nil,
        whyRecommended: nil, questionsToAsk: nil,
        source: "ltc_directory", directoryId: id, serviceEvidence: evidence,
        serviceArea: "Nationwide (mail-in), US", intakeModel: "mail_in", verifiedAt: "2026-10-16",
        acceptanceStatus: "unknown")
}

private let cameraSpecialty = LiquidationSpecialtyDTO(itemKind: "film camera", brand: "Leica", model: "M3",
                                                      isSpecialistItem: true)

@MainActor
private final class Store {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(for: LTCItem.self, LTCItemSet.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// An item with a Brief (Consignment recommended) and a Plan for `chosen`.
    func itemWithPlan(_ chosen: LiquidationPath = .pathB) async throws -> (LTCItem, LiquidationPlanRecord) {
        let item = LTCItem(name: "Grandpa's Leica M3", itemDescription: "Private family notes.", category: "Electronics", value: 1800)
        context.insert(item)
        let brief = LiquidationBriefDTO(scope: .item, recommendedPath: .pathB_delegateConsign, reasoning: "r",
                                        pathOptions: [], actionSteps: [], specialty: cameraSpecialty)
        let record = try LiquidationWorkflow.recordNewBrief(brief, owner: .item(item), context: context)
        let plan = try await LiquidationWorkflow.createPlan(
            owner: .item(item), chosen: chosen, briefRecord: record, brief: brief, context: context
        ) {
            LiquidationPlanChecklistDTO(schemaVersion: 2, items: [
                .init(order: 1, text: "Find a specialist", action: "findSpecialtyHelp"),
                .init(order: 2, text: "Compare terms"),
            ])
        }
        return (item, plan)
    }

    func closetLotWithPlan() async throws -> (LTCItemSet, LiquidationPlanRecord) {
        let set = LTCItemSet(name: "Mom's closet", setType: .closetLot)
        context.insert(set)
        let brief = LiquidationBriefDTO(scope: .set, recommendedPath: .pathB_delegateConsign, reasoning: "r",
                                        pathOptions: [], actionSteps: [])
        let record = try LiquidationWorkflow.recordNewBrief(brief, owner: .itemSet(set), context: context)
        let plan = try await LiquidationWorkflow.createPlan(
            owner: .itemSet(set), chosen: .pathB, briefRecord: record, brief: brief, context: context
        ) {
            LiquidationPlanChecklistDTO(schemaVersion: 2, items: [
                .init(order: 1, text: "Mail designer pieces", group: "luxury"),
                .init(order: 2, text: "Consign contemporary pieces", group: "contemporary"),
            ])
        }
        return (set, plan)
    }
}

private let boise = DispositionLocationDTO(city: "Boise", region: "ID", countryCode: "US", radiusMiles: 25,
                                           latitude: 43.62, longitude: -116.21)

// MARK: - Search preview and explicit search

@MainActor
struct FindHelpSearchTests {

    @Test func openingTheScreenSendsNothing() async throws {
        let store = try Store()
        let (item, _) = try await store.itemWithPlan()
        let recorder = SearchRecorder()
        let model = FindHelpModel.make(owner: .item(item), request: nil, searcher: recorder.searcher)
        #expect(recorder.calls.isEmpty)
        #expect(model.state == .idle)
        #expect(model.response == nil)
    }

    @Test func planStrategyIsAuthoritativeAndSpecialtyGivesTheTitle() async throws {
        let store = try Store()
        let (item, plan) = try await store.itemWithPlan(.pathC)   // Brief recommended Consignment
        let step = try #require(LiquidationWorkflow.checklist(of: plan)?.items.first)
        let request = LiquidationWorkflow.findHelpRequest(plan: plan, step: step, action: .findSpecialtyHelp)
        let model = FindHelpModel.make(owner: .item(item), request: request, searcher: SearchRecorder().searcher)
        #expect(model.strategy == .quickSale)
        #expect(model.isStrategyFromPlan)
        #expect(model.title == "Find Specialty Help")
        #expect(model.phrase == "film camera")
        #expect(model.hasPlan)
        #expect(FindHelpModel.lookingFor(.quickSale) == "Businesses that buy items like this")
    }

    @Test func withoutAPlanNoApproachIsInventedAndChoosingIsOff() throws {
        let store = try Store()
        let item = LTCItem(name: "Oak dining table", itemDescription: "", category: "Furniture")
        store.context.insert(item)
        let model = FindHelpModel.make(owner: .item(item), request: nil, searcher: SearchRecorder().searcher)
        #expect(model.strategy == nil)
        #expect(!model.isStrategyFromPlan)
        #expect(!model.hasPlan)
        #expect(model.title == "Find Help")
        #expect(model.phrase == "furniture")
        #expect(model.blockingReason == "Choose the kind of help you want.")
        #expect(!model.canSearch)
        #expect(model.selection(for: googleResult(), label: "", notes: "") == nil)
        // External search still works without a Plan.
        #expect(model.webSearchURL != nil)
        #expect(model.searchPrompt != nil)
    }

    @Test func searchRunsOnlyWhenCalledAndUsesTheEditedWording() async throws {
        let recorder = SearchRecorder()
        let model = FindHelpModel(
            suggestion: SearchIntentSuggestion(strategy: .consignment, phrase: "film camera",
                                               detailTerms: ["Leica"], geoScope: .local, phraseSource: .specialty),
            planStrategy: .consignment, request: nil, searcher: recorder.searcher)
        model.city = "Boise"
        model.region = "ID"
        model.phrase = "rangefinder camera"
        model.includeDetails = false
        #expect(recorder.calls.isEmpty)

        await model.search(location: boise)
        #expect(recorder.calls.count == 1)
        let (intent, location) = recorder.calls[0]
        #expect(intent.phrase == "rangefinder camera")
        #expect(intent.detailTerms.isEmpty)
        #expect(intent.valueBand == nil)
        #expect(location.latitude == 43.62)
        #expect(model.lastSentIntent == intent)
        #expect(model.state == .finished)

        let q = URLComponents(url: try #require(model.webSearchURL), resolvingAgainstBaseURL: false)?
            .queryItems?.first?.value
        #expect(q == "rangefinder camera consignment near Boise, ID")
        #expect(model.searchPrompt?.contains("rangefinder camera") == true)
    }

    @Test func scopesSendOnlyTheLocationTheyNeed() {
        let regional = FindHelpModel.location(for: .regional, from: boise)
        #expect((regional.city, regional.region, regional.latitude, regional.longitude) == ("", "ID", nil, nil))
        let national = FindHelpModel.location(for: .national, from: boise)
        #expect((national.city, national.region, national.latitude) == ("", "", nil))
        #expect(FindHelpModel.location(for: .local, from: boise).latitude == 43.62)
    }

    @Test func blockingReasonsFollowTheScope() {
        let model = FindHelpModel(
            suggestion: SearchIntentSuggestion(strategy: .consignment, phrase: "film camera", detailTerms: [],
                                               geoScope: .local, phraseSource: .specialty),
            planStrategy: .consignment, request: nil, searcher: SearchRecorder().searcher)
        #expect(model.blockingReason == "Enter a city and state, or use your current location.")
        model.scope = .regional
        #expect(model.blockingReason == "Enter a US state.")
        model.scope = .national
        #expect(model.blockingReason == nil)
        model.phrase = "call 208-555-1234"
        #expect(model.blockingReason == SearchIntentValidator.ValidationError.containsLongNumber.errorDescription)
    }

    @Test func privacySummaryStatesExactlyWhatIsShared() {
        let model = FindHelpModel(
            suggestion: SearchIntentSuggestion(strategy: .consignment, phrase: "film camera", detailTerms: ["Leica"],
                                               geoScope: .local, phraseSource: .specialty),
            planStrategy: .consignment, request: nil, searcher: SearchRecorder().searcher)
        model.city = "Boise"
        model.region = "ID"
        let typed = model.privacySummary(usesDeviceLocation: false)
        #expect(typed.contains("\u{201C}film camera\u{201D} and \u{201C}Leica\u{201D}"))
        #expect(typed.contains("Boise, ID"))
        #expect(!typed.contains("precise"))
        #expect(model.privacySummary(usesDeviceLocation: true).contains("your precise location from Use Current Location"))
        model.scope = .national
        #expect(model.privacySummary(usesDeviceLocation: true).contains("No location is shared."))
    }

    @Test func failuresAreHonestAndKeepExternalSearchAvailable() async {
        let recorder = SearchRecorder()
        recorder.result = .failure(AIError.offline(requestID: "r"))
        let model = FindHelpModel(
            suggestion: SearchIntentSuggestion(strategy: .donation, phrase: "kitchenware", detailTerms: [],
                                               geoScope: .national, phraseSource: .category),
            planStrategy: .donation, request: nil, searcher: recorder.searcher)
        await model.search(location: boise)
        #expect(model.state == .failed("You appear to be offline. You can still search the web or copy the search prompt."))
        #expect(model.response == nil)
        #expect(model.webSearchURL != nil)

        #expect(FindHelpModel.failureMessage(for: AIError.rateLimited(requestID: "r")).contains("limit"))
        #expect(FindHelpModel.failureMessage(for: AIError.serviceUnavailable(requestID: "r")).contains("unavailable"))
    }

    @Test func statusNoticesExplainMissingResults() async {
        let recorder = SearchRecorder()
        let model = FindHelpModel(
            suggestion: SearchIntentSuggestion(strategy: .consignment, phrase: "film camera", detailTerms: [],
                                               geoScope: .local, phraseSource: .specialty),
            planStrategy: .consignment, request: nil, searcher: recorder.searcher)
        model.city = "Boise"; model.region = "ID"
        for (status, needle) in [("no_results", "No matching businesses"), ("limited", "usage limit"),
                                 ("unavailable", "unavailable right now")] {
            recorder.result = .success(response(local: status))
            await model.search(location: boise)
            #expect(model.statusNotice?.contains(needle) == true, "\(status)")
        }
        model.scope = .national
        recorder.result = .success(response(directory: "no_match", scope: "national"))
        await model.search(location: boise)
        #expect(model.statusNotice?.contains("no match") == true)
    }
}

// MARK: - Results and classification

@MainActor
struct FindHelpResultTests {

    @Test func googleAndDirectoryResultsAreSeparate() async {
        let recorder = SearchRecorder()
        recorder.result = .success(response(results: [googleResult(), directoryResult()]))
        let model = FindHelpModel(
            suggestion: SearchIntentSuggestion(strategy: .quickSale, phrase: "film camera", detailTerms: [],
                                               geoScope: .national, phraseSource: .specialty),
            planStrategy: .quickSale, request: nil, searcher: recorder.searcher)
        await model.search(location: boise)
        #expect(model.googleResults.map(\.name) == ["Boise Camera & Video"])
        #expect(model.directoryResults.map(\.name) == ["KEH Camera"])
        // A Maps listing is never shown as the website.
        let g = model.googleResults[0]
        #expect(g.contact.website == "https://shop.example")
        #expect(g.googleMapsUri == "https://maps.google.com/?cid=ChIJabcdefghij123")
    }

    @Test func serviceDescriptionsNeverOverclaim() {
        #expect(FindHelpModel.googleServiceLine(["consignment": "not_mentioned", "buysOutright": "mentioned"])
                == "The listing mentions buying.")
        #expect(FindHelpModel.googleServiceLine(nil)
                == "The listing does not say whether they consign, buy, or accept donations.")
        #expect(FindHelpModel.directoryModelLine(["buysOutright": "offered"]) == "Buys items outright. This is not consignment.")
        #expect(FindHelpModel.directoryModelLine(["auction": "offered"])
                == "Sells items for you through online auctions to professional buyers.")
        #expect(FindHelpModel.directoryModelLine(["marketplace": "offered"])
                == "A marketplace: you list, sell, and ship the item yourself.")
        #expect(FindHelpModel.directoryModelLine(["buysOutright": "offered", "consignment": "offered"])
                == "Buys items outright or sells them for you on consignment.")
    }

    @Test func differentSellingModelsAreCalledOut() {
        #expect(FindHelpModel.approachNote(strategy: .consignment, evidence: ["auction": "offered"])
                == "Different from your Consignment Plan: this is an auction service.")
        #expect(FindHelpModel.approachNote(strategy: .consignment, evidence: ["buysOutright": "offered"])
                == "Different from your Consignment Plan: they do not consign.")
        #expect(FindHelpModel.approachNote(strategy: .quickSale, evidence: ["marketplace": "offered"]) != nil)
        #expect(FindHelpModel.approachNote(strategy: .consignment, evidence: ["consignment": "offered"]) == nil)
        #expect(FindHelpModel.approachNote(strategy: nil, evidence: ["auction": "offered"]) == nil)
        #expect(FindHelpModel.intakeLine("mail_in") == "By mail")
        #expect(FindHelpModel.verifiedLine("2026-10-16")?.hasPrefix("Details checked by LTC on") == true)
        #expect(FindHelpModel.verifiedLine("not a date") == nil)
    }

    @Test func outreachMessageIncludesNoValueOrPrivateDetails() {
        let message = DispositionPartnersView.outreachMessage(businessName: "KEH Camera", phrase: "film camera", questions: [])
        #expect(message.contains("Hello KEH Camera"))
        #expect(message.contains("film camera"))
        #expect(!message.contains("$") && !message.lowercased().contains("value"))
    }
}

// MARK: - Choosing and persistence

@MainActor
struct ProviderSelectionTests {

    @Test func googleChoicesKeepOnlyThePlaceID() async throws {
        let store = try Store()
        let (item, plan) = try await store.itemWithPlan()
        let request = LiquidationWorkflow.findHelpRequest(plan: plan, step: nil, action: .findHelp)
        let model = FindHelpModel.make(owner: .item(item), request: request, searcher: SearchRecorder().searcher)

        let selection = try #require(model.selection(for: googleResult(), label: "  ", notes: "Ask for Sam"))
        #expect(selection.source == .googlePlaces)
        #expect(selection.providerRef == "ChIJabcdefghij123")
        #expect(selection.homeownerLabel == nil)
        #expect(selection.homeownerNotes == "Ask for Sam")
        #expect(selection.directoryName == nil && selection.directoryWebsite == nil)
        #expect(selection.group == LiquidationProviderSelectionDTO.mainGroup)

        try LiquidationWorkflow.selectProvider(selection, in: plan, owner: .item(item), context: store.context)
        let stored = String(decoding: plan.payloadJSON, as: UTF8.self)
        for googleContent in ["Boise Camera", "555-0100", "1 Main St", "shop.example", "4.7", "maps.google.com"] {
            #expect(!stored.contains(googleContent), "\(googleContent)")
        }
        #expect(SavedProviderRow.displayName(selection) == "a business you chose from Google Maps")
    }

    @Test func directoryAndHomeownerChoices() async throws {
        let store = try Store()
        let (item, plan) = try await store.itemWithPlan(.pathC)
        let model = FindHelpModel.make(
            owner: .item(item), request: LiquidationWorkflow.findHelpRequest(plan: plan, step: nil, action: .findHelp),
            searcher: SearchRecorder().searcher)

        let dir = try #require(model.selection(for: directoryResult(), label: "", notes: ""))
        #expect((dir.source, dir.providerRef, dir.directoryName, dir.directoryWebsite)
                == (.ltcDirectory, "directory:keh", "KEH Camera", "https://www.keh.com/"))
        #expect(dir.storedDisplayName == "KEH Camera")

        #expect(model.selection(for: nil, label: "  ", notes: "") == nil)  // label required
        let own = try #require(model.selection(for: nil, label: "Camera shop on 8th", notes: ""))
        #expect((own.source, own.providerRef, own.homeownerLabel) == (.homeowner, nil, "Camera shop on 8th"))
    }

    @Test func choosingChangingAndRemovingKeepProgressAndOutcome() async throws {
        let store = try Store()
        let (item, plan) = try await store.itemWithPlan()
        let owner = LiquidationOwner.item(item)
        let firstStep = try #require(LiquidationWorkflow.checklist(of: plan)?.items.first?.id)
        try LiquidationWorkflow.setStep(firstStep, completed: true, in: plan, owner: owner, context: store.context)
        try LiquidationWorkflow.saveOutcome(.fromForm(result: .consigned, amount: nil, currencyCode: "USD",
                                                      counterparty: "", date: .now, notes: "", previous: nil),
                                            in: plan, owner: owner, context: store.context)

        try LiquidationWorkflow.selectProvider(.init(source: .googlePlaces, providerRef: "ChIJfirst00000"),
                                               in: plan, owner: owner, context: store.context)
        try LiquidationWorkflow.selectProvider(.init(source: .ltcDirectory, providerRef: "directory:keh", directoryName: "KEH Camera"),
                                               in: plan, owner: owner, context: store.context)
        var checklist = try #require(LiquidationWorkflow.checklist(of: plan))
        #expect(checklist.selectedProviders?.count == 1)  // one per group: changed, not added
        #expect(LiquidationWorkflow.selection(in: checklist, group: nil)?.providerRef == "directory:keh")
        #expect(checklist.items[0].isCompleted && !checklist.items[1].isCompleted)  // nothing ticked
        #expect(checklist.outcome?.result == .consigned)
        #expect(plan.status == .inProgress)

        // Survives checkbox toggles and a relaunch.
        try LiquidationWorkflow.setStep(checklist.items[1].id, completed: true, in: plan, owner: owner, context: store.context)
        let relaunched = ModelContext(store.container)
        let reread = try #require(try relaunched.fetch(FetchDescriptor<LiquidationPlanRecord>()).first)
        checklist = try #require(LiquidationWorkflow.checklist(of: reread))
        #expect(LiquidationWorkflow.selection(in: checklist, group: nil)?.directoryName == "KEH Camera")

        try LiquidationWorkflow.removeProvider(group: "main", in: plan, owner: owner, context: store.context)
        checklist = try #require(LiquidationWorkflow.checklist(of: plan))
        #expect(checklist.selectedProviders == nil)
        #expect(checklist.outcome?.result == .consigned)
        #expect(checklist.items.allSatisfy { $0.isCompleted })
    }

    @Test func outcomeSuggestionNeverOverwritesTypedText() {
        #expect(LiquidationOutcomeForm.counterpartySuggestion("KEH Camera", current: "") == "KEH Camera")
        #expect(LiquidationOutcomeForm.counterpartySuggestion("KEH Camera", current: "My neighbor") == nil)
        #expect(LiquidationOutcomeForm.counterpartySuggestion(nil, current: "") == nil)
        #expect(LiquidationOutcomeForm.counterpartySuggestion("  ", current: "") == nil)
    }

    @Test func savedDetailsMessagesAreHonest() {
        #expect(SavedProviderDetailsSheet.message(for: "ok", overall: "ok") == nil)
        #expect(SavedProviderDetailsSheet.message(for: "not_found", overall: "ok")?.contains("no longer lists") == true)
        #expect(SavedProviderDetailsSheet.message(for: "unavailable", overall: "limited")?.contains("limit") == true)
        #expect(SavedProviderDetailsSheet.message(for: "unavailable", overall: "unavailable")?
            .contains("Your choice is still saved") == true)
    }
}

// MARK: - Sets and earlier pile choices

@MainActor
struct SetFindHelpTests {

    @Test func pileRequestsChooseForThatPile() async throws {
        let store = try Store()
        let (set, plan) = try await store.closetLotWithPlan()
        let request = LiquidationWorkflow.findHelpRequest(plan: plan, step: nil, action: .findHelp, group: "luxury")
        let model = FindHelpModel.make(owner: .itemSet(set), request: request, searcher: SearchRecorder().searcher)
        #expect(model.group == "luxury")
        #expect(model.phrase == "designer clothing")
        #expect(model.scope == .national)
        let selection = try #require(model.selection(for: directoryResult("curated:luxury:therealreal",
                                                                          evidence: ["consignment": "offered"]),
                                                     label: "", notes: ""))
        try LiquidationWorkflow.selectProvider(selection, in: plan, owner: .itemSet(set), context: store.context)
        let checklist = LiquidationWorkflow.checklist(of: plan)
        #expect(LiquidationWorkflow.selection(in: checklist, group: "luxury")?.providerRef == "curated:luxury:therealreal")
        #expect(LiquidationWorkflow.selection(in: checklist, group: "contemporary") == nil)
    }

    @Test func legacyReferencesAreMappedOnlyWhenReliable() {
        #expect(LiquidationWorkflow.legacyReference(partnerId: "gplaces:ChIJabcdefghij123")! == (.googlePlaces, "ChIJabcdefghij123"))
        #expect(LiquidationWorkflow.legacyReference(partnerId: "gplaces:bad id") == nil)
        #expect(LiquidationWorkflow.legacyReference(partnerId: "curated:luxury:grailed")! == (.ltcDirectory, "curated:luxury:grailed"))
        #expect(LiquidationWorkflow.legacyReference(partnerId: "curated-fashionphile-handbags")! == (.ltcDirectory, "directory:fashionphile"))
        #expect(LiquidationWorkflow.legacyReference(partnerId: "curated-worthydotcom")! == (.ltcDirectory, "directory:worthy"))
        #expect(LiquidationWorkflow.legacyReference(partnerId: "curated-rebag") == nil)
        #expect(LiquidationWorkflow.legacyReference(partnerId: "stub:consignment:1") == nil)
    }

    @Test func earlierPileChoicesAreImportedCautiously() async throws {
        let store = try Store()
        let (set, plan) = try await store.closetLotWithPlan()
        let defaults = try #require(UserDefaults(suiteName: "b2-legacy-\(UUID().uuidString)"))
        let planKey = "plan-key"
        func save(_ group: String, _ p: LTCSavedSelectedPartner) throws {
            defaults.set(try JSONEncoder().encode(p),
                         forKey: LiquidationWorkflow.legacySelectionKey(planKey: planKey, group: group))
        }
        try save("luxury", LTCSavedSelectedPartner(partnerId: "curated-realreal-handbags", name: "The RealReal",
                                                   partnerType: "Luxury", distanceMiles: nil,
                                                   website: "https://www.therealreal.com", phone: nil))
        try save("contemporary", LTCSavedSelectedPartner(partnerId: "curated-rebag", name: "Rebag",
                                                         partnerType: "x", distanceMiles: nil, website: nil, phone: nil))

        let unresolved = try LiquidationWorkflow.importLegacySetChoices(
            plan: plan, planKey: planKey, groups: ["luxury", "contemporary"], owner: .itemSet(set),
            context: store.context, defaults: defaults)
        #expect(unresolved == [.init(group: "contemporary", savedName: "Rebag")])
        var checklist = LiquidationWorkflow.checklist(of: plan)
        let lux = try #require(LiquidationWorkflow.selection(in: checklist, group: "luxury"))
        #expect((lux.source, lux.providerRef) == (.ltcDirectory, "curated:luxury:therealreal"))
        #expect(LiquidationWorkflow.selection(in: checklist, group: "contemporary") == nil)
        // Earlier storage is left in place.
        #expect(defaults.data(forKey: LiquidationWorkflow.legacySelectionKey(planKey: planKey, group: "luxury")) != nil)

        // Removing the imported choice does not bring it back.
        try LiquidationWorkflow.removeProvider(group: "luxury", in: plan, owner: .itemSet(set), context: store.context)
        let again = try LiquidationWorkflow.importLegacySetChoices(
            plan: plan, planKey: planKey, groups: ["luxury", "contemporary"], owner: .itemSet(set),
            context: store.context, defaults: defaults)
        checklist = LiquidationWorkflow.checklist(of: plan)
        #expect(LiquidationWorkflow.selection(in: checklist, group: "luxury") == nil)
        #expect(again.map(\.group) == ["contemporary"])

        // Choosing again for the unresolved pile settles it.
        try LiquidationWorkflow.selectProvider(.init(group: "contemporary", source: .homeowner, homeownerLabel: "Local shop"),
                                               in: plan, owner: .itemSet(set), context: store.context)
        let settled = try LiquidationWorkflow.importLegacySetChoices(
            plan: plan, planKey: planKey, groups: ["luxury", "contemporary"], owner: .itemSet(set),
            context: store.context, defaults: defaults)
        #expect(settled.isEmpty)
    }

    @Test func googleChoicesFromEarlierVersionsKeepOnlyThePlaceID() async throws {
        let store = try Store()
        let (set, plan) = try await store.closetLotWithPlan()
        let defaults = try #require(UserDefaults(suiteName: "b2-legacy-\(UUID().uuidString)"))
        defaults.set(try JSONEncoder().encode(LTCSavedSelectedPartner(
            partnerId: "gplaces:ChIJabcdefghij123", name: "Boise Consign", partnerType: "consignment",
            distanceMiles: 2, website: "https://maps.google.com/?cid=1", phone: "(208) 555-0199")),
                     forKey: LiquidationWorkflow.legacySelectionKey(planKey: "k", group: "contemporary"))
        _ = try LiquidationWorkflow.importLegacySetChoices(plan: plan, planKey: "k", groups: ["contemporary"],
                                                           owner: .itemSet(set), context: store.context, defaults: defaults)
        let sel = try #require(LiquidationWorkflow.selection(in: LiquidationWorkflow.checklist(of: plan), group: "contemporary"))
        #expect((sel.source, sel.providerRef, sel.directoryName) == (.googlePlaces, "ChIJabcdefghij123", nil))
        let stored = String(decoding: plan.payloadJSON, as: UTF8.self)
        #expect(!stored.contains("Boise Consign") && !stored.contains("555-0199"))
    }
}
