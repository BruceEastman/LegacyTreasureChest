//
//  FindHelpModel.swift
//  LegacyTreasureChest
//
//  B2: state and rules for the shared Find Help screen (DispositionPartnersView).
//  - Starts from SearchIntentBuilder's suggestion; the homeowner reviews and
//    edits it. Nothing is sent until search() is called from an explicit tap.
//  - With a Plan, the Plan's approach decides what is searched for; without
//    one, the homeowner chooses (no approach is invented).
//  - Results are held only for this screen; Google business details are never
//    stored. Choosing a business for a Plan keeps a place ID or LTC directory
//    ID plus the homeowner's own words.
//

import Combine
import Foundation

@MainActor
final class FindHelpModel: ObservableObject {

    enum SearchState: Equatable {
        case idle
        case searching
        case finished
        case failed(String)
    }

    typealias Searcher = (DispositionSearchIntentDTO, DispositionLocationDTO) async throws -> DispositionPartnersSearchResponse

    // MARK: Inputs the homeowner controls

    @Published var phrase: String
    @Published var detailTerms: [String]
    @Published var includeDetails: Bool = true
    /// Fixed by the Plan when there is one; otherwise chosen by the homeowner.
    @Published var strategy: DispositionSearchStrategy?
    @Published var scope: DispositionGeoScope
    @Published var city: String = ""
    @Published var region: String = ""
    @Published var radiusMiles: Int = 25

    // MARK: Results (this screen only)

    @Published private(set) var state: SearchState = .idle
    @Published private(set) var response: DispositionPartnersSearchResponse?
    /// The intent behind the current results (what was actually sent).
    @Published private(set) var lastSentIntent: DispositionSearchIntentDTO?

    // MARK: Context

    let request: LiquidationFindHelpRequest?
    let isStrategyFromPlan: Bool
    let isSpecialty: Bool
    let suggestedPhrase: String
    private let searcher: Searcher

    var hasPlan: Bool { request?.planRecordId != nil }
    var group: String { request?.group ?? LiquidationProviderSelectionDTO.mainGroup }

    init(suggestion: SearchIntentSuggestion?, planStrategy: DispositionSearchStrategy?,
         request: LiquidationFindHelpRequest?, searcher: @escaping Searcher) {
        self.request = request
        self.searcher = searcher
        self.phrase = suggestion?.phrase ?? ""
        self.suggestedPhrase = suggestion?.phrase ?? ""
        self.detailTerms = suggestion?.detailTerms ?? []
        self.scope = suggestion?.geoScope ?? .local
        self.strategy = planStrategy
        self.isStrategyFromPlan = planStrategy != nil
        self.isSpecialty = (request?.wantsSpecialist ?? false) || suggestion?.phraseSource == .specialty
    }

    /// Builds the model for an Item or Set, from a Plan step's request or from
    /// the owner's active Plan when opened directly. Without a Plan the phrase
    /// is still suggested but the homeowner picks the kind of help.
    static func make(owner: LiquidationOwner, request: LiquidationFindHelpRequest?,
                     searcher: @escaping Searcher) -> FindHelpModel {
        let plan = LiquidationWorkflow.activePlan(owner.state)
        let effectiveRequest: LiquidationFindHelpRequest? = request
            ?? plan.map { LiquidationWorkflow.findHelpRequest(plan: $0, step: nil, action: .findHelp) }

        var suggestion = effectiveRequest.flatMap { SearchIntentBuilder.suggestion(for: $0, owner: owner) }
        let planStrategy = suggestion?.strategy
        if suggestion == nil {
            // No usable Plan: suggest wording only (the approach is not assumed).
            switch owner {
            case .item(let item):
                suggestion = SearchIntentBuilder.suggest(approach: .pathB_delegateConsign, specialty: nil,
                                                         itemName: item.name, category: item.category)
            case .itemSet(let set):
                suggestion = SearchIntentBuilder.suggest(approach: .pathB_delegateConsign, specialty: nil,
                                                         setName: set.name, setType: set.setType, pile: nil)
            }
        }
        return FindHelpModel(
            suggestion: suggestion,
            planStrategy: planStrategy,
            request: planStrategy == nil ? nil : effectiveRequest,
            searcher: searcher
        )
    }

    // MARK: - Presentation

    var title: String { isSpecialty ? "Find Specialty Help" : "Find Help" }

    /// "Consignment shops and specialist dealers", etc.
    static func lookingFor(_ strategy: DispositionSearchStrategy) -> String {
        switch strategy {
        case .consignment: return "Consignment shops and specialist dealers"
        case .maximizePrice: return "Specialist dealers, auction houses, and specialist marketplaces"
        case .quickSale: return "Businesses that buy items like this"
        case .donation: return "Charities and donation centers"
        }
    }

    static func strategyName(_ strategy: DispositionSearchStrategy) -> String {
        switch strategy {
        case .maximizePrice: return UserFacingTerms.Liquidation.maximizePrice
        case .consignment: return UserFacingTerms.Liquidation.consignment
        case .quickSale: return UserFacingTerms.Liquidation.quickSale
        case .donation: return UserFacingTerms.Liquidation.donation
        }
    }

    // MARK: - Intent

    /// The reviewed intent, or a validation error the screen can show.
    func currentIntent() throws -> DispositionSearchIntentDTO {
        guard let strategy else { throw SearchIntentValidator.ValidationError.unknownStrategy }
        return try SearchIntentValidator.validated(DispositionSearchIntentDTO(
            strategy: strategy.rawValue,
            phrase: phrase,
            detailTerms: includeDetails ? detailTerms : [],
            geoScope: scope.rawValue,
            valueBand: nil
        ))
    }

    /// Why Search is unavailable, in plain words; nil when ready.
    var blockingReason: String? {
        if strategy == nil { return "Choose the kind of help you want." }
        do { _ = try currentIntent() } catch { return error.localizedDescription }
        switch scope {
        case .local where city.trimmingCharacters(in: .whitespaces).isEmpty
            || region.trimmingCharacters(in: .whitespaces).isEmpty:
            return "Enter a city and state, or use your current location."
        case .regional where region.trimmingCharacters(in: .whitespaces).isEmpty:
            return "Enter a US state."
        default:
            return nil
        }
    }

    var canSearch: Bool { blockingReason == nil && state != .searching }

    /// Exactly what Search shares, shown before the homeowner taps it.
    func privacySummary(usesDeviceLocation: Bool) -> String {
        let terms = includeDetails && !detailTerms.isEmpty ? " and \u{201C}\(detailTerms.joined(separator: ", "))\u{201D}" : ""
        let what = "\u{201C}\(phrase.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}\(terms)"
        switch scope {
        case .local:
            let place = [city, region].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
            let precise = usesDeviceLocation ? ", and your precise location from Use Current Location" : ""
            return "Search shares \(what), \(place.isEmpty ? "your city and state" : place)\(precise) with LTC's server and Google Maps. Nothing else about the item is shared."
        case .regional:
            return "Search shares \(what) and \(region.isEmpty ? "your state" : region) with LTC's server and Google Maps. Nothing else about the item is shared."
        case .national:
            return "Search shares \(what) with LTC's server to check its reviewed national list. No location is shared."
        }
    }

    // MARK: - Search (explicit only)

    /// Runs only when the homeowner taps Search. A failure keeps nothing new
    /// and never touches the Plan.
    func search(location: DispositionLocationDTO) async {
        guard state != .searching else { return }
        let intent: DispositionSearchIntentDTO
        do { intent = try currentIntent() } catch {
            state = .failed(error.localizedDescription)
            return
        }
        state = .searching
        do {
            response = try await searcher(intent, Self.location(for: scope, from: location))
            lastSentIntent = intent
            state = .finished
        } catch {
            response = nil
            state = .failed(Self.failureMessage(for: error))
        }
    }

    /// Location sent for each scope: Local as given; Regional the state only;
    /// National nothing.
    static func location(for scope: DispositionGeoScope, from loc: DispositionLocationDTO) -> DispositionLocationDTO {
        switch scope {
        case .local:
            return loc
        case .regional:
            return DispositionLocationDTO(city: "", region: loc.region, countryCode: "US",
                                          radiusMiles: loc.radiusMiles, latitude: nil, longitude: nil)
        case .national:
            return DispositionLocationDTO(city: "", region: "", countryCode: "US",
                                          radiusMiles: 0, latitude: nil, longitude: nil)
        }
    }

    static func failureMessage(for error: Error) -> String {
        if let ai = error as? AIError {
            switch ai {
            case .offline: return "You appear to be offline. You can still search the web or copy the search prompt."
            case .rateLimited: return "The search limit has been reached for now. Try again later, or search the web."
            case .temporarilyUnavailable, .serviceUnavailable, .timeout:
                return "Business search is unavailable right now. Try again later, or search the web."
            case .consentRequired: return "Turn on online features to search for businesses."
            default: break
            }
        }
        return "Business search did not work this time. Try again, or search the web."
    }

    /// A plain explanation when results are missing or limited for a reason.
    var statusNotice: String? {
        guard let response else { return nil }
        if scope == .national {
            return response.directoryStatus == "no_match"
                ? "LTC's reviewed national list has no match for this item yet. Try Local or Regional, or search the web."
                : nil
        }
        switch response.localDiscoveryStatus {
        case "no_results": return "No matching businesses were found. Try different wording, a larger area, or search the web."
        case "limited": return "Business search has reached its usage limit for now. Try again later, or search the web."
        case "unavailable", "disabled": return "Business search is unavailable right now. Try again later, or search the web."
        default: return nil
        }
    }

    // MARK: - Results

    var googleResults: [DispositionPartnerResult] {
        (response?.results ?? []).filter { $0.source == "google_places" || ($0.source == nil && $0.partnerId.hasPrefix("gplaces:")) }
    }

    var directoryResults: [DispositionPartnerResult] {
        (response?.results ?? []).filter { $0.source == "ltc_directory" }
    }

    /// What the Google listing itself says. Never a claim about the item.
    static func googleServiceLine(_ evidence: [String: String]?) -> String {
        let e = evidence ?? [:]
        var said: [String] = []
        if e["consignment"] == "mentioned" { said.append("consignment") }
        if e["buysOutright"] == "mentioned" { said.append("buying") }
        if e["auction"] == "mentioned" { said.append("auctions") }
        if e["donations"] == "mentioned" { said.append("donations") }
        guard !said.isEmpty else { return "The listing does not say whether they consign, buy, or accept donations." }
        return "The listing mentions \(said.joined(separator: " and "))."
    }

    /// How an LTC directory provider sells, in plain words.
    static func directoryModelLine(_ evidence: [String: String]?) -> String {
        let e = Set((evidence ?? [:]).filter { $0.value == "offered" }.keys)
        if e.contains("consignment") && e.contains("buysOutright") { return "Buys items outright or sells them for you on consignment." }
        if e.contains("consignment") { return "Sells items for you on consignment." }
        if e.contains("buysOutright") { return "Buys items outright. This is not consignment." }
        if e.contains("auction") { return "Sells items for you through online auctions to professional buyers." }
        if e.contains("marketplace") { return "A marketplace: you list, sell, and ship the item yourself." }
        if e.contains("donations") { return "Accepts donations." }
        return "Contact them to learn how they work."
    }

    /// A note when a directory provider's way of selling differs from the Plan's approach.
    static func approachNote(strategy: DispositionSearchStrategy?, evidence: [String: String]?) -> String? {
        guard let strategy else { return nil }
        let offered = Set((evidence ?? [:]).filter { $0.value == "offered" }.keys)
        switch strategy {
        case .consignment where !offered.contains("consignment"):
            return "Different from your Consignment Plan: \(offered.contains("auction") ? "this is an auction service" : "they do not consign")."
        case .quickSale where !offered.contains("buysOutright"):
            return "Different from a Quick Sale: they do not buy items outright."
        case .donation where !offered.contains("donations"):
            return "This is not a donation service."
        default:
            return nil
        }
    }

    static func intakeLine(_ model: String?) -> String? {
        switch model {
        case "mail_in": return "By mail"
        case "in_person": return "In person"
        case "mail_in_or_in_person": return "By mail or in person"
        case "online_listing": return "Online listing"
        default: return nil
        }
    }

    static func verifiedLine(_ date: String?) -> String? {
        guard let date else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let d = parser.date(from: date) else { return nil }
        return "Details checked by LTC on \(d.formatted(date: .abbreviated, time: .omitted))."
    }

    // MARK: - External search (always available; reflects the edited phrase)

    private var externalIntent: DispositionSearchIntentDTO? {
        let s = strategy ?? .consignment
        return try? SearchIntentValidator.validated(DispositionSearchIntentDTO(
            strategy: s.rawValue, phrase: phrase,
            detailTerms: includeDetails ? detailTerms : [], geoScope: scope.rawValue))
    }

    var webSearchURL: URL? {
        externalIntent.flatMap { ExternalSearchLinks.webSearchURL(for: $0, city: city, region: region) }
    }

    var searchPrompt: String? {
        externalIntent.map { ExternalSearchLinks.discoveryPrompt(for: $0, city: city, region: region) }
    }

    // MARK: - Choosing for the Plan

    /// The selection to save. Google keeps only the place ID; the directory
    /// keeps LTC's own name and site; labels and notes are the homeowner's.
    func selection(for result: DispositionPartnerResult?, label: String, notes: String) -> LiquidationProviderSelectionDTO? {
        func clean(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        guard hasPlan else { return nil }
        guard let result else {
            guard let label = clean(label) else { return nil }
            return LiquidationProviderSelectionDTO(group: group, source: .homeowner, homeownerLabel: label,
                                                   homeownerNotes: clean(notes), stepId: request?.stepID)
        }
        if result.source == "ltc_directory", let id = result.directoryId {
            return LiquidationProviderSelectionDTO(group: group, source: .ltcDirectory, providerRef: id,
                                                   directoryName: result.name, directoryWebsite: result.contact.website,
                                                   homeownerLabel: clean(label), homeownerNotes: clean(notes),
                                                   stepId: request?.stepID)
        }
        let placeId = result.placeId ?? (result.partnerId.hasPrefix("gplaces:") ? String(result.partnerId.dropFirst(8)) : nil)
        guard let placeId else { return nil }
        return LiquidationProviderSelectionDTO(group: group, source: .googlePlaces, providerRef: placeId,
                                               homeownerLabel: clean(label), homeownerNotes: clean(notes),
                                               stepId: request?.stepID)
    }
}
