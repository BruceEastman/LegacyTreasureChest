//
//  HomeView.swift
//  LegacyTreasureChest
//
//  Home screen shown after successful sign-in.
//  Focused on two primary work modes:
//  1. Items & Stories
//  2. Estate Dashboard
//
//  Guide and Sign Out are moved into a top-right menu.
//  A compact live metrics strip gives immediate estate context.
//  The primary content is vertically centered when space allows.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    /// Called when the user taps "Sign Out".
    let onSignOut: () -> Void
    @Binding var openItemsAfterOnboarding: Bool

    @Environment(\.modelContext) private var modelContext
    @Query private var items: [LTCItem]

    @State private var isConfirmingReset: Bool = false
    @State private var resetErrorMessage: String?
    @State private var isShowingGuide: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Theme.spacing.large) {
                    Spacer(minLength: 0)

                    VStack(spacing: Theme.spacing.large) {
                        HomeMetricsStrip(
                            itemCount: totalItems,
                            estimatedValueText: currencyString(totalEstateValue),
                            legacyCount: legacyItemCount
                        )

                        NavigationLink {
                            ItemsListView()
                        } label: {
                            HomePrimaryCard(
                                title: "Items & Stories",
                                message: "Add items, update details, manage photos, audio stories, documents, and beneficiaries.",
                                iconName: "shippingbox.fill",
                                backgroundColor: Theme.primary
                            )
                        }

                        NavigationLink {
                            EstateDashboardView()
                        } label: {
                            HomePrimaryCard(
                                title: "Estate Dashboard",
                                message: "Review estate value, legacy vs. liquidate progress, and estate-level reports.",
                                iconName: "chart.bar.fill",
                                backgroundColor: Theme.accent
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)

                    #if DEBUG
                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("Tools & Labs")
                            .ltcSectionHeaderStyle()

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

                        NavigationLink {
                            LiquidateSandboxView()
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                                Text("Liquidate Sandbox")
                                    .font(Theme.bodyFont.weight(.semibold))
                                    .foregroundStyle(Theme.text)

                                Text("End-to-end liquidation flow: seed brief → choose path → plan → checklist.")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ltcCardBackground()
                        }

                        NavigationLink {
                            DeveloperSettingsView()
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                                Text("Developer Settings")
                                    .font(Theme.bodyFont.weight(.semibold))
                                    .foregroundStyle(Theme.text)

                                Text("Toggle backend AI and debug logging without resetting data.")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ltcCardBackground()
                        }

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
                    .padding(.top, Theme.spacing.large)
                    #endif

                    if let message = resetErrorMessage {
                        Text(message)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.destructive)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: geometry.size.height,
                    alignment: .center
                )
                .padding(.horizontal, Theme.spacing.xl)
                .padding(.vertical, Theme.spacing.large)
            }
            .background(Theme.background.ignoresSafeArea())
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isShowingGuide = true
                    } label: {
                        Label("Guide", systemImage: "book.closed")
                    }

                    Divider()

                    Button(role: .destructive) {
                        onSignOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .navigationDestination(isPresented: $openItemsAfterOnboarding) {
            ItemsListView()
        }
        .navigationDestination(isPresented: $isShowingGuide) {
            HelpView()
        }
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

    // MARK: - Home Metrics Helpers
    // Uses the same effective value / legacy logic you provided from EstateDashboardView.

    private func effectiveUnitValue(for item: LTCItem) -> Double {
        if let estimated = item.valuation?.estimatedValue, estimated > 0 {
            return estimated
        }
        return max(item.value, 0)
    }

    private func effectiveTotalValue(for item: LTCItem) -> Double {
        let qty = max(item.quantity, 1)
        return effectiveUnitValue(for: item) * Double(qty)
    }

    private func isLegacy(_ item: LTCItem) -> Bool {
        !item.itemBeneficiaries.isEmpty
    }

    private var totalItems: Int {
        items.count
    }

    private var totalEstateValue: Double {
        items.reduce(0) { $0 + effectiveTotalValue(for: $1) }
    }

    private var legacyItemCount: Int {
        items.filter(isLegacy).count
    }

    private func currencyString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    // MARK: - Reset Logic

    private func resetAllData() {
        do {
            try deleteAll(of: ItemBeneficiary.self)
            try deleteAll(of: Beneficiary.self)

            try deleteAll(of: ItemImage.self)
            try deleteAll(of: AudioRecording.self)
            try deleteAll(of: Document.self)

            try deleteAll(of: LTCItemSetMembership.self)
            try deleteAll(of: LTCItemSet.self)

            try deleteAll(of: LiquidationPlanRecord.self)
            try deleteAll(of: LiquidationBriefRecord.self)
            try deleteAll(of: LiquidationState.self)

            try deleteAll(of: BatchItem.self)
            try deleteAll(of: LiquidationBatch.self)

            try deleteAll(of: ItemValuation.self)
            try deleteAll(of: LTCItem.self)

            try deleteAll(of: LiquidationPlan.self)
            try deleteAll(of: LiquidationBrief.self)
            try deleteAll(of: LTCSet.self)
            try deleteAll(of: TriageEntry.self)

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

private struct HomeMetricsStrip: View {
    let itemCount: Int
    let estimatedValueText: String
    let legacyCount: Int

    var body: some View {
        HStack(spacing: 0) {
            metricCell(value: "\(itemCount)", label: "Items")
            divider
            metricCell(value: estimatedValueText, label: "Estimated")
            divider
            metricCell(value: "\(legacyCount)", label: "Legacy")
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(width: 1, height: 28)
    }

    private func metricCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
    }
}

private struct HomePrimaryCard: View {
    let title: String
    let message: String
    let iconName: String
    let backgroundColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing.medium) {
            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.white)

                Text(message)
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.spacing.small)

            Image(systemName: iconName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .padding(10)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.spacing.large)
        .padding(.vertical, Theme.spacing.large)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        HomeView(
            onSignOut: { },
            openItemsAfterOnboarding: .constant(false)
        )
        .modelContainer(
            try! ModelContainer(
                for: LTCItem.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
    }
}
