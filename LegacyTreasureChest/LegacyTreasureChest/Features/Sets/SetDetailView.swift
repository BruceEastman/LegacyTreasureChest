//
//  SetDetailView.swift
//  LegacyTreasureChest
//
//  Sets v1: Detail view + members.
//  Enhancements:
//  - Visual reinforcement: shows the picker’s default “Suggested” intent.
//  - Adds item thumbnails for members (matches ItemsListView thumbnail style).
//  - Wires “Next Step → Liquidate Set” end-to-end.
//

import SwiftUI
import SwiftData
import UIKit

struct SetDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var itemSet: LTCItemSet

    @State private var isPresentingEdit: Bool = false
    @State private var isPresentingItemsPicker: Bool = false

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    init(itemSet: LTCItemSet) {
        self._itemSet = Bindable(wrappedValue: itemSet)
    }

    private var membersSorted: [LTCItemSetMembership] {
        itemSet.memberships.sorted { lhs, rhs in
            let lName = lhs.item?.name ?? ""
            let rName = rhs.item?.name ?? ""
            return lName.localizedCaseInsensitiveCompare(rName) == .orderedAscending
        }
    }

    private var suggestedHint: String {
        switch itemSet.setType {
        case .china:
            return "Suggested: China / Dinnerware (and related Crystal)"
        case .crystal:
            return "Suggested: Crystal / Stemware / Glass"
        case .flatware:
            return "Suggested: Flatware / Silverware"
        case .rugCollection:
            return "Suggested: Rugs"
        case .diningRoom:
            return "Suggested: Furniture / Decor (Dining Room)"
        case .bedroom:
            return "Suggested: Furniture / Decor (Bedroom)"
        case .furnitureSuite:
            return "Suggested: Furniture / Decor"
        case .closetLot:
            return "Suggested: Clothing (Closet Lot)"
        case .other:
            return "Suggested: All Items (mixed set)"
        }
    }

    var body: some View {
        Form {
            Section("Set") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(itemSet.name)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Type")
                    Spacer()
                    Text(itemSet.setType.rawValue)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    Text("Sell Preference")
                    Spacer()
                    Text(itemSet.sellTogetherPreference.rawValue)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    Text("Completeness")
                    Spacer()
                    Text(itemSet.completeness.rawValue)
                        .foregroundStyle(Theme.textSecondary)
                }

                Text(suggestedHint)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
            }

            if let story = itemSet.story, !story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Story") {
                    Text(story)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.text)
                }
            }

            if let notes = itemSet.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.text)
                }
            }

            Section {
                Button {
                    isPresentingItemsPicker = true
                } label: {
                    HStack {
                        Image(systemName: "checklist")
                        Text("Add / Remove Items")
                    }
                }

                Button {
                    isPresentingEdit = true
                } label: {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit Set")
                    }
                }

                NavigationLink {
                    SetLiquidationSectionView(itemSet: itemSet)
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Next Step → Liquidate Set")
                    }
                }
                .foregroundStyle(Theme.accent)
            }

            Section("Members (\(itemSet.memberships.count))") {
                if membersSorted.isEmpty {
                    Text("No items in this set yet.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(membersSorted) { membership in
                        if let item = membership.item {
                            NavigationLink {
                                ItemDetailView(item: item)
                            } label: {
                                memberRow(item: item, membership: membership)
                            }
                        } else {
                            Text("Unknown Item")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Set Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingEdit) {
            NavigationStack {
                SetEditorSheet(mode: .edit(itemSet))
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isPresentingItemsPicker) {
            NavigationStack {
                SetItemsPickerView(itemSet: itemSet)
            }
            .presentationDetents([.large])
        }
        .onChange(of: itemSet.name) { _, _ in touchUpdatedAt() }
        .onChange(of: itemSet.setTypeRaw) { _, _ in touchUpdatedAt() }
        .onChange(of: itemSet.sellTogetherPreferenceRaw) { _, _ in touchUpdatedAt() }
        .onChange(of: itemSet.completenessRaw) { _, _ in touchUpdatedAt() }
    }

    // MARK: - Member Row

    @ViewBuilder
    private func memberRow(item: LTCItem, membership: LTCItemSetMembership) -> some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail(for: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(Theme.sectionHeaderFont)
                    .foregroundStyle(Theme.text)

                let qty = membership.quantityInSet ?? item.quantity
                let total = item.value * Double(max(1, qty))

                Text("\(item.category) • Qty \(max(1, qty))")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)

                if item.value > 0 {
                    Text(total, format: .currency(code: currencyCode))
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
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

    private func touchUpdatedAt() {
        itemSet.updatedAt = .now
    }
}
