//
//  ItemBeneficiariesSection.swift
//  LegacyTreasureChest
//
//  Placeholder section for beneficiaries linked to this item.
//  UI only for now – no real selection or notifications yet.
//  Later we’ll hook this up to Beneficiary and ItemBeneficiary records.
//

import SwiftUI
import SwiftData

struct ItemBeneficiariesSection: View {
    @Bindable var item: LTCItem

    private var beneficiaryNames: [String] {
        item.itemBeneficiaries
            .compactMap { $0.beneficiary?.name }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        Section(header: Text("Beneficiaries")) {
            if item.itemBeneficiaries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3")
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        Text("Choose who should receive this item as part of your legacy.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        // Placeholder – will be wired to a beneficiary picker/editor in a future update.
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Beneficiary")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .opacity(0.6)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This item is linked to:")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    if beneficiaryNames.isEmpty {
                        Text("\(item.itemBeneficiaries.count) beneficiary link(s)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(beneficiaryNames, id: \.self) { name in
                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.circle")
                                    .foregroundStyle(.secondary)
                                Text(name)
                                    .font(.subheadline)
                            }
                        }
                    }

                    Text("A full beneficiary picker and notification flow will be added in a future update.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Preview

private let itemBeneficiariesPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    let sample = LTCItem(
        name: "Preview Item with Beneficiaries",
        itemDescription: "This is a preview item for the beneficiaries section.",
        category: "Jewelry",
        value: 0
    )

    context.insert(sample)

    return container
}()

#Preview("Item Beneficiaries Section – Empty") {
    let container = itemBeneficiariesPreviewContainer
    let context = ModelContext(container)

    let descriptor = FetchDescriptor<LTCItem>()
    let items = (try? context.fetch(descriptor)) ?? []

    return NavigationStack {
        if let first = items.first {
            Form {
                ItemBeneficiariesSection(item: first)
            }
        } else {
            Text("No preview item")
        }
    }
    .modelContainer(container)
}
