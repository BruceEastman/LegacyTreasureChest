//
//  HowItWorksHubView.swift
//  LegacyTreasureChest
//
//  Hub for the How It Works orientation pages.
//

import SwiftUI

struct HowItWorksHubView: View {

    @State private var showStartHere = false

    var body: some View {

        ScrollView {

            VStack(alignment: .leading, spacing: Theme.spacing.large) {

                replayStartHereButton

                VStack(spacing: Theme.spacing.small) {
                    ForEach(HowItWorksContent.pages) { page in

                        NavigationLink {
                            HowItWorksDetailView(page: page)
                        } label: {
                            hubRow(page.title)
                        }
                    }
                }
                .ltcCardBackground()

            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.vertical, Theme.spacing.large)
        }
        .navigationTitle("How It Works")
        .navigationBarTitleDisplayMode(.inline)

        .fullScreenCover(isPresented: $showStartHere) {
            StartHereOnboardingView(
                onFinish: {
                    showStartHere = false
                },
                onAddFirstItem: {
                    showStartHere = false
                }
            )
        }
    }

    // MARK: - Replay Button

    private var replayStartHereButton: some View {

        Button {
            showStartHere = true
        } label: {

            HStack(spacing: Theme.spacing.medium) {

                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textSecondary)

                VStack(alignment: .leading, spacing: Theme.spacing.xs) {

                    Text("Replay Start Here")
                        .font(Theme.bodyFont.weight(.semibold))
                        .foregroundStyle(Theme.text)

                    Text("Review the quick introduction to Legacy Treasure Chest.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ltcCardBackground()
        }
    }

    // MARK: - Hub Row

    private func hubRow(_ title: String) -> some View {

        HStack {

            Text(title)
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)

            Spacer()

            Image(systemName: "chevron.forward")
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, Theme.spacing.medium)
        .padding(.horizontal, Theme.spacing.medium)
    }
}
