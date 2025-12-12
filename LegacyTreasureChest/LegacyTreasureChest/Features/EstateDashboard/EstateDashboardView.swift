//
//  EstateDashboardView.swift
//  LegacyTreasureChest
//
//  Estate-level snapshot of value, Legacy vs Liquidate paths,
//  valuation readiness, category value, and high-value Liquidate items.
//  Includes an "Export & Share" section (reports) at the bottom.
//  Adds a lightweight Valuation Readiness tip sheet (ⓘ).
//

import SwiftUI
import SwiftData

struct EstateDashboardView: View {
    @Query(sort: \LTCItem.createdAt, order: .forward)
    private var items: [LTCItem]

    @State private var isShowingValuationTip: Bool = false

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {
                headerSection

                if items.isEmpty {
                    emptyStateSection
                } else {
                    estateSnapshotSection
                    estatePathsSection
                    valuationReadinessSection
                    valueByCategorySection
                    highValueLiquidateSection
                    nextStepsSection
                    exportAndShareSection
                }

                Spacer(minLength: Theme.spacing.xl)
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.top, Theme.spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Estate Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingValuationTip) {
            ValuationReadinessTipSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Legacy & Liquidate")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)

            Text("See your conservative estate value, how many items are marked as Legacy for specific people, and how much will be Liquidated and sold.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("No items yet")
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)

            Text("Start by adding items and photos. Once you have a catalog, this dashboard will show your total estate value and how your items are divided between Legacy and Liquidate.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .ltcCardBackground()
    }

    private var estateSnapshotSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Estate Snapshot")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text(totalEstateValue, format: .currency(code: currencyCode))
                        .font(Theme.titleFont)
                        .foregroundStyle(Theme.text)

                    Text("Total estate (conservative sale value)")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Items").font(Theme.secondaryFont).foregroundStyle(Theme.textSecondary)
                        Text("\(totalItems)").font(Theme.bodyFont.weight(.semibold)).foregroundStyle(Theme.text)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Legacy").font(Theme.secondaryFont).foregroundStyle(Theme.textSecondary)
                        Text("\(legacyItemCount)").font(Theme.bodyFont.weight(.semibold)).foregroundStyle(Theme.text)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Liquidate").font(Theme.secondaryFont).foregroundStyle(Theme.textSecondary)
                        Text("\(liquidateItemCount)").font(Theme.bodyFont.weight(.semibold)).foregroundStyle(Theme.text)
                    }
                }

                Text("Items without a named beneficiary are treated as Liquidate items—sold, with proceeds handled by your will or estate plan.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            .ltcCardBackground()
        }
    }

    private var estatePathsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Estate Paths")
                .ltcSectionHeaderStyle()

            VStack(spacing: Theme.spacing.medium) {
                estatePathRow(
                    title: "Legacy Items",
                    itemCount: legacyItemCount,
                    value: legacyValue,
                    valueShare: legacyValueShare
                )

                estatePathRow(
                    title: "Liquidate Items",
                    itemCount: liquidateItemCount,
                    value: liquidateValue,
                    valueShare: liquidateValueShare
                )
            }
            .ltcCardBackground()
        }
    }

    private func estatePathRow(
        title: String,
        itemCount: Int,
        value: Double,
        valueShare: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            HStack {
                Text(title)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(value, format: .currency(code: currencyCode))
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }

            HStack {
                Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Int((valueShare * 100).rounded()))% of estate value")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            ProgressView(value: valueShare, total: 1.0)
        }
    }

    private var valuationReadinessSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            HStack(alignment: .center) {
                Text("Valuation Readiness")
                    .ltcSectionHeaderStyle()

                Spacer()

                Button {
                    isShowingValuationTip = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, Theme.spacing.small)
                }
                .accessibilityLabel("Valuation readiness tip")
            }

            VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall")
                        .font(Theme.bodyFont.weight(.semibold))
                        .foregroundStyle(Theme.text)

                    ProgressView(value: valuationCompletionOverall, total: 1.0)

                    Text("Valuations complete for \(Int((valuationCompletionOverall * 100).rounded()))% of your items.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: Theme.spacing.large) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Legacy").font(Theme.secondaryFont).foregroundStyle(Theme.textSecondary)
                        Text("\(Int((legacyValuationCompletion * 100).rounded()))%")
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.text)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Liquidate").font(Theme.secondaryFont).foregroundStyle(Theme.textSecondary)
                        Text("\(Int((liquidateValuationCompletion * 100).rounded()))%")
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.text)
                    }
                }

                Text("Values are conservative resale estimates from AI or your own entries.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            .ltcCardBackground()
        }
    }

    private struct CategorySummary: Identifiable {
        let id = UUID()
        let name: String
        let itemCount: Int
        let totalValue: Double
    }

    private var valueByCategorySection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Value by Category")
                .ltcSectionHeaderStyle()

            VStack(spacing: Theme.spacing.small) {
                ForEach(categorySummaries) { summary in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.name.isEmpty ? "Uncategorized" : summary.name)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.text)

                            Text("\(summary.itemCount) item\(summary.itemCount == 1 ? "" : "s")")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()

                        Text(summary.totalValue, format: .currency(code: currencyCode))
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.vertical, 4)
                }

                if categorySummaries.isEmpty {
                    Text("No categories yet. As you add items and set categories, you’ll see where most of your value lives.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, Theme.spacing.small)
                }
            }
            .ltcCardBackground()
        }
    }

    private var highValueLiquidateSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("High-Value Liquidate Items")
                .ltcSectionHeaderStyle()

            VStack(spacing: Theme.spacing.small) {
                if highValueLiquidateItems.isEmpty {
                    Text("No high-value Liquidate items found. As you add items and values, the most valuable Liquidate items will appear here.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, Theme.spacing.small)
                } else {
                    ForEach(highValueLiquidateItems) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            highValueItemRow(for: item)
                        }
                    }
                }
            }
            .ltcCardBackground()
        }
    }

    private func highValueItemRow(for item: LTCItem) -> some View {
        HStack(spacing: Theme.spacing.medium) {
            if let firstImage = item.images.first,
               let uiImage = MediaStorage.loadImage(from: firstImage.filePath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.textSecondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.text)

                Text(item.category)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Text(effectiveValue(for: item), format: .currency(code: currencyCode))
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)
        }
        .padding(.vertical, 4)
    }

    private var nextStepsSection: some View {
        Group {
            if let message = nextStepsMessage {
                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Next Steps")
                        .ltcSectionHeaderStyle()

                    VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                        Text(message)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .ltcCardBackground()
                }
            }
        }
    }

    private var exportAndShareSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Export & Share")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Generate printable PDFs for your executor, attorney, or family.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)

                    Text("These reports summarize your Legacy vs Liquidate plan and your conservative sale values.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                Divider()

                NavigationLink {
                    EstateReportsView()
                } label: {
                    HStack(spacing: Theme.spacing.small) {
                        Image(systemName: "doc.richtext")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Estate Snapshot Report")
                                .font(Theme.bodyFont.weight(.semibold))
                                .foregroundStyle(Theme.text)
                            Text("One-page readiness summary")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 6)
                }

                NavigationLink {
                    EstateReportsView()
                } label: {
                    HStack(spacing: Theme.spacing.small) {
                        Image(systemName: "doc.text.magnifyingglass")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Detailed Inventory Report")
                                .font(Theme.bodyFont.weight(.semibold))
                                .foregroundStyle(Theme.text)
                            Text("Full item list with path and beneficiary")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 6)
                }
            }
            .ltcMutedExportCardBackground()
        }
    }

    // MARK: - Helpers

    private func effectiveValue(for item: LTCItem) -> Double {
        if let estimated = item.valuation?.estimatedValue, estimated > 0 {
            return estimated
        }
        return max(item.value, 0)
    }

    private func isLegacy(_ item: LTCItem) -> Bool {
        !item.itemBeneficiaries.isEmpty
    }

    private func isLiquidate(_ item: LTCItem) -> Bool {
        item.itemBeneficiaries.isEmpty
    }

    private var totalItems: Int { items.count }

    private var totalEstateValue: Double {
        items.reduce(0) { $0 + effectiveValue(for: $1) }
    }

    private var legacyItems: [LTCItem] { items.filter(isLegacy) }
    private var liquidateItems: [LTCItem] { items.filter(isLiquidate) }

    private var legacyItemCount: Int { legacyItems.count }
    private var liquidateItemCount: Int { liquidateItems.count }

    private var legacyValue: Double {
        legacyItems.reduce(0) { $0 + effectiveValue(for: $1) }
    }

    private var liquidateValue: Double {
        liquidateItems.reduce(0) { $0 + effectiveValue(for: $1) }
    }

    private var totalEstateValueNonZero: Double { max(totalEstateValue, 0.01) }

    private var legacyValueShare: Double { legacyValue / totalEstateValueNonZero }
    private var liquidateValueShare: Double { liquidateValue / totalEstateValueNonZero }

    private func hasValuation(_ item: LTCItem) -> Bool {
        effectiveValue(for: item) > 0
    }

    private var valuedItemsCount: Int {
        items.filter(hasValuation).count
    }

    private var valuationCompletionOverall: Double {
        guard totalItems > 0 else { return 0 }
        return Double(valuedItemsCount) / Double(totalItems)
    }

    private var legacyValuedItemsCount: Int { legacyItems.filter(hasValuation).count }
    private var liquidateValuedItemsCount: Int { liquidateItems.filter(hasValuation).count }

    private var legacyValuationCompletion: Double {
        guard legacyItemCount > 0 else { return 0 }
        return Double(legacyValuedItemsCount) / Double(legacyItemCount)
    }

    private var liquidateValuationCompletion: Double {
        guard liquidateItemCount > 0 else { return 0 }
        return Double(liquidateValuedItemsCount) / Double(liquidateItemCount)
    }

    private var categorySummaries: [CategorySummary] {
        let grouped = Dictionary(grouping: items, by: { $0.category })
        return grouped.map { (category, itemsInCategory) in
            let totalValue = itemsInCategory.reduce(0) { $0 + effectiveValue(for: $1) }
            return CategorySummary(
                name: category,
                itemCount: itemsInCategory.count,
                totalValue: totalValue
            )
        }
        .sorted { $0.totalValue > $1.totalValue }
    }

    private var highValueLiquidateItems: [LTCItem] {
        liquidateItems
            .filter(hasValuation)
            .sorted { effectiveValue(for: $0) > effectiveValue(for: $1) }
            .prefix(5)
            .map { $0 }
    }

    private var nextStepsMessage: String? {
        guard totalItems > 0 else { return nil }

        if valuationCompletionOverall < 0.7 {
            return "You have many items without a sale value. Consider adding photos and running AI analysis—especially for Liquidate items—to improve readiness."
        }

        if legacyItemCount < max(3, totalItems / 10) {
            return "Most of your estate is currently marked for liquidation. You may want to choose a few special items to mark as Legacy for specific people."
        }

        if highValueLiquidateItems.count >= 3 {
            return "You have several high-value Liquidate items. Review these to confirm whether they should remain Liquidate or be marked as Legacy."
        }

        return "Your estate is looking well organized."
    }
}

// MARK: - Tip Sheet (no nav title to avoid header overlap)

private struct ValuationReadinessTipSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.medium) {

                // Top row: title + close
                HStack(alignment: .center) {
                    Text("How to increase readiness")
                        .font(Theme.titleFont)
                        .foregroundStyle(Theme.text)

                    Spacer()

                    Button("Close") { dismiss() }
                        .font(Theme.bodyFont.weight(.semibold))
                }
                .padding(.top, Theme.spacing.small)

                Text("Readiness improves when more of your items have a conservative sale value. Most people get values by adding photos and running AI.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)

                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    tipRow("1", "Add 2–4 photos (front, back, close-up of any marks).")
                    tipRow("2", "Open the item and tap “Analyze with AI”.")
                    tipRow("3", "If value is uncertain, add a short note (brand, material, size) and re-run AI.")
                }
                .padding(.top, Theme.spacing.small)

                Divider()
                    .padding(.vertical, Theme.spacing.small)

                VStack(spacing: Theme.spacing.small) {
                    NavigationLink {
                        ItemsListView()
                    } label: {
                        HStack {
                            Image(systemName: "shippingbox")
                            Text("Go to Items")
                                .font(Theme.bodyFont.weight(.semibold))
                            Spacer()
                        }
                        .padding()
                        .background(Theme.primary)
                        .foregroundStyle(.white)
                        .cornerRadius(16)
                    }

                    NavigationLink {
                        BatchAddItemsFromPhotosView()
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Batch Add from Photos")
                                .font(Theme.bodyFont.weight(.semibold))
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(Theme.text)
                        .cornerRadius(16)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(Theme.bodyFont.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .foregroundStyle(Theme.text)
                            .cornerRadius(16)
                    }
                    .padding(.top, Theme.spacing.xs)
                }

                Spacer(minLength: Theme.spacing.small)
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.bottom, Theme.spacing.large)
        }
        .background(Theme.background)
    }

    private func tipRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing.small) {
            Text(number)
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 20, alignment: .leading)

            Text(text)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

// MARK: - Muted export card background modifier

private extension View {
    func ltcMutedExportCardBackground() -> some View {
        self
            .padding(Theme.spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray6))
                    .shadow(radius: 1)
            )
    }
}
