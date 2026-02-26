//
//  BeneficiaryDetailView.swift
//  LegacyTreasureChest
//
//  Detail view for a single Beneficiary.
//  Shows contact info, total assigned value, and a list of items
//  linked via ItemBeneficiary.
//

import SwiftUI
import SwiftData

struct BeneficiaryDetailView: View {
    @Bindable var beneficiary: Beneficiary

    @State private var isEditing: Bool = false

    // Currency code based on current locale, defaulting to USD.
    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    // All ItemBeneficiary links for this beneficiary, sorted by creation date.
    private var links: [ItemBeneficiary] {
        beneficiary.itemLinks
            .sorted { $0.createdAt < $1.createdAt }
    }

    // Total value of assigned items, based on each item's current value.
    private var totalValue: Double {
        links
            .compactMap { $0.item?.value }
            .reduce(0, +)
    }

    var body: some View {
        List {
            beneficiaryHeaderSection
            exportSection
            assignedItemsSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Beneficiary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditing) {
            BeneficiaryEditSheet(beneficiary: beneficiary)
        }
    }

    // MARK: - Sections

    private var beneficiaryHeaderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                // Name + relationship
                Text(beneficiary.name)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)

                if !beneficiary.relationship.isEmpty {
                    Text(beneficiary.relationship)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Contacts link indicator (subtle, consistent with list row)
                if beneficiary.isLinkedToContact {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)

                        Text("Linked to Contacts")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                // Email / phone
                if let email = beneficiary.email, !email.isEmpty {
                    Text(email)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let phone = beneficiary.phoneNumber, !phone.isEmpty {
                    Text(phone)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Total value summary
                if totalValue > 0 {
                    Divider()
                        .padding(.vertical, Theme.spacing.small)

                    HStack {
                        Text("Total Assigned Value")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        CurrencyText.view(totalValue)                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.text)
                    }
                }

                // Edit button – clearly about the Beneficiary, not items.
                Button {
                    isEditing = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text("Edit Beneficiary")
                            .font(Theme.bodyFont.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .padding(.top, Theme.spacing.medium)
            }
            .padding(.vertical, Theme.spacing.small)
        } header: {
            Text("Beneficiary")
                .ltcSectionHeaderStyle()
        }
    }
    
    private var exportSection: some View {
        Section {
            let itemsForExport = links.compactMap { $0.item }
            NavigationLink {
                BeneficiaryPacketExportView(
                    preset: .beneficiary(
                        name: beneficiary.name,   // assumes Beneficiary has `name`
                        items: itemsForExport
                    )
                )
            } label: {
                HStack(spacing: Theme.spacing.small) {
                    Image(systemName: "archivebox")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Beneficiary Packet")
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text("ZIP bundle for this beneficiary (PDF + optional media)")
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
            .disabled(itemsForExport.isEmpty)
        } header: {
            Text("Export")
                .ltcSectionHeaderStyle()
        }
    }

    private var assignedItemsSection: some View {
        Section {
            if links.isEmpty {
                Text("No items have been assigned to this beneficiary yet.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, Theme.spacing.small)
            } else {
                ForEach(links) { link in
                    if let item = link.item {
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            itemRow(for: item, link: link)
                        }
                    }
                }
            }
        } header: {
            Text("Assigned Items")
                .ltcSectionHeaderStyle()
        }
    }

    // MARK: - Row Builders

    private func itemRow(for item: LTCItem, link: ItemBeneficiary) -> some View {
        HStack(spacing: Theme.spacing.medium) {
            // Thumbnail: first image if available, otherwise a placeholder.
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
                        Image(systemName: "photo")
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

                HStack(spacing: Theme.spacing.small) {
                    if item.value > 0 {
                        CurrencyText.view(item.value)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.text)
                    }

                    Text(permissionSummary(for: link))
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func permissionSummary(for link: ItemBeneficiary) -> String {
        switch link.accessPermission {
        case .immediate:
            return "Immediate access"
        case .afterSpecificDate:
            if let date = link.accessDate {
                let formatted = date.formatted(date: .abbreviated, time: .omitted)
                return "Access after \(formatted)"
            } else {
                return "Access after specific date"
            }
        case .uponPassing:
            return "Access upon passing"
        }
    }
}

// MARK: - Preview

private let beneficiaryDetailPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self, ItemBeneficiary.self, Beneficiary.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    let item1 = LTCItem(
        name: "Diamond Necklace",
        itemDescription: "Family heirloom necklace.",
        category: "Jewelry",
        value: 5000
    )

    let item2 = LTCItem(
        name: "Oil Painting",
        itemDescription: "Landscape painting from the living room.",
        category: "Art",
        value: 1500
    )

    let beneficiary = Beneficiary(
        name: "Kate Bell",
        relationship: "",
        email: "kate-bell@mac.com",
        phoneNumber: "555-564-8583",
        contactIdentifier: "CONTACT-KATE",
        isLinkedToContact: true
    )

    let link1 = ItemBeneficiary(
        accessPermission: .immediate,
        personalMessage: "You’ve always loved this piece."
    )
    link1.item = item1
    link1.beneficiary = beneficiary

    let link2 = ItemBeneficiary(
        accessPermission: .uponPassing,
        personalMessage: nil
    )
    link2.item = item2
    link2.beneficiary = beneficiary

    context.insert(item1)
    context.insert(item2)
    context.insert(beneficiary)
    context.insert(link1)
    context.insert(link2)

    return container
}()

#Preview("Beneficiary Detail") {
    let container = beneficiaryDetailPreviewContainer
    let context = ModelContext(container)

    let descriptor = FetchDescriptor<Beneficiary>()
    let beneficiaries = (try? context.fetch(descriptor)) ?? []

    return NavigationStack {
        if let first = beneficiaries.first {
            BeneficiaryDetailView(beneficiary: first)
        } else {
            Text("No beneficiary")
        }
    }
    .modelContainer(container)
}
