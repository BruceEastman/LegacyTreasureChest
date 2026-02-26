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

    // Live-updating query of all items, newest first
    @Query(
        sort: \LTCItem.createdAt,
        order: .reverse
    )
    private var allItems: [LTCItem]

    // Local search state
    @State private var searchText: String = ""

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

            // MARK: - Items List
            List {
                let filtered = filteredItems()

                if filtered.isEmpty {
                    Section {
                        Text("No items yet.")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.vertical, Theme.spacing.medium)
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

                NavigationLink {
                    AddItemView()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Item")
            }
        }
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

    // MARK: - Actions

    /// Delete in flat (search) mode.
    private func deleteItemsFlat(at offsets: IndexSet) {
        let current = filteredItems()
        for index in offsets {
            let item = current[index]
            modelContext.delete(item)
        }
    }

    /// Delete in grouped mode – offsets are relative to the section's items.
    private func deleteItems(_ offsets: IndexSet, in items: [LTCItem]) {
        for index in offsets {
            let item = items[index]
            modelContext.delete(item)
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
    }
}
