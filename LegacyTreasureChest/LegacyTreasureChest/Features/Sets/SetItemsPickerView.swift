//
//  SetItemsPickerView.swift
//  LegacyTreasureChest
//
//  Sets v1: Multi-select items and sync memberships.
//  v1.1 enhancements:
//  - default suggested list by set type (with All Items override)
//  - thumbnails in picker rows (matches ItemsListView thumbnail style)
//

import SwiftUI
import SwiftData
import UIKit

struct SetItemsPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var itemSet: LTCItemSet

    @Query(sort: \LTCItem.updatedAt, order: .reverse)
    private var items: [LTCItem]

    @State private var searchText: String = ""
    @State private var selectedItemIDs: Set<UUID> = []

    private enum Scope: String, CaseIterable, Identifiable {
        case suggested = "Suggested"
        case allItems = "All Items"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .suggested

    init(itemSet: LTCItemSet) {
        self._itemSet = Bindable(wrappedValue: itemSet)
    }

    private var baseItemsForScope: [LTCItem] {
        switch scope {
        case .allItems:
            return items
        case .suggested:
            let suggested = items.filter { isSuggestedItem($0, for: itemSet.setType) }
            return suggested.isEmpty ? items : suggested
        }
    }

    private var filteredItems: [LTCItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return baseItemsForScope }

        return baseItemsForScope.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.category.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Scope", selection: $scope) {
                    ForEach(Scope.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                Text(scopeDescription)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            Section {
                ForEach(filteredItems) { item in
                    Button {
                        toggle(item)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            thumbnail(for: item)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(Theme.sectionHeaderFont)
                                    .foregroundStyle(Theme.text)

                                Text("\(item.category) • Qty \(item.quantity) • $\(item.value, specifier: "%.0f")")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: selectedItemIDs.contains(item.itemId) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedItemIDs.contains(item.itemId) ? Theme.accent : Theme.textSecondary)
                                .padding(.top, 2)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Select Items")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search items")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    applyChanges()
                    dismiss()
                }
            }
        }
        .onAppear {
            selectedItemIDs = Set(itemSet.memberships.compactMap { $0.item?.itemId })
            scope = (itemSet.setType == .other) ? .allItems : .suggested
        }
    }

    private var scopeDescription: String {
        switch scope {
        case .suggested:
            return "Shows items that most likely fit this set type. Switch to “All Items” for mixed sets."
        case .allItems:
            return "Shows every item in your inventory."
        }
    }

    private func toggle(_ item: LTCItem) {
        if selectedItemIDs.contains(item.itemId) {
            selectedItemIDs.remove(item.itemId)
        } else {
            selectedItemIDs.insert(item.itemId)
        }
    }

    private func applyChanges() {
        // Lookup existing memberships by itemId.
        var existingByItemId: [UUID: LTCItemSetMembership] = [:]
        for membership in itemSet.memberships {
            if let id = membership.item?.itemId {
                existingByItemId[id] = membership
            }
        }

        // Remove memberships no longer selected.
        for membership in itemSet.memberships {
            guard let id = membership.item?.itemId else { continue }
            if !selectedItemIDs.contains(id) {
                modelContext.delete(membership)
            }
        }

        // Add memberships for newly selected items.
        for item in items where selectedItemIDs.contains(item.itemId) {
            if existingByItemId[item.itemId] == nil {
                let membership = LTCItemSetMembership(
                    createdAt: .now,
                    role: "member",
                    quantityInSet: nil
                )
                membership.item = item
                membership.itemSet = itemSet
                modelContext.insert(membership)
            }
        }

        itemSet.updatedAt = .now
    }

    // MARK: - Thumbnails (matches ItemsListView)

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

    // MARK: - Suggested mapping (SetType → item.category)

    private func isSuggestedItem(_ item: LTCItem, for setType: SetType) -> Bool {
        let cat = item.category.lowercased()

        func containsAny(_ needles: [String]) -> Bool {
            needles.contains { cat.contains($0.lowercased()) }
        }

        switch setType {
        case .china:
            return containsAny(["china", "dinnerware", "china & crystal", "crystal"])
        case .crystal:
            return containsAny(["crystal", "stemware", "china & crystal", "glass"])
        case .flatware:
            return containsAny(["flatware", "silver", "silverware"])
        case .rugCollection:
            return containsAny(["rug"])
        case .diningRoom, .bedroom, .furnitureSuite:
            return containsAny(["furniture", "decor"])
        case .other:
            return true
        }
    }
}
