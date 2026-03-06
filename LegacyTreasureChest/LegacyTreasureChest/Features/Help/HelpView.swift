//
//  HelpView.swift
//  LegacyTreasureChest
//
//  In-app guidance for users, executors, and families.
//  UI + copy only. No backend or data model dependencies.
//

import SwiftUI

struct HelpView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {

                header

                VStack(alignment: .leading, spacing: Theme.spacing.medium) {

                    // MARK: - How It Works (Primary Orientation)

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("How It Works")
                            .ltcSectionHeaderStyle()

                        NavigationLink {
                            HowItWorksHubView()
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                                Text("Open How It Works")
                                    .font(Theme.bodyFont.weight(.semibold))
                                    .foregroundStyle(Theme.text)

                                Text("A high-level overview of what Legacy Treasure Chest does, how the Estate Journey works, and what you can do in the system.")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ltcCardBackground()
                        }
                    }

                    // MARK: - Scanning & Documents

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("Scanning & Documents")
                            .ltcSectionHeaderStyle()

                        NavigationLink {
                            ScannerHelpView()
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                                Text("Open Scanning & Documents Help")
                                    .font(Theme.bodyFont.weight(.semibold))
                                    .foregroundStyle(Theme.text)

                                Text("How to scan receipts or appraisals into a PDF using iPhone tools, and simple ways to keep files easy to find.")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ltcCardBackground()
                        }
                    }

                    // MARK: - Advisor Philosophy

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("Advisor Philosophy")
                            .ltcSectionHeaderStyle()

                        VStack(alignment: .leading, spacing: Theme.spacing.small) {
                            bullet("You stay in control. Legacy Treasure Chest does not take actions on your behalf.")
                            bullet("AI assists with suggestions and summaries; it does not make decisions for you.")
                            bullet("Nothing is automated: no listings, no outreach, and no irreversible operations.")
                            bullet("Your inventory remains on your device. AI processing is used only when needed for analysis.")
                            bullet("Exports reflect the catalog exactly as it exists at the time you generate them.")
                        }
                        .ltcCardBackground()
                    }

                    footerNote
                }
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.vertical, Theme.spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Guide")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Legacy Treasure Chest Guide")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)

            Text("Orientation and practical guidance for using the system.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, Theme.spacing.small)
    }

    private var footerNote: some View {
        Text("Reminder: Legacy Treasure Chest is an advisory system. For legal or tax decisions, consult a qualified professional.")
            .font(Theme.secondaryFont)
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, Theme.spacing.small)
    }

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
