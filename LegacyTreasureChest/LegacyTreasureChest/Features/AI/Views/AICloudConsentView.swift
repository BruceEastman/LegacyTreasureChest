//
//  AICloudConsentView.swift
//  LegacyTreasureChest
//
//  Reusable disclosure sheet shown before the first optional AI / Local
//  Help feature, and reachable any time afterward from Guide > Privacy &
//  AI to review or change the choice.
//
//  This view only records the user's choice locally. It does not make any
//  network request and does not gate any AI/network call site — that
//  wiring happens separately.
//

import SwiftUI

struct AICloudConsentView: View {

    enum Mode {
        /// First-time consent (or review from Privacy & AI).
        case standard
        /// The owner already turned AI on under the earlier disclosure and is
        /// about to include additional photos or a document for the first
        /// time. "Not Now" cancels only this analysis; it does not turn AI off.
        case evidenceUpdate
    }

    var mode: Mode = .standard

    /// Called after the user makes a choice, with the resulting status.
    /// Optional so callers that only need the persisted side effect can
    /// ignore it.
    var onDecision: ((AICloudConsentStatus) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    private let consent = AICloudConsentManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing.large) {

                    if mode == .evidenceUpdate {
                        evidenceUpdateSection
                    }
                    coreExplanationSection
                    whatMaySendSection
                    thirdPartiesSection
                    storageSection
                    privacyPolicyLink

                    Spacer(minLength: Theme.spacing.large)
                }
                .padding(.horizontal, Theme.spacing.xl)
                .padding(.vertical, Theme.spacing.large)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(mode == .evidenceUpdate ? "Photos and Documents for AI" : "Using AI and Online Assistance")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                footerButtons
            }
        }
    }

    // MARK: - Core explanation

    private var coreExplanationSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text(
                "Your estate inventory is stored on this device.\n\n" +
                "When you choose an AI or Find Help feature, the information it needs is sent securely for online processing.\n\n" +
                "AI and Find Help are optional. The rest of the app remains fully usable if you decline."
            )
            .font(Theme.bodyFont)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
        }
    }

    // MARK: - Update notice (disclosure version 2)

    private var evidenceUpdateSection: some View {
        Text(
            "Improve with AI can now also use additional photos and a document that you select for an analysis. " +
            "The item's main photo and existing information are still sent automatically. " +
            "Please review what may be sent before continuing."
        )
        .font(Theme.bodyFont.weight(.semibold))
        .foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true)
        .ltcCardBackground()
    }

    // MARK: - What may be sent

    private var whatMaySendSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("What may be sent")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                bullet("Photos you choose to analyze, such as when you add items from photos")
                bullet("When you use Improve with AI, the item's main photo and its existing information (name, category, quantity, description, and your notes) are included automatically")
                bullet("Additional photos and one document, only when you select them for an Improve with AI analysis. A PDF's first 10 pages are sent as images, so anything printed on them, such as names, addresses, or certificate numbers, is included")
                bullet("An audio recording, when you explicitly request an AI summary")
                bullet("For liquidation guidance: item or set details such as name, description, quantity, value, and notes. Photos and documents are not sent")
                bullet("For Find Help: the search words you review, the city or state you choose, and your precise location only when you tap Use Current Location")
            }
            .ltcCardBackground()
        }
    }

    // MARK: - Third parties

    private var thirdPartiesSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Who's involved")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                bullet("Requests go through the Legacy Treasure Chest secure server")
                bullet("Google Gemini is used for AI analysis and guidance")
                bullet("Google Maps (Google Places) is used for Find Help business searches")
            }
            .ltcCardBackground()
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("What stays where")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                bullet("Legacy Treasure Chest does not maintain a cloud-hosted copy of your estate inventory")
                bullet("Our server processes what you send to answer your request and does not store it")
                bullet("Your other photos and documents are not sent and stay on this device")
                bullet("Our server keeps limited request records, such as a random ID created by the app, timing, and status, for up to 30 days for diagnostics, rate limiting, and abuse protection. These records do not include your photos, documents, recordings, or item details")
                bullet("Google processes information under its own privacy and data-handling terms. See our Privacy Policy for more information.")
            }
            .ltcCardBackground()
        }
    }

    // MARK: - Privacy Policy link

    @ViewBuilder
    private var privacyPolicyLink: some View {
        if let url = AppConstants.URLs.privacyPolicy {
            Link("Read our Privacy Policy", destination: url)
                .font(Theme.secondaryFont.weight(.semibold))
                .foregroundStyle(Theme.primary)
        }
    }

    // MARK: - Footer buttons

    private var footerButtons: some View {
        VStack(spacing: Theme.spacing.small) {
            Button {
                handleGrant()
            } label: {
                Text(mode == .evidenceUpdate ? "Continue" : "Turn On AI Features")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing.medium)
                    .background(Theme.text)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button {
                handleDecline()
            } label: {
                Text("Not Now")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing.medium)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, Theme.spacing.xl)
        .padding(.top, Theme.spacing.small)
        .padding(.bottom, Theme.spacing.medium)
        .background(.thinMaterial)
    }

    // MARK: - Actions

    private func handleGrant() {
        consent.grant()
        onDecision?(.granted)
        dismiss()
    }

    private func handleDecline() {
        // In update mode the owner keeps their existing AI choice; only the
        // pending analysis with additional evidence is cancelled.
        if mode == .standard {
            consent.decline()
        }
        onDecision?(.declined)
        dismiss()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing.small) {
            Text("•")
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 12, alignment: .leading)

            Text(text)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    AICloudConsentView()
}
