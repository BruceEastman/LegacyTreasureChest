//
//  ItemsListView.swift
//  LegacyTreasureChest
//
//  SwiftData-backed list of items.
//  Uses @Query so changes (insert/delete) are reflected automatically.
//  The + button navigates to AddItemView for full item creation,
//  and tapping an item pushes ItemDetailView for editing.
//  A separate photo toolbar button opens BatchAddItemsFromPhotosView
//  to create multiple items from photos using AI.
//

import SwiftUI
import SwiftData
import UIKit

struct ItemsListView: View {
    // SwiftData context for deletes (inserts happen in AddItemView or batch import)
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager

    // Live-updating query of all items, newest first
    @Query(
        sort: \LTCItem.createdAt,
        order: .reverse
    )
    private var allItems: [LTCItem]

    // Local search state
    @State private var searchText: String = ""

    // Deletion error surfaces (see deleteItemsAndMedia)
    @State private var deleteErrorMessage: String?
    @State private var cleanupWarningMessage: String?

    // Manual Add creation gate: both toolbar and empty-state entry points
    // route through attemptAddManually() before AddItemView ever opens.
    @State private var isShowingAddItem = false
    @State private var isShowingFullCatalogAccessPaywall = false
    @State private var isShowingEntitlementResolvingMessage = false

    // Currency code based on current locale, defaulting to USD
    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    // Whether we are actively filtering by search
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Search Bar
            HStack {
                TextField("Search items…", text: $searchText)
                    .font(Theme.bodyFont)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
            }
            .padding(.top, 12)

            // MARK: - Sets
            NavigationLink {
                SetsListView()
            } label: {
                HStack(alignment: .top, spacing: Theme.spacing.medium) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sets")
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.text)

                        Text("Group related items — china, crystal, furniture, and jewelry collections.")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.spacing.medium)
                .padding(.vertical, Theme.spacing.medium)
                .background(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
                .padding(.top, Theme.spacing.small)
                .padding(.bottom, Theme.spacing.small)
            }
            .buttonStyle(.plain)

            // MARK: - Items List
            List {                let filtered = filteredItems()

                if filtered.isEmpty {
                    Section {
                        emptyState
                            .listRowInsets(EdgeInsets(
                                top: Theme.spacing.medium,
                                leading: Theme.spacing.large,
                                bottom: Theme.spacing.medium,
                                trailing: Theme.spacing.large
                            ))
                            .listRowBackground(Color.clear)
                    }
                } else {
                    if isSearching {
                        // Flat list when searching – easier to scan matches
                        ForEach(filtered) { item in
                            NavigationLink {
                                ItemDetailView(item: item)
                            } label: {
                                itemRow(for: item)
                            }
                        }
                        .onDelete(perform: deleteItemsFlat)
                    } else {
                        // Grouped by category when not searching
                        let grouped = Dictionary(grouping: filtered, by: normalizedCategory(for:))
                        let sortedCategories = sortedCategories(from: Array(grouped.keys))

                        ForEach(sortedCategories, id: \.self) { category in
                            if let itemsInSection = grouped[category] {
                                Section(header: Text(category).font(Theme.sectionHeaderFont)) {
                                    ForEach(itemsInSection) { item in
                                        NavigationLink {
                                            ItemDetailView(item: item)
                                        } label: {
                                            itemRow(for: item)
                                        }
                                    }
                                    .onDelete { offsets in
                                        deleteItems(offsets, in: itemsInSection)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)   // Hide default list background
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Your Items")
        .tint(Theme.accent)
        .toolbar {
            // Leading: Beneficiaries overview
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    YourBeneficiariesView()
                } label: {
                    Image(systemName: "person.3.fill")
                }
                .accessibilityLabel("View Beneficiaries")
            }

            // Trailing: Add from Photos (AI) + Add Item manually
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    BatchAddItemsFromPhotosView()
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .accessibilityLabel("Add Items from Photos (AI)")

                Button {
                    attemptAddManually()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Item")
            }
        }
        .navigationDestination(isPresented: $isShowingAddItem) {
            AddItemView()
        }
        .sheet(isPresented: $isShowingFullCatalogAccessPaywall) {
            FullCatalogAccessView()
        }
        .alert(
            "Still Checking",
            isPresented: $isShowingEntitlementResolvingMessage,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text("Still checking Full Catalog Access. Please try again in a moment.")
            }
        )
        .alert(
            "Could Not Delete Item",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { newValue in
                    if !newValue { deleteErrorMessage = nil }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    deleteErrorMessage = nil
                }
            },
            message: {
                Text(deleteErrorMessage ?? "Please try again.")
            }
        )
        .alert(
            "Cleanup Incomplete",
            isPresented: Binding(
                get: { cleanupWarningMessage != nil },
                set: { newValue in
                    if !newValue { cleanupWarningMessage = nil }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    cleanupWarningMessage = nil
                }
            },
            message: {
                Text(cleanupWarningMessage ?? "Some local storage cleanup could not be completed.")
            }
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Text("No items yet")
                .font(Theme.sectionHeaderFont)
                .foregroundStyle(Theme.text)

            Text("Start by adding a few items to begin building your inventory.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                NavigationLink {
                    BatchAddItemsFromPhotosView()
                } label: {
                    emptyStateActionRow(
                        systemImage: "photo.on.rectangle.angled",
                        title: "Add with Photos",
                        body: "Photograph items and let AI help identify them and preserve visual detail."
                    )
                }
                .buttonStyle(.plain)

                Button {
                    attemptAddManually()
                } label: {
                    emptyStateActionRow(
                        systemImage: "plus",
                        title: "Add Manually",
                        body: "Use the + button when you want to create an item without starting from a photo."
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: Theme.spacing.small) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20, alignment: .center)
                    .padding(.top, 2)

                Text("AI can help with item identification, categories, and value guidance after you add an item.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Theme.spacing.xs)
        }
        .ltcCardBackground()
    }

    @ViewBuilder
    private func emptyStateActionRow(systemImage: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Theme.spacing.xs) {
                Text(title)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)

                Text(body)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.forward")
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)
        }
        .padding(.vertical, Theme.spacing.xs)
        .contentShape(Rectangle())
    }

    // MARK: - Row + Thumbnail

    @ViewBuilder
    private func itemRow(for item: LTCItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail(for: item)

            VStack(alignment: .leading, spacing: 4) {
                // Item name – primary
                Text(item.name)
                    .font(Theme.sectionHeaderFont)
                    .foregroundStyle(Theme.text)

                // Description – secondary
                if !item.itemDescription.isEmpty {
                    Text(item.itemDescription)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                // Show value if it's greater than zero
                if item.value > 0 {
                    CurrencyText.view(item.value)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Created date as subtle metadata
                Text(item.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumbnail(for item: LTCItem) -> some View {
        if let firstImage = item.images.first,
           let uiImage = MediaStorage.loadImage(from: firstImage.filePath) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
                .clipped()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.background)

                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
            .frame(width: 56, height: 56)
        }
    }

    // MARK: - Category Helpers

    /// Normalize an item's category for grouping (fallback to "Uncategorized").
    private func normalizedCategory(for item: LTCItem) -> String {
        let trimmed = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Uncategorized" : trimmed
    }

    /// Sort categories for section order: "Uncategorized" first, then alpha.
    private func sortedCategories(from keys: [String]) -> [String] {
        keys.sorted { lhs, rhs in
            if lhs == "Uncategorized" { return true }
            if rhs == "Uncategorized" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    // MARK: - Filtering

    /// Apply simple name/description search based on searchText
    private func filteredItems() -> [LTCItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return allItems
        }

        let needle = trimmed.lowercased()

        return allItems.filter { item in
            item.name.lowercased().contains(needle) ||
            item.itemDescription.lowercased().contains(needle)
        }
    }

    // MARK: - Creation Gate

    /// Single entry point for both the toolbar "+" and the empty-state
    /// "Add Manually" row -- the capacity check happens before AddItemView
    /// ever opens, so the user never fills out a form only to discover
    /// they can't save it. Runs in a Task since the gate briefly waits for
    /// entitlement resolution if needed (see ItemCreationGate.evaluate).
    private func attemptAddManually() {
        Task {
            switch await ItemCreationGate.evaluate(
                requestedItemCount: 1,
                modelContext: modelContext,
                purchaseManager: purchaseManager
            ) {
            case .allowed:
                isShowingAddItem = true
            case .requiresFullCatalogAccess:
                isShowingFullCatalogAccessPaywall = true
            case .entitlementResolving:
                isShowingEntitlementResolvingMessage = true
            }
        }
    }

    // MARK: - Actions

    /// Delete in flat (search) mode.
    private func deleteItemsFlat(at offsets: IndexSet) {
        let current = filteredItems()
        deleteItemsAndMedia(offsets.map { current[$0] })
    }

    /// Delete in grouped mode – offsets are relative to the section's items.
    private func deleteItems(_ offsets: IndexSet, in items: [LTCItem]) {
        deleteItemsAndMedia(offsets.map { items[$0] })
    }

    /// Deletes the given items and their owned media.
    ///
    /// Order is deliberate: capture each item's media paths, delete the
    /// SwiftData records, save explicitly, and only delete the physical
    /// files after that save succeeds. If the save fails, nothing on disk
    /// is touched and the pending deletion is rolled back so a later
    /// autosave can't silently commit it without cleanup ever running.
    private func deleteItemsAndMedia(_ items: [LTCItem]) {
        guard !items.isEmpty else { return }

        var mediaPaths: [String] = []
        for item in items {
            mediaPaths.append(contentsOf: item.images.map(\.filePath))
            mediaPaths.append(contentsOf: item.audioRecordings.map(\.filePath))
            mediaPaths.append(contentsOf: item.documents.map(\.filePath))
            modelContext.delete(item)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            print("❌ Failed to delete item(s): \(error)")
            deleteErrorMessage = "Please try again."
            return
        }

        let failedPaths = MediaStorage.deleteFiles(at: mediaPaths)
        if !failedPaths.isEmpty {
            print("⚠️ Item deleted but \(failedPaths.count) local media file(s) could not be removed.")
            cleanupWarningMessage = "Some local storage cleanup could not be completed."
        }
    }
}

// MARK: - Preview Support

/// A pre-seeded in-memory container used only for Xcode previews.
private let itemsListPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    let sample1 = LTCItem(
        name: "Grandfather Clock",
        itemDescription: "Antique clock from the family farm.",
        category: "Furniture",
        value: 1200
    )

    let sample2 = LTCItem(
        name: "Oil Painting",
        itemDescription: "Landscape painting from 1978.",
        category: "Art",
        value: 0
    )

    context.insert(sample1)
    context.insert(sample2)

    return container
}()

#Preview {
    NavigationStack {
        ItemsListView()
            .modelContainer(itemsListPreviewContainer)
            .environment(PurchaseManager())
    }
}
