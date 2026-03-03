//
//  HelpView.swift
//  LegacyTreasureChest
//
//  In-app operational help for executors and calm, non-technical users.
//  UI + copy only. No backend or data model dependencies.
//

import SwiftUI

struct HelpView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {

                header

                VStack(alignment: .leading, spacing: Theme.spacing.medium) {

                    // MARK: - Getting Started (Ultra Clear First Steps)

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("Getting Started (First 5 Minutes)")
                            .ltcSectionHeaderStyle()

                        VStack(alignment: .leading, spacing: Theme.spacing.medium) {

                            step(
                                "1",
                                "Start from Home",
                                "Tap “View Your Items”. This is where you begin building your estate catalog."
                            )

                            step(
                                "2",
                                "Add your first items",
                                "On the Items screen, you can add items in two simple ways:"
                            )

                            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                                iconLine(
                                    systemImage: "photo.on.rectangle.angled",
                                    text: "Add from photos: tap the photo add button to create items from pictures."
                                )
                                iconLine(
                                    systemImage: "plus",
                                    text: "Add from text: tap the + button to type an item directly when you do not have a photo."
                                )
                            }
                            .padding(.leading, Theme.spacing.large)

                            Text("Tip: Starting from photos usually preserves more detail for executors later.")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .ltcCardBackground()
                    }

                    // MARK: - Recommended Workflow

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("Recommended Workflow")
                            .ltcSectionHeaderStyle()

                        VStack(alignment: .leading, spacing: Theme.spacing.medium) {

                            step("1", "Add Items", "Create an item record for each real object you want to track.")
                            step("2", "Add Photos", "Clear photos help preserve details for executors later.")
                            step("3", "Run AI Analysis", "Use AI to generate valuation hints and liquidation guidance. Treat this as advisory, not final.")
                            step(
                                "3a",
                                "Complete the Item Record",
                                "Add a beneficiary (if known), optional audio context, and supporting documents such as receipts or appraisals (see “Scanning & Documents” below if needed)."
                            )
                            step("4", "Create Sets (when natural)", "Use Sets when items truly belong together, such as matched pieces or collections.")
                            step("5", "Group into Lots (when planning work)", "Lots are work groupings used when preparing for downsizing or sale.")
                            step("6", "Create Batches (real-world event only)", "Create a Batch when there is an actual estate sale, dealer visit, or consignment event.")
                            step("7", "Use Execution Mode", "Execution Mode helps an executor complete planned work clearly and carefully.")
                            step("8", "Export when needed", "Exports generate executor-ready reports based on the current state of your catalog.")
                        }
                        .ltcCardBackground()
                    }

                    // MARK: - What This App Is

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("What This App Is")
                            .ltcSectionHeaderStyle()

                        VStack(alignment: .leading, spacing: Theme.spacing.small) {
                            bullet("A private, on-device system to catalog household items and organize estate planning decisions.")
                            bullet("A place to store photos, notes, documents, and optional audio context for each item.")
                            bullet("A guided workflow to group items into Sets, Lots, and Batches when you are ready to plan real-world work.")
                            bullet("An advisor tool: it helps you think clearly and produce executor-grade exports when needed.")
                        }
                        .ltcCardBackground()
                    }

                    // MARK: - What This App Is Not

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("What This App Is Not")
                            .ltcSectionHeaderStyle()

                        VStack(alignment: .leading, spacing: Theme.spacing.small) {
                            bullet("Not a marketplace. It does not list items for sale or manage transactions.")
                            bullet("Not a legal will, trust, or substitute for professional legal advice.")
                            bullet("Not a formal appraisal. Value ranges are advisory and may be incomplete or wrong.")
                            bullet("Not cloud storage for your inventory. Your catalog stays on your device; the backend is used only for AI processing.")
                        }
                        .ltcCardBackground()
                    }

                    // MARK: - Scanning & Documents (optional help)

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

                                Text("How to scan receipts/appraisals into a PDF using iPhone tools, and simple ways to keep files easy to find.")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
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
                            bullet("You stay in control. LTC does not take actions on your behalf.")
                            bullet("AI assists with suggestions and summaries; it does not make decisions.")
                            bullet("Nothing is automated: no listings, no outreach, no irreversible operations.")
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
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Legacy Treasure Chest Help")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)

            Text("Operational clarity for executors and calm, non-technical users.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, Theme.spacing.small)
    }

    private var footerNote: some View {
        Text("Reminder: LTC is an advisory system. For legal or tax decisions, consult a qualified professional.")
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

    @ViewBuilder
    private func iconLine(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing.small) {
            Image(systemName: systemImage)
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 18, alignment: .leading)
                .padding(.top, 2)

            Text(text)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func step(_ number: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing.medium) {
            Text(number)
                .font(Theme.secondaryFont.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 30, height: 30)
                .background(Color(.systemGray6))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: Theme.spacing.xs) {
                Text(title)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)

                Text(body)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
