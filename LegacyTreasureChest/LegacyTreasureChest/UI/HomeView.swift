//
//  HomeView.swift
//  LegacyTreasureChest
//
//  Home screen shown after successful sign-in.
//  Includes navigation into the Items list, the Estate Dashboard,
//  Estate Reports, and the AI Test Lab. Also includes a developer-only
//  "Reset All Data" tool.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    /// Called when the user taps "Sign Out".
    let onSignOut: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingReset: Bool = false
    @State private var resetErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing.large) {
                // App icon / visual anchor
                Image(systemName: "shippingbox.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, Theme.spacing.xl)

                // Headline
                Text("Welcome to Legacy Treasure Chest")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacing.large)

                // Subheadline
                Text("Next we’ll start cataloging your items, photos, audio stories, and beneficiaries.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacing.large)

                // MARK: – Estate Dashboard

                NavigationLink {
                    EstateDashboardView()
                } label: {
                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("Estate Dashboard")
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Color.white)

                        Text("See your total estate value, Legacy items, and what will be Liquidated.")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Theme.accent)
                    .cornerRadius(16)
                }
                .padding(.horizontal, Theme.spacing.xl)
                .padding(.top, Theme.spacing.small)

                // MARK: – Primary navigation card (Items)

                NavigationLink {
                    ItemsListView()
                } label: {
                    Text("View Your Items")
                        .font(Theme.bodyFont.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.primary)
                        .foregroundStyle(Color.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal, Theme.spacing.xl)
                .padding(.top, Theme.spacing.small)

                // MARK: – Tools & Labs

                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Tools & Labs")
                        .ltcSectionHeaderStyle()

                    // Estate Reports entry point
                    NavigationLink {
                        EstateReportsView()
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.spacing.small) {
                            Text("Estate Reports")
                                .font(Theme.bodyFont.weight(.semibold))
                                .foregroundStyle(Theme.text)

                            Text("Generate PDF reports for your estate, beneficiaries, and executor.")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ltcCardBackground()
                    }

                    // AI Test Lab
                    NavigationLink {
                        AITestView()
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.spacing.small) {
                            Text("AI Test Lab")
                                .font(Theme.bodyFont.weight(.semibold))
                                .foregroundStyle(Theme.text)

                            Text("Try Gemini-powered item analysis with sample photos.")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ltcCardBackground()
                    }

                    // Developer-only reset tool
                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Button {
                            isConfirmingReset = true
                        } label: {
                            HStack {
                                Image(systemName: "trash.circle.fill")
                                Text("Reset All Data (Dev)")
                            }
                            .font(Theme.bodyFont)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.systemGray6))
                            .foregroundStyle(Theme.destructive)
                            .cornerRadius(16)
                        }

                        Text("Clears all items, beneficiaries, media, and links from this device. Use for testing only.")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Theme.spacing.small)
                }
                .padding(.horizontal, Theme.spacing.xl)
                .padding(.top, Theme.spacing.medium)

                if let message = resetErrorMessage {
                    Text(message)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.destructive)
                        .padding(.horizontal, Theme.spacing.xl)
                }

                // MARK: – Sign Out

                Button {
                    onSignOut()
                } label: {
                    Text("Sign Out")
                        .font(Theme.bodyFont)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(Theme.text)
                        .cornerRadius(16)
                }
                .padding(.horizontal, Theme.spacing.xl)
                .padding(.top, Theme.spacing.small)

                Spacer(minLength: Theme.spacing.xl)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset All Data?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset All Data", role: .destructive) {
                resetAllData()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all items, beneficiaries, media, and related records stored on this device. This is intended for development and testing only.")
        }
    }

    // MARK: - Reset Logic

    private func resetAllData() {
        do {
            try deleteAll(of: ItemBeneficiary.self)
            try deleteAll(of: ItemImage.self)
            try deleteAll(of: AudioRecording.self)
            try deleteAll(of: Document.self)
            try deleteAll(of: LTCItem.self)
            try deleteAll(of: Beneficiary.self)

            resetErrorMessage = nil
        } catch {
            resetErrorMessage = "Failed to reset data: \(error.localizedDescription)"
        }
    }

    private func deleteAll<T: PersistentModel>(of type: T.Type) throws {
        let descriptor = FetchDescriptor<T>()
        let all = try modelContext.fetch(descriptor)
        for object in all {
            modelContext.delete(object)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(onSignOut: { })
            .modelContainer(
                try! ModelContainer(
                    for: LTCItem.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            )
    }
}
