//
//  YourBeneficiariesView.swift
//  LegacyTreasureChest
//
//  Top-level overview of all beneficiaries for the current user,
//  with per-beneficiary item counts and total assigned value.
//  Also surfaces items that have not yet been assigned to anyone.
//

import SwiftUI
import SwiftData
import Contacts

struct YourBeneficiariesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Beneficiary.createdAt, order: .forward)
    private var beneficiaries: [Beneficiary]

    @Query(sort: \LTCItem.createdAt, order: .forward)
    private var items: [LTCItem]

    // Alerts & sheets
    @State private var deletionErrorMessage: String?
    @State private var isPresentingAddBeneficiary: Bool = false
    @State private var isShowingContactPicker: Bool = false

    // Currency code based on current locale, defaulting to USD.
    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    // Items that have no ItemBeneficiary links yet.
    private var unassignedItems: [LTCItem] {
        items.filter { $0.itemBeneficiaries.isEmpty }
    }

    var body: some View {
        List {
            beneficiariesSection

            if !unassignedItems.isEmpty {
                unassignedItemsSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Beneficiaries")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isShowingContactPicker = true
                    } label: {
                        Label("Add from Contacts", systemImage: "person.fill.badge.plus")
                    }

                    Button {
                        isPresentingAddBeneficiary = true
                    } label: {
                        Label("Add Manually", systemImage: "square.and.pencil")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Beneficiary")
            }
        }
        // Manual add sheet
        .sheet(isPresented: $isPresentingAddBeneficiary) {
            BeneficiaryFormSheet()
        }
        // Contacts picker sheet (top-level, not nested)
        .sheet(isPresented: $isShowingContactPicker) {
            ContactPickerView(
                onSelect: { contact in
                    addBeneficiary(from: contact)
                    isShowingContactPicker = false
                },
                onCancel: {
                    isShowingContactPicker = false
                }
            )
        }
        .alert(
            "Cannot Delete Beneficiary",
            isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { if !$0 { deletionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deletionErrorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var beneficiariesSection: some View {
        Group {
            if beneficiaries.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("No beneficiaries yet")
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.text)

                        Text("Start by adding beneficiaries from your Contacts or manually. Then you can assign items to each person as part of your legacy plan.")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, Theme.spacing.small)
                } header: {
                    Text("Your Beneficiaries")
                        .ltcSectionHeaderStyle()
                }
            } else {
                Section {
                    ForEach(beneficiaries) { beneficiary in
                        NavigationLink {
                            BeneficiaryDetailView(beneficiary: beneficiary)
                        } label: {
                            beneficiaryRow(for: beneficiary)
                        }
                        .swipeActions(edge: .trailing) {
                            if beneficiary.itemLinks.isEmpty {
                                // Safe to delete: no assigned items
                                Button(role: .destructive) {
                                    deleteBeneficiary(beneficiary)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(Theme.destructive)
                            } else {
                                // Has assigned items – explain why we can’t delete
                                Button {
                                    let name = beneficiary.name.isEmpty ? "this beneficiary" : beneficiary.name
                                    deletionErrorMessage = "\(name) still has assigned items. Remove those item assignments before deleting."
                                } label: {
                                    Label("Has Items", systemImage: "exclamationmark.triangle")
                                }
                                .tint(.gray)
                            }
                        }
                    }
                } header: {
                    Text("Your Beneficiaries")
                        .ltcSectionHeaderStyle()
                } footer: {
                    Text("Totals here use the current estimated value for each assigned item.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var unassignedItemsSection: some View {
        Section {
            ForEach(unassignedItems) { item in
                NavigationLink {
                    ItemDetailView(item: item)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.text)

                            Text(item.category)
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()

                        if item.value > 0 {
                            CurrencyText.view(item.value)                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
            }
        } header: {
            Text("Unassigned Items")
                .ltcSectionHeaderStyle()
        } footer: {
            Text("These items don’t have a beneficiary yet. Open an item to choose who should receive it as part of your legacy.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Row Builders

    private func beneficiaryRow(for beneficiary: Beneficiary) -> some View {
        let itemCount = beneficiary.itemLinks.count
        let totalValue = totalValueForBeneficiary(beneficiary)

        return HStack(spacing: Theme.spacing.medium) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 24))
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(beneficiary.name)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.text)

                if !beneficiary.relationship.isEmpty {
                    Text(beneficiary.relationship)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                if beneficiary.isLinkedToContact {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)

                        Text("From Contacts")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                HStack(spacing: Theme.spacing.small) {
                    if itemCount > 0 {
                        Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if totalValue > 0 {
                        CurrencyText.view(totalValue)                            .font(Theme.secondaryFont.weight(.semibold))
                            .foregroundStyle(Theme.text)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func totalValueForBeneficiary(_ beneficiary: Beneficiary) -> Double {
        beneficiary.itemLinks
            .compactMap { $0.item?.value }
            .reduce(0, +)
    }

    private func deleteBeneficiary(_ beneficiary: Beneficiary) {
        guard beneficiary.itemLinks.isEmpty else {
            let name = beneficiary.name.isEmpty ? "this beneficiary" : beneficiary.name
            deletionErrorMessage = "\(name) still has assigned items. Remove those item assignments before deleting."
            return
        }

        modelContext.delete(beneficiary)
    }

    // MARK: - Contacts → Beneficiary (with dedupe / merge)

    private func addBeneficiary(from contact: CNContact) {
        // 1) If we already have a beneficiary linked to this contact, update it and return.
        if let existingByContact = beneficiaries.first(where: { $0.contactIdentifier == contact.identifier }) {
            applyContact(contact, to: existingByContact)
            return
        }

        // Build a reasonable full name.
        let fullName: String
        if !contact.givenName.isEmpty || !contact.familyName.isEmpty {
            fullName = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } else if !contact.organizationName.isEmpty {
            fullName = contact.organizationName
        } else {
            fullName = "Unnamed Contact"
        }

        let normalizedFullName = fullName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // First email & phone, if any.
        let email: String? = contact.emailAddresses.first?.value as String?
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let phone: String? = contact.phoneNumbers.first?.value.stringValue

        // 2) Try to find an existing beneficiary by name or email.
        if let existingByNameOrEmail = beneficiaries.first(where: { existing in
            let existingName = existing.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let existingEmail = existing.email?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let nameMatches = !normalizedFullName.isEmpty && existingName == normalizedFullName
            let emailMatches = if let normalizedEmail {
                existingEmail == normalizedEmail
            } else {
                false
            }

            return nameMatches || emailMatches
        }) {
            // Merge: link the existing beneficiary to this contact,
            // and fill in any missing email/phone.
            applyContact(
                contact,
                to: existingByNameOrEmail,
                overrideName: false // keep user's name if they customized it
            )
            return
        }

        // 3) No existing match – create a brand new beneficiary.
        let newBeneficiary = Beneficiary(
            name: fullName,
            relationship: "", // user can fill in later via Edit
            email: email,
            phoneNumber: phone,
            contactIdentifier: contact.identifier,
            isLinkedToContact: true
        )

        modelContext.insert(newBeneficiary)
    }

    /// Applies contact details to an existing beneficiary, linking it to Contacts.
    private func applyContact(
        _ contact: CNContact,
        to beneficiary: Beneficiary,
        overrideName: Bool = true
    ) {
        // Build full name from contact.
        let fullName: String
        if !contact.givenName.isEmpty || !contact.familyName.isEmpty {
            fullName = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } else if !contact.organizationName.isEmpty {
            fullName = contact.organizationName
        } else {
            fullName = beneficiary.name
        }

        if overrideName {
            beneficiary.name = fullName
        }

        let email: String? = contact.emailAddresses.first?.value as String?
        let phone: String? = contact.phoneNumbers.first?.value.stringValue

        // Only overwrite email/phone if they are currently empty.
        if (beneficiary.email == nil || beneficiary.email?.isEmpty == true),
           let email, !email.isEmpty {
            beneficiary.email = email
        }

        if (beneficiary.phoneNumber == nil || beneficiary.phoneNumber?.isEmpty == true),
           let phone, !phone.isEmpty {
            beneficiary.phoneNumber = phone
        }

        beneficiary.contactIdentifier = contact.identifier
        beneficiary.isLinkedToContact = true
        beneficiary.updatedAt = .now
    }
}

// MARK: - Preview

private let yourBeneficiariesPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self, ItemBeneficiary.self, Beneficiary.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    // Sample items
    let camera = LTCItem(
        name: "Vintage Camera",
        itemDescription: "Grandpa's old camera.",
        category: "Collectibles",
        value: 250
    )

    let rug = LTCItem(
        name: "Persian Rug",
        itemDescription: "Living room rug.",
        category: "Rug",
        value: 1200
    )

    let painting = LTCItem(
        name: "Landscape Painting",
        itemDescription: "Oil painting of a mountain landscape.",
        category: "Art",
        value: 800
    )

    // Beneficiaries
    let alex = Beneficiary(
        name: "Alex Johnson",
        relationship: "Daughter",
        email: "alex@example.com",
        contactIdentifier: "CONTACT-ALEX",
        isLinkedToContact: true
    )

    let michael = Beneficiary(
        name: "Michael Smith",
        relationship: "Son",
        email: "michael@example.com"
    )

    // Links
    let link1 = ItemBeneficiary(accessPermission: .immediate)
    link1.item = camera
    link1.beneficiary = alex

    let link2 = ItemBeneficiary(accessPermission: .uponPassing)
    link2.item = rug
    link2.beneficiary = alex

    let link3 = ItemBeneficiary(accessPermission: .afterSpecificDate)
    link3.item = painting
    link3.beneficiary = michael

    context.insert(camera)
    context.insert(rug)
    context.insert(painting)
    context.insert(alex)
    context.insert(michael)
    context.insert(link1)
    context.insert(link2)
    context.insert(link3)

    return container
}()

#Preview("Your Beneficiaries") {
    NavigationStack {
        YourBeneficiariesView()
    }
    .modelContainer(yourBeneficiariesPreviewContainer)
}
