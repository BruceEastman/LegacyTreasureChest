//
//  AIPrivacySettingsView.swift
//  LegacyTreasureChest
//
//  Release-reachable place to review the AI / Local Help disclosure and
//  see or change the current consent choice. Reached from Guide.
//
//  This screen does not gate any network request itself — it only reads
//  and writes AICloudConsentStatus via AICloudConsentManager.
//

import SwiftUI

struct AIPrivacySettingsView: View {

    @State private var consent = AICloudConsentManager()
    @State private var isShowingDisclosure = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {

                header

                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Status")
                        .ltcSectionHeaderStyle()

                    HStack {
                        Text(statusLabel)
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                    }
                    .ltcCardBackground()
                }

                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Button {
                        isShowingDisclosure = true
                    } label: {
                        Text("Review AI & Online Assistance")
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacing.medium)
                            .background(Theme.text)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if consent.status == .granted {
                        Button {
                            revoke()
                        } label: {
                            Text("Turn Off AI Features")
                                .font(Theme.bodyFont.weight(.semibold))
                                .foregroundStyle(Theme.destructive)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.spacing.medium)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }

                if let url = AppConstants.URLs.privacyPolicy {
                    Link("Read our Privacy Policy", destination: url)
                        .font(Theme.secondaryFont.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                }

                Spacer(minLength: Theme.spacing.large)
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.vertical, Theme.spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Privacy & AI")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingDisclosure) {
            AICloudConsentView { _ in
                refresh()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("AI & Online Assistance")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)

            Text("Review what happens when you use AI photo analysis, value guidance, or Local Help, and change your choice at any time.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.spacing.small)
    }

    private var statusLabel: String {
        switch consent.status {
        case .notDetermined: return "Not Set"
        case .granted: return "On"
        case .declined: return "Off"
        }
    }

    private func revoke() {
        consent.revoke()
        refresh()
    }

    /// AICloudConsentManager is a plain UserDefaults-backed class (not
    /// observable), so re-create it after a mutation to force this view
    /// to reread the persisted value — same pattern used by FeatureFlags
    /// elsewhere in the app.
    private func refresh() {
        consent = AICloudConsentManager()
    }
}

#Preview {
    NavigationStack {
        AIPrivacySettingsView()
    }
}
