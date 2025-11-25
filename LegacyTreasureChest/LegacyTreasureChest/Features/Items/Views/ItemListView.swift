//
//  ItemsListView.swift
//  LegacyTreasureChest
//
//  SwiftData-backed list of items.
//  Uses @Query so changes (insert/delete) are reflected automatically.
//  The + button navigates to AddItemView for full item creation,
//  and tapping an item pushes ItemDetailView for editing.
//

import SwiftUI
import SwiftData

struct ItemsListView: View {
    // SwiftData context for deletes (inserts happen in AddItemView)
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

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Search Bar
            HStack {
                TextField("Search items…", text: $searchText)
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
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(filtered) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)

                                if !item.itemDescription.isEmpty {
                                    Text(item.itemDescription)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                // Show value if it's greater than zero
                                if item.value > 0 {
                                    Text(item.value, format: .currency(code: currencyCode))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Text(item.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
            }
        }
        .navigationTitle("Your Items")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    AddItemView()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Item")
            }
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

    private func deleteItems(at offsets: IndexSet) {
        let current = filteredItems()

        for index in offsets {
            let item = current[index]
            modelContext.delete(item)
        }
        // @Query + SwiftData will automatically reflect deletions.
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
