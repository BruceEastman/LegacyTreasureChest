//
//  DispositionPartnersView.swift
//  LegacyTreasureChest
//
//  Find Help (B2): the one shared screen for finding businesses for an Item,
//  a Set, or a Plan step.
//  - Shows what LTC proposes to search for; the homeowner edits it and picks
//    Local, Regional, or National. Nothing is sent until they tap Search.
//  - A Plan's chosen approach decides the kind of help; without a Plan the
//    homeowner chooses it.
//  - Google Maps results and LTC's reviewed national list are separate.
//  - Web search and a copyable prompt are always available.
//  - "Choose for My Plan" saves only a place ID or LTC directory ID plus the
//    homeowner's own words, then returns to the Plan.
//  State and rules live in FindHelpModel.
//

import SwiftData
import SwiftUI

struct DispositionPartnersView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let owner: LiquidationOwner

    @StateObject private var model: FindHelpModel
    @StateObject private var autofill = LTCLocationAutofill()
    @StateObject private var consentGate = AIConsentGate()

    /// True when the user tapped "Use Current Location" (fields are replaced);
    /// false for the automatic lookup on open (fields are only filled if empty).
    @State private var autofillWasExplicit = false
    @State private var choosing: ChoiceTarget?
    @State private var notice: String?

    private struct ChoiceTarget: Identifiable {
        let id = UUID()
        let result: DispositionPartnerResult?
    }

    // MARK: - Entry points

    /// From Item detail. Uses the Item's active Plan when there is one.
    init(item: LTCItem) {
        self.init(owner: .item(item), request: nil)
    }

    /// From Set detail. Uses the Set's active Plan when there is one.
    init(itemSet: LTCItemSet) {
        self.init(owner: .itemSet(itemSet), request: nil)
    }

    /// From a Plan step or a Set pile (A3 LiquidationFindHelpRequest).
    init(owner: LiquidationOwner, request: LiquidationFindHelpRequest?) {
        self.owner = owner
        let service = DispositionAIService()
        _model = StateObject(wrappedValue: FindHelpModel.make(owner: owner, request: request) { intent, location in
            try await service.searchPartners(intent: intent, location: location)
        })
    }

    // MARK: - Body

    var body: some View {
        Form {
            headerSection
            searchForSection
            whereSection
            searchButtonSection

            if let notice {
                Section { Text(notice).font(.footnote) }
            }
            resultsSections
            searchYourselfSection

            if model.hasPlan {
                Section {
                    Button("Add a Business Yourself") { choosing = ChoiceTarget(result: nil) }
                } footer: {
                    Text("Already know who you want to work with? Add them to your Plan in your own words.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
        .aiConsentSheet(consentGate)
        .sheet(item: $choosing) { target in
            ProviderChoiceSheet(businessName: target.result?.name) { label, notes in
                choose(target.result, label: label, notes: notes)
            }
        }
        .onAppear(perform: prefillLocation)
        .onReceive(autofill.$deviceFix) { fix in
            guard let fix else { return }
            let cityIsEmpty = model.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard autofillWasExplicit || cityIsEmpty else { return }
            model.city = fix.city
            model.region = fix.region
        }
    }

    // MARK: - Sections

    private var plan: LiquidationPlanRecord? {
        guard let id = model.request?.planRecordId else { return nil }
        return owner.state?.plans.first(where: { $0.planRecordId == id })
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.title)
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.text)
                if let plan, let checklist = LiquidationWorkflow.checklist(of: plan) {
                    let specific = checklist.context?.specificRecommendation
                    Text([UserFacingTerms.Liquidation.planTitle(plan.chosenPath), specific].compactMap { $0 }
                        .joined(separator: " · "))
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                    if let current = LiquidationWorkflow.selection(in: checklist, group: model.group) {
                        Text("Currently chosen: \(SavedProviderRow.displayName(current))")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Text("No Plan yet. You can still search; choose the kind of help below.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("LTC never contacts businesses for you.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var searchForSection: some View {
        Section {
            TextField("Search words", text: $model.phrase)
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search words")
            if model.phrase != model.suggestedPhrase && !model.suggestedPhrase.isEmpty {
                Button("Use suggested words (\(model.suggestedPhrase))") { model.phrase = model.suggestedPhrase }
                    .font(.footnote)
            }
            if !model.detailTerms.isEmpty {
                Toggle(isOn: $model.includeDetails) {
                    Text("Also use: \(model.detailTerms.joined(separator: ", "))")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.isStrategyFromPlan, let strategy = model.strategy {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looking for: \(FindHelpModel.lookingFor(strategy))")
                        .font(.subheadline)
                    Text("Based on your \(FindHelpModel.strategyName(strategy)) Plan.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Kind of help", selection: $model.strategy) {
                    Text("Choose…").tag(DispositionSearchStrategy?.none)
                    ForEach(DispositionSearchStrategy.allCases, id: \.self) { s in
                        Text(FindHelpModel.strategyName(s)).tag(DispositionSearchStrategy?.some(s))
                    }
                }
            }
        } header: {
            Text("What to search for")
        } footer: {
            Text("Keep it short: say what the item is, not its brand or model. You can change it before searching.")
        }
    }

    @ViewBuilder
    private var whereSection: some View {
        Section {
            Picker("Where", selection: $model.scope) {
                Text("Local").tag(DispositionGeoScope.local)
                Text("Regional").tag(DispositionGeoScope.regional)
                Text("National").tag(DispositionGeoScope.national)
            }
            .pickerStyle(.segmented)

            switch model.scope {
            case .local:
                TextField("City", text: $model.city)
                    .textInputAutocapitalization(.words)
                TextField("State", text: $model.region)
                    .textInputAutocapitalization(.characters)
                Stepper(value: $model.radiusMiles, in: 5...100, step: 5) {
                    HStack {
                        Text("Search near (miles)")
                        Spacer()
                        Text("\(model.radiusMiles)").foregroundStyle(Theme.textSecondary)
                    }
                }
                if let status = autofill.statusText {
                    Text(status).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                Button {
                    autofillWasExplicit = true
                    autofill.requestOnce()
                } label: {
                    Label(autofill.isWorking ? "Locating…" : "Use Current Location", systemImage: "location.fill")
                }
                .disabled(autofill.isWorking)
            case .regional:
                TextField("State", text: $model.region)
                    .textInputAutocapitalization(.characters)
            case .national:
                Text("Shows businesses from LTC's reviewed national list that work by mail or online. No location is used.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Where")
        } footer: {
            switch model.scope {
            case .local: Text("Results favor businesses near this place; some may be farther away.")
            case .regional: Text("Searches businesses in this US state.")
            case .national: EmptyView()
            }
        }
    }

    @ViewBuilder
    private var searchButtonSection: some View {
        Section {
            Button {
                Task { await consentGate.perform { await runSearch() } }
            } label: {
                HStack(spacing: 10) {
                    if model.state == .searching { ProgressView() } else { Image(systemName: "magnifyingglass") }
                    Text(model.state == .searching ? "Searching…" : "Search").font(Theme.bodyFont.weight(.semibold))
                }
            }
            .disabled(!model.canSearch)
            if let reason = model.blockingReason {
                Text(reason).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            if case .failed(let message) = model.state {
                Text(message).font(.footnote).foregroundStyle(Theme.destructive)
            }
        } footer: {
            Text(model.privacySummary(usesDeviceLocation: usesDeviceLocation))
        }
    }

    @ViewBuilder
    private var resultsSections: some View {
        if model.response != nil {
            if let status = model.statusNotice {
                Section { Text(status).font(.footnote) }
            }
            if !model.googleResults.isEmpty {
                Section {
                    ForEach(model.googleResults) { result in
                        FindHelpGoogleResultCard(
                            result: result,
                            canChoose: model.hasPlan,
                            onChoose: { choosing = ChoiceTarget(result: result) },
                            onCopyMessage: { copyMessage(to: result) }
                        )
                    }
                } header: {
                    Text("Businesses on Google Maps")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Maps")
                            .font(.footnote)
                            .accessibilityLabel("Business information from Google Maps")
                        Text("Appearing here does not mean a business will accept your item.")
                    }
                }
            }
            if !model.directoryResults.isEmpty {
                Section {
                    ForEach(model.directoryResults) { result in
                        FindHelpDirectoryResultCard(
                            result: result,
                            strategy: model.strategy,
                            canChoose: model.hasPlan,
                            onChoose: { choosing = ChoiceTarget(result: result) },
                            onCopyMessage: { copyMessage(to: result) }
                        )
                    }
                } header: {
                    Text("LTC's reviewed national list")
                } footer: {
                    Text("A short list LTC checks by hand. It is not complete; check terms with each business.")
                }
            }
        }
    }

    @ViewBuilder
    private var searchYourselfSection: some View {
        Section {
            if let url = model.webSearchURL {
                Button { openURL(url) } label: { Label("Search the Web", systemImage: "safari") }
            }
            if let prompt = model.searchPrompt {
                Button {
                    FindHelpClipboard.copy(prompt)
                    notice = "Search prompt copied. Paste it into the search or assistant app you use."
                } label: { Label("Copy Search Prompt", systemImage: "doc.on.doc") }
            }
        } header: {
            Text("Search further yourself")
        } footer: {
            Text("Uses your search words above. Web results are not checked by LTC.")
        }
    }

    // MARK: - Actions

    private var usesDeviceLocation: Bool {
        model.scope == .local && LocalHelpLocationResolver.deviceCoordinates(
            city: model.city, region: model.region, countryCode: "US", fix: autofill.deviceFix) != nil
    }

    private func prefillLocation() {
        let lastCity = UserDefaults.standard.string(forKey: LocalHelpLocationResolver.lastCityKey) ?? ""
        let lastRegion = UserDefaults.standard.string(forKey: LocalHelpLocationResolver.lastRegionKey) ?? ""
        if model.city.isEmpty { model.city = lastCity }
        if model.region.isEmpty { model.region = lastRegion }
    }

    /// Runs only from the Search button.
    private func runSearch() async {
        notice = nil
        UserDefaults.standard.set(model.city, forKey: LocalHelpLocationResolver.lastCityKey)
        UserDefaults.standard.set(model.region, forKey: LocalHelpLocationResolver.lastRegionKey)

        var coordinates: LocalHelpCoordinates?
        if model.scope == .local {
            coordinates = await LocalHelpLocationResolver.resolveCoordinates(
                city: model.city, region: model.region, countryCode: "US", fix: autofill.deviceFix)
        }
        let location = LocalHelpLocationResolver.makeLocationDTO(
            city: model.city, region: model.region, countryCode: "US",
            radiusMiles: model.radiusMiles, coordinates: coordinates)
        await model.search(location: location)
    }

    private func choose(_ result: DispositionPartnerResult?, label: String, notes: String) {
        guard let plan, let selection = model.selection(for: result, label: label, notes: notes) else {
            notice = "This business could not be saved to your Plan."
            choosing = nil
            return
        }
        do {
            try LiquidationWorkflow.selectProvider(selection, in: plan, owner: owner, context: modelContext)
            choosing = nil
            dismiss()  // back to the Plan or Set pile it came from
        } catch {
            notice = "Could not save your choice: \(error.localizedDescription)"
            choosing = nil
        }
    }

    private func copyMessage(to result: DispositionPartnerResult) {
        FindHelpClipboard.copy(Self.outreachMessage(businessName: result.name, phrase: model.phrase,
                                                    questions: result.questionsToAsk ?? []))
        notice = "Message copied. Paste it into an email or text to \(result.name)."
    }

    /// A short message the homeowner can send. No value or private details.
    static func outreachMessage(businessName: String, phrase: String, questions: [String]) -> String {
        var lines = ["Hello \(businessName),", "",
                     "I'm looking for help with a \(phrase.trimmingCharacters(in: .whitespacesAndNewlines)) and would like to know if you can help.",
                     "", "A few questions:"]
        let asks = questions.isEmpty
            ? ["Do you accept items like this right now?", "What fees or commission apply?", "What is the next step?"]
            : Array(questions.prefix(4))
        lines += asks.map { "• \($0)" }
        lines += ["", "Thank you,"]
        return lines.joined(separator: "\n")
    }
}
