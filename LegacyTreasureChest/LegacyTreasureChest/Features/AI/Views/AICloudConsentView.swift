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
            .navigationTitle("Using AI and Online Assistance")
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
                "Your estate inventory is stored on this iPhone.\n\n" +
                "When you choose an AI or Local Help feature, selected information is sent securely for online processing.\n\n" +
                "AI and Local Help are optional. The rest of the app remains fully usable if you decline."
            )
            .font(Theme.bodyFont)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
        }
    }

    // MARK: - What may be sent

    private var whatMaySendSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("What may be sent")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                bullet("A photo you choose to analyze")
                bullet("Item title, description, or notes")
                bullet("An audio recording, when you explicitly request an AI summary")
                bullet("Valuation or liquidation details")
                bullet("City or general area, for Local Help searches")
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
                bullet("Google Places is used for applicable Local Help searches")
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
                bullet("Our server does not keep submitted photos, audio, or item details in permanent storage")
                bullet("Limited request details (like a device ID, timing, and status) may be logged for diagnostics, rate limiting, and abuse protection")
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
                Text("Turn On AI Features")
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
        consent.decline()
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
