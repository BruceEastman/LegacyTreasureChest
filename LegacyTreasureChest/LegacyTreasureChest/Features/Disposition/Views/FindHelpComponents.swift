//
//  FindHelpComponents.swift
//  LegacyTreasureChest
//
//  B2 building blocks shared by Find Help, the Plan panel, and Set piles:
//  result cards (Google Maps and LTC directory kept visibly separate), the
//  "Choose for My Plan" sheet, and the saved-provider row whose Google details
//  are fetched only when the homeowner asks (only the place ID is stored).
//

import SwiftUI
import UIKit

// MARK: - Result cards

struct FindHelpGoogleResultCard: View {
    let result: DispositionPartnerResult
    let canChoose: Bool
    let onChoose: () -> Void
    let onCopyMessage: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var showQuestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            if let address = result.contact.address, !address.isEmpty {
                Text(address)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let facts = Self.facts(result)
            if !facts.isEmpty {
                Text(facts)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(FindHelpModel.googleServiceLine(result.serviceEvidence))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            if result.areaMatch == "outside_area" {
                Text("Outside the area you searched.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Confirm they accept your item before you go.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            FindHelpActionButtons(
                phone: result.contact.phone,
                website: result.contact.website,
                mapsLink: result.googleMapsUri,
                onCopyMessage: onCopyMessage
            )

            if let questions = result.questionsToAsk, !questions.isEmpty {
                DisclosureGroup("Questions to ask", isExpanded: $showQuestions) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(questions, id: \.self) { Text("• \($0)").font(.footnote) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
            }

            if canChoose {
                Button("Choose for My Plan", action: onChoose)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }

    static func facts(_ r: DispositionPartnerResult) -> String {
        var parts: [String] = []
        if let d = r.distanceMiles { parts.append(String(format: "%.1f mi", d)) }
        if let rating = r.rating {
            parts.append(r.userRatingsTotal.map { String(format: "%.1f stars (%d)", rating, $0) }
                         ?? String(format: "%.1f stars", rating))
        }
        return parts.joined(separator: " · ")
    }
}

struct FindHelpDirectoryResultCard: View {
    let result: DispositionPartnerResult
    let strategy: DispositionSearchStrategy?
    let canChoose: Bool
    let onChoose: () -> Void
    let onCopyMessage: () -> Void

    @State private var showQuestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.name)
                .font(.headline)
            Text(FindHelpModel.directoryModelLine(result.serviceEvidence))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            if let note = FindHelpModel.approachNote(strategy: strategy, evidence: result.serviceEvidence) {
                Text(note)
                    .font(.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            let reach = [result.serviceArea, FindHelpModel.intakeLine(result.intakeModel)].compactMap { $0 }
            if !reach.isEmpty {
                Text(reach.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let checked = FindHelpModel.verifiedLine(result.verifiedAt) {
                Text(checked)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Confirm they accept your item before sending anything.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            FindHelpActionButtons(phone: nil, website: result.contact.website, mapsLink: nil,
                                  onCopyMessage: onCopyMessage)

            if let questions = result.questionsToAsk, !questions.isEmpty {
                DisclosureGroup("Questions to ask", isExpanded: $showQuestions) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(questions, id: \.self) { Text("• \($0)").font(.footnote) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
            }

            if canChoose {
                Button("Choose for My Plan", action: onChoose)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Call, Website, and Google Maps are separate: a Maps listing is never shown
/// as the business's website.
struct FindHelpActionButtons: View {
    let phone: String?
    let website: String?
    let mapsLink: String?
    let onCopyMessage: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(alignment: .leading, spacing: 6) { buttons }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private var buttons: some View {
        if let phone, !phone.isEmpty, let url = URL(string: "tel:\(phone.filter { $0.isNumber })") {
            Button { openURL(url) } label: { Self.label("Call", "phone") }
                .fixedSize()
        }
        if let website, let url = URL(string: website), url.scheme == "https" || url.scheme == "http" {
            Button { openURL(url) } label: { Self.label("Website", "safari") }
                .fixedSize()
        }
        if let mapsLink, let url = URL(string: mapsLink) {
            Button { openURL(url) } label: { Self.label("Google Maps", "map") }
                .fixedSize()
                .accessibilityLabel("Open in Google Maps")
        }
        Button(action: onCopyMessage) { Self.label("Copy Message", "doc.on.doc") }
            .fixedSize()
    }

    /// Icon and words together (a plain Label collapses to its icon here).
    private static func label(_ title: String, _ systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).accessibilityHidden(true)
            Text(title)
        }
    }
}

// MARK: - Choose for My Plan

struct ProviderChoiceSheet: View {
    /// The business being chosen, or nil when the homeowner adds one themselves.
    let businessName: String?
    let onSave: (_ label: String, _ notes: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var notes = ""

    private var isHomeownerEntry: Bool { businessName == nil }

    var body: some View {
        NavigationStack {
            Form {
                if let businessName {
                    Section {
                        Text(businessName).font(.headline)
                        Text("Choosing a business does not tick any step or contact them. Confirm they accept your item.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField(isHomeownerEntry ? "Business name (required)" : "Your name for it (optional)", text: $label)
                        .textInputAutocapitalization(.words)
                } footer: {
                    if !isHomeownerEntry {
                        Text("Google Maps details are looked up again when you view them; LTC saves only a reference and your own words.")
                    }
                }
                Section("Notes") {
                    TextField("Optional, e.g. who you spoke with", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(isHomeownerEntry ? "Add a Business" : "Choose for My Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(label, notes) }
                        .disabled(isHomeownerEntry && label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Saved provider (Plan panel and Set piles)

struct SavedProviderRow: View {
    let selection: LiquidationProviderSelectionDTO
    let isDisabled: Bool
    let onChange: () -> Void
    let onRemove: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var showingDetails = false
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Working with: \(Self.displayName(selection))")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let notes = selection.homeownerNotes {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .leading, spacing: 6) { buttons }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDisabled)
        }
        .sheet(isPresented: $showingDetails) {
            SavedProviderDetailsSheet(selection: selection)
        }
        .confirmationDialog("Remove this business from your Plan?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your checklist progress and outcome stay as they are.")
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch selection.source {
        case .googlePlaces:
            Button("Details") { showingDetails = true }.fixedSize()
        case .ltcDirectory:
            if let site = selection.directoryWebsite, let url = URL(string: site) {
                Button("Website") { openURL(url) }.fixedSize()
            }
        case .homeowner:
            EmptyView()
        }
        Button("Change", action: onChange).fixedSize()
        Button("Remove", role: .destructive) { confirmRemove = true }.fixedSize()
    }

    static func displayName(_ s: LiquidationProviderSelectionDTO) -> String {
        s.storedDisplayName ?? "a business you chose from Google Maps"
    }
}

/// A Set pile choice saved by an earlier app version that has no reliable
/// reference. It is shown from where it was saved, never copied or guessed.
struct LegacyProviderChoiceRow: View {
    let choice: LiquidationWorkflow.LegacyProviderChoice
    let onChooseAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chosen in an earlier version: \(choice.savedName)")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose it again to keep it with this Plan.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Find Help", action: onChooseAgain)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

/// Google details for a saved choice, fetched only when the homeowner asks and
/// never stored.
struct SavedProviderDetailsSheet: View {
    let selection: LiquidationProviderSelectionDTO

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var consentGate = AIConsentGate()
    @State private var details: PlaceDetailsResponse.PlaceDetails?
    @State private var message: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isLoading {
                        ProgressView("Looking up current details…")
                    } else if let details, details.status == "ok" || details.status == "closed" {
                        Text(details.name ?? "Business").font(.headline)
                        if let address = details.address { Text(address).font(.footnote) }
                        if details.status == "closed" {
                            Text("Google Maps lists this business as closed.").font(.footnote.weight(.semibold))
                        }
                        if let link = details.googleMapsUri, let url = URL(string: link) {
                            Button("Open in Google Maps") { openURL(url) }
                        }
                    } else if let message {
                        Text(message).font(.footnote)
                    } else {
                        Button("Show Current Details") { load() }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if details != nil { Text("Google Maps") }
                        Text("LTC saves only a reference to this business and looks up its details when you ask.")
                    }
                }
                if let notes = selection.homeownerNotes {
                    Section("Your notes") { Text(notes) }
                }
            }
            .navigationTitle(SavedProviderRow.displayName(selection).capitalizedFirst)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .aiConsentSheet(consentGate)
        }
    }

    private func load() {
        guard let placeId = selection.providerRef else { return }
        Task {
            await consentGate.perform {
                isLoading = true
                defer { isLoading = false }
                do {
                    let response = try await DispositionAIService().placeDetails(placeIds: [placeId])
                    let found = response.places.first(where: { $0.placeId == placeId })
                    details = found
                    message = Self.message(for: found?.status ?? "unavailable", overall: response.status)
                } catch {
                    message = "Details are unavailable right now. Your choice is still saved."
                }
            }
        }
    }

    static func message(for status: String, overall: String) -> String? {
        switch status {
        case "ok", "closed": return nil
        case "not_found": return "Google Maps no longer lists this business. Your choice is still saved; you can choose another."
        default:
            return overall == "limited"
                ? "The lookup limit has been reached for now. Your choice is still saved."
                : "Details are unavailable right now. Your choice is still saved."
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Puts text on the clipboard (Copy Message / Copy Search Prompt).
enum FindHelpClipboard {
    @MainActor static func copy(_ text: String) { UIPasteboard.general.string = text }
}
