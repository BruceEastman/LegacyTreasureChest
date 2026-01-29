//
//  DispositionPartnersView.swift
//  LegacyTreasureChest
//
//  Disposition Engine UI (v1)
//  - Item-scoped partner discovery (advisor mode)
//  - Editable location + radius
//  - Calls backend: POST /ai/disposition/partners/search
//

import SwiftUI
import UIKit

struct DispositionPartnersView: View {
    let item: LTCItem

    @State private var city: String = "Boise"
    @State private var region: String = "ID"
    @State private var countryCode: String = "US"
    @State private var radiusMiles: Int = 25

    // Optional coordinates (we can wire device location later)
    @State private var latitude: Double? = 43.6150
    @State private var longitude: Double? = -116.2023

    @State private var isSearching: Bool = false
    @State private var errorMessage: String?
    @State private var response: DispositionPartnersSearchResponse?
    @State private var expandedPartnerIds: Set<String> = []

    private let service = DispositionAIService()

    private var currencyCode: String {
        item.valuation?.currencyCode ?? Locale.current.currency?.identifier ?? "USD"
    }

    private var chosenPathDisplay: String {
        guard let path = item.liquidationState?.activePlan?.chosenPath else { return "Not selected yet" }
        switch path {
        case .pathA: return "Maximize Price"
        case .pathB: return "Delegate / Consign"
        case .pathC: return "Quick Exit"
        case .donate: return "Donate"
        case .needsInfo: return "Needs Info"
        }
    }

    private var totalValueDisplay: String {
        let unit = max(item.valuation?.estimatedValue ?? item.value, 0)
        let qty = Double(max(item.quantity, 1))
        let total = unit * qty
        return total.formatted(.currency(code: currencyCode))
    }

    var body: some View {
        Form {
            // MARK: - Header
            Section {
                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Local Help")
                        .font(Theme.titleFont)
                        .foregroundStyle(Theme.text)

                    Text("Find nearby services for this item. You choose what to do next — we don’t auto-contact anyone.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, Theme.spacing.small)
            }

            // MARK: - Search Context Preview (Trust builder)
            Section {
                DisclosureGroup("Search context") {
                    VStack(alignment: .leading, spacing: 10) {
                        contextRow(label: "Item", value: item.name)
                        contextRow(label: "Category", value: item.category)
                        contextRow(label: "Quantity", value: "×\(max(item.quantity, 1))")
                        contextRow(label: "Est. total value", value: totalValueDisplay)
                        contextRow(label: "Chosen path", value: chosenPathDisplay)
                        Divider().padding(.vertical, 4)
                        contextRow(label: "Searching near", value: "\(city), \(region) (\(radiusMiles) miles)")
                    }
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Theme.spacing.small)
                }
            } header: {
                Text("Transparency")
                    .ltcSectionHeaderStyle()
            } footer: {
                Text("This helps you verify the app is searching using the right item context.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            // MARK: - Location Inputs
            Section {
                TextField("City", text: $city)
                    .textInputAutocapitalization(.words)

                TextField("State / Region", text: $region)
                    .textInputAutocapitalization(.characters)

                TextField("Country Code", text: $countryCode)
                    .textInputAutocapitalization(.characters)

                Stepper(value: $radiusMiles, in: 5...100, step: 5) {
                    HStack {
                        Text("Radius")
                        Spacer()
                        Text("\(radiusMiles) miles")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } header: {
                Text("Search near")
                    .ltcSectionHeaderStyle()
            }

            // MARK: - Search Button
            Section {
                Button {
                    Task { await runSearch() }
                } label: {
                    HStack(spacing: 10) {
                        if isSearching {
                            ProgressView()
                        } else {
                            Image(systemName: "magnifyingglass")
                        }

                        Text(isSearching ? "Searching…" : UserFacingTerms.Disposition.findLocalHelpCTA)
                            .font(Theme.bodyFont.weight(.semibold))
                    }
                }
                .disabled(isSearching || city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // MARK: - Error
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.destructive)
                }
            }

            // MARK: - Results
            if let response {
                Section {
                    if response.results.isEmpty {
                        Text(UserFacingTerms.Disposition.noLocalHelpFound)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(response.results) { partner in
                            partnerCard(partner)
                        }
                    }
                } header: {
                    HStack {
                        Text(UserFacingTerms.Disposition.localHelpOptionsHeader)
                            .ltcSectionHeaderStyle()
                        Spacer()
                        if !response.partnerTypes.isEmpty {
                            Text(response.partnerTypes.joined(separator: ", "))
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } footer: {
                    Text("Advisor mode: verify pickup, fees, timeline, and insurance before proceeding.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 4)

                    Text("Last updated: \(response.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(UserFacingTerms.Disposition.localHelpTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
    }

    // MARK: - UI Pieces

    private func contextRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .frame(width: 120, alignment: .leading)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func partnerCard(_ partner: DispositionPartnerResult) -> some View {
        let isExpanded = expandedPartnerIds.contains(partner.partnerId)

        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    toggleExpanded(partner.partnerId)
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(partner.name)
                                .font(Theme.bodyFont.weight(.semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(2)

                            Spacer(minLength: 0)

                            Text(partnerTypeLabel(partner.partnerType))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.accent.opacity(0.12))
                                .foregroundStyle(Theme.text)
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 14) {
                            if let dist = partner.distanceMiles {
                                Label(String(format: "%.2f mi", dist), systemImage: "location.fill")
                                    .labelStyle(.titleAndIcon)
                            }

                            if let rating = partner.rating {
                                if let count = partner.userRatingsTotal {
                                    Label("\(String(format: "%.1f", rating)) (\(count))", systemImage: "star.fill")
                                        .labelStyle(.titleAndIcon)
                                } else {
                                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                        .labelStyle(.titleAndIcon)
                                }
                            }
                        }
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)

                        if let why = cleanedWhyRecommended(partner.whyRecommended), !why.isEmpty {
                            Text(why)
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let questions = partner.questionsToAsk, !questions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Questions to ask")
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.text)

                        ForEach(questions, id: \.self) { q in
                            Text("• \(q)")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                actionsRow(for: partner)

                if FeatureFlags().showDebugInfo, let trust = partner.trust {
                    DisclosureGroup("Trust details") {
                        VStack(alignment: .leading, spacing: 6) {
                            if let score = trust.trustScore {
                                Text("trustScore: \(String(format: "%.2f", score))")
                            }
                            if let claim = trust.claimLevel {
                                Text("claimLevel: \(claim)")
                            }
                            if let gates = trust.gates, !gates.isEmpty {
                                Text("gates:")
                                ForEach(gates) { g in
                                    Text("• \(g.id) (\(g.mode)) = \(g.status)")
                                }
                            }
                            if let signals = trust.signals, !signals.isEmpty {
                                Text("signals:")
                                ForEach(signals, id: \.self) { s in
                                    Text("• \(s.label ?? s.type ?? "signal")")
                                }
                            }
                        }
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 6)
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func partnerTypeLabel(_ raw: String) -> String {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch v {
        case "estate_sale": return "Estate Sale"
        case "consignment": return "Consignment"
        case "donation": return "Donation"
        case "junk_haul": return "Haul-away"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func cleanedWhyRecommended(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        // Remove the noisy prefix if present.
        if s.lowercased().hasPrefix("matches:") {
            s = s.dropFirst("matches:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Normalize spacing around semicolons.
        s = s.replacingOccurrences(of: " ;", with: ";")
        s = s.replacingOccurrences(of: ";", with: " • ")
        return s
    }

    private func actionsRow(for partner: DispositionPartnerResult) -> some View {
        HStack(spacing: 12) {
            if let phone = partner.contact.phone, !phone.isEmpty {
                Button {
                    callPhone(phone)
                } label: {
                    Label("Call", systemImage: "phone.fill")
                }
                .buttonStyle(.bordered)
            }

            if let website = partner.contact.website, !website.isEmpty {
                Button {
                    openWebsite(website)
                } label: {
                    Label("Website", systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }

            Button {
                copyOutreachText(for: partner)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 6)
    }

    // MARK: - Search

    private func runSearch() async {
        errorMessage = nil
        isSearching = true
        defer { isSearching = false }

        let loc = DispositionLocationDTO(
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            region: region.trimmingCharacters(in: .whitespacesAndNewlines),
            countryCode: countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            radiusMiles: radiusMiles,
            latitude: latitude,
            longitude: longitude
        )

        do {
            let resp = try await service.searchPartners(
                item: item,
                location: loc,
                radiusMiles: radiusMiles
            )
            response = resp
        } catch {
            response = nil
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func toggleExpanded(_ partnerId: String) {
        if expandedPartnerIds.contains(partnerId) {
            expandedPartnerIds.remove(partnerId)
        } else {
            expandedPartnerIds.insert(partnerId)
        }
    }

    private func callPhone(_ phone: String) {
        let digits = phone.filter { $0.isNumber }
        guard let url = URL(string: "tel:\(digits)") else { return }
        UIApplication.shared.open(url)
    }

    private func openWebsite(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func copyOutreachText(for partner: DispositionPartnerResult) {
        // v1: simple copy template (we’ll swap to backend /outreach/compose next)
        var lines: [String] = []
        lines.append("Hello \(partner.name),")
        lines.append("")
        lines.append("I have an item I’m looking to sell:")
        lines.append("• \(item.name)")
        if !item.category.isEmpty { lines.append("• Category: \(item.category)") }
        lines.append("")
        lines.append("A few questions:")
        if let qs = partner.questionsToAsk, !qs.isEmpty {
            for q in qs.prefix(5) {
                lines.append("• \(q)")
            }
        } else {
            lines.append("• Do you offer pickup/handling (if needed)?")
            lines.append("• What fees/commission should I expect?")
            lines.append("• What’s the next step to get started?")
        }
        lines.append("")
        lines.append("Thank you,")

        UIPasteboard.general.string = lines.joined(separator: "\n")
    }
}
