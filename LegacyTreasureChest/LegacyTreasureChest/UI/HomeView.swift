//
//  HomeView.swift
//  LegacyTreasureChest
//
//  Home screen shown after successful sign-in.
//  Includes navigation into the Items list and the AI Test Lab.
//  Updated to use Theme.swift design system.
//

import SwiftUI

struct HomeView: View {
    /// Called when the user taps "Sign Out".
    let onSignOut: () -> Void

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
                }
                .padding(.horizontal, Theme.spacing.xl)
                .padding(.top, Theme.spacing.medium)

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
    }
}

#Preview {
    NavigationStack {
        HomeView(onSignOut: { })
    }
}
