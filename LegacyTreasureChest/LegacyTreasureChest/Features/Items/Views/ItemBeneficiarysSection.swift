//
//  ItemBeneficiariesSection.swift
//  LegacyTreasureChest
//
//  Beneficiaries linked to this item.
//  Theme-based and callback-driven; the parent view owns presentation
//  (sheets, editors, etc.).
//

import SwiftUI
import SwiftData

struct ItemBeneficiariesSection: View {
    @Bindable var item: LTCItem

    /// Called when the user taps "Add Beneficiary".
    var onAddTapped: () -> Void

    /// Called when the user taps an existing link row to edit it.
    var onEditLink: (ItemBeneficiary) -> Void

    /// Called when the user confirms removal of a link.
    var onRemoveLink: (ItemBeneficiary) -> Void

    // MARK: - Derived Data

    private var links: [ItemBeneficiary] {
        item.itemBeneficiaries
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Section {
            if links.isEmpty {
                emptyStateView
            } else {
                linksListView
            }
        } header: {
            Text("Beneficiaries")
                .ltcSectionHeaderStyle()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            HStack(spacing: Theme.spacing.medium) {
                Image(systemName: "person.3")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                Text("Choose who should receive this item as part of your legacy.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button(action: onAddTapped) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Beneficiary")
                        .font(Theme.bodyFont)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, Theme.spacing.small)
        }
        .padding(.vertical, Theme.spacing.small)
    }

    // MARK: - Populated State

    private var linksListView: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            ForEach(links) { link in
                linkRow(for: link)
            }

            Text("You can adjust when each beneficiary can access this item and add a personal message.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, Theme.spacing.small)
        }
        .padding(.vertical, Theme.spacing.small)
    }

    private func linkRow(for link: ItemBeneficiary) -> some View {
        let name = link.beneficiary?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let relationship = link.beneficiary?.relationship.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(alignment: .top, spacing: Theme.spacing.medium) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 24))
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                if let name, !name.isEmpty {
                    Text(name)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.text)
                } else {
                    Text("Unnamed Beneficiary")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textSecondary)
                        .italic()
                }

                if let relationship, !relationship.isEmpty {
                    Text(relationship)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: Theme.spacing.small) {
                    Text(permissionSummary(for: link))
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)

                    Spacer(minLength: Theme.spacing.small)

                    notificationBadge(for: link)
                }
                .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onEditLink(link)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onRemoveLink(link)
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .tint(Theme.destructive)
        }
    }

    // MARK: - Helpers

    private func permissionSummary(for link: ItemBeneficiary) -> String {
        switch link.accessPermission {
        case .immediate:
            return "Access: Immediate"
        case .afterSpecificDate:
            if let date = link.accessDate {
                let formatted = date.formatted(date: .abbreviated, time: .omitted)
                return "Access after \(formatted)"
            } else {
                return "Access after a specific date"
            }
        case .uponPassing:
            return "Access upon passing"
        }
    }

    private func notificationBadge(for link: ItemBeneficiary) -> some View {
        let text: String
        let foreground: Color
        let background: Color

        switch link.notificationStatus {
        case .notSent:
            text = "Not Sent"
            foreground = Theme.textSecondary
            background = Theme.background.opacity(0.7)
        case .sent:
            text = "Sent"
            foreground = Theme.accent
            background = Theme.accent.opacity(0.12)
        case .accepted:
            text = "Accepted"
            foreground = Theme.text
            background = Theme.primary.opacity(0.12)
        }

        return Text(text)
            .font(Theme.secondaryFont)
            .padding(.horizontal, Theme.spacing.small)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(background)
            )
            .foregroundStyle(foreground)
    }
}

// MARK: - Beneficiary Picker / Creator Sheet

struct BeneficiaryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var item: LTCItem
    var user: LTCUser?

    @State private var newName: String = ""
    @State private var newRelationship: String = ""
    @State private var newEmail: String = ""
    @State private var newPhone: String = ""

    private var existingBeneficiaries: [Beneficiary] {
        (user?.beneficiaries ?? [])
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !existingBeneficiaries.isEmpty {
                    Section {
                        ForEach(existingBeneficiaries) { beneficiary in
                            Button {
                                attachExisting(beneficiary)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(beneficiary.name)
                                            .font(Theme.bodyFont)
                                            .foregroundStyle(Theme.text)

                                        if !beneficiary.relationship.isEmpty {
                                            Text(beneficiary.relationship)
                                                .font(Theme.secondaryFont)
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    } header: {
                        Text("Your Beneficiaries")
                            .ltcSectionHeaderStyle()
                    }
                }

                Section {
                    TextField("Full Name", text: $newName)
                        .font(Theme.bodyFont)

                    TextField("Relationship (e.g., Daughter)", text: $newRelationship)
                        .font(Theme.bodyFont)

                    TextField("Email (optional)", text: $newEmail)
                        .font(Theme.bodyFont)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)

                    TextField("Phone (optional)", text: $newPhone)
                        .font(Theme.bodyFont)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Add New Beneficiary")
                        .ltcSectionHeaderStyle()
                } footer: {
                    Text("This person will be available to link to other items in your legacy plan.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                Section {
                    Button {
                        createAndAttachNewBeneficiary()
                    } label: {
                        Text("Save & Attach to This Item")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Select Beneficiary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .tint(Theme.accent)
        }
    }

    // MARK: - Actions

    private func attachExisting(_ beneficiary: Beneficiary) {
        let link = ItemBeneficiary(
            accessPermission: .immediate,
            accessDate: nil,
            personalMessage: nil,
            notificationStatus: .notSent
        )
        link.item = item
        link.beneficiary = beneficiary
        item.itemBeneficiaries.append(link)
        dismiss()
    }

    private func createAndAttachNewBeneficiary() {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let beneficiary = Beneficiary(
            name: trimmedName,
            relationship: newRelationship.trimmingCharacters(in: .whitespacesAndNewlines),
            email: newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newEmail,
            phoneNumber: newPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newPhone
        )

        // Associate with the owning user if available so they show up in future lists.
        if let user {
            beneficiary.user = user
            user.beneficiaries.append(beneficiary)
        }

        attachExisting(beneficiary)
    }
}

// MARK: - Preview

private let itemBeneficiariesPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self, ItemBeneficiary.self, Beneficiary.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    let sampleItem = LTCItem(
        name: "Preview Item with Beneficiaries",
        itemDescription: "This is a preview item for the beneficiaries section.",
        category: "Jewelry",
        value: 0
    )

    let beneficiary1 = Beneficiary(
        name: "Alex Johnson",
        relationship: "Daughter",
        email: "alex@example.com"
    )

    let beneficiary2 = Beneficiary(
        name: "Michael Smith",
        relationship: "Son",
        email: "michael@example.com"
    )

    let link1 = ItemBeneficiary(
        accessPermission: .immediate,
        personalMessage: "You’ve always cherished this piece."
    )
    link1.item = sampleItem
    link1.beneficiary = beneficiary1

    let link2 = ItemBeneficiary(
        accessPermission: .afterSpecificDate,
        accessDate: Calendar.current.date(byAdding: .year, value: 5, to: .now),
        personalMessage: nil,
        notificationStatus: .sent
    )
    link2.item = sampleItem
    link2.beneficiary = beneficiary2

    sampleItem.itemBeneficiaries = [link1, link2]

    context.insert(sampleItem)
    context.insert(beneficiary1)
    context.insert(beneficiary2)

    return container
}()

#Preview("Item Beneficiaries Section") {
    let container = itemBeneficiariesPreviewContainer
    let context = ModelContext(container)

    let descriptor = FetchDescriptor<LTCItem>()
    let items = (try? context.fetch(descriptor)) ?? []

    return NavigationStack {
        if let first = items.first {
            Form {
                ItemBeneficiariesSection(
                    item: first,
                    onAddTapped: {},
                    onEditLink: { _ in },
                    onRemoveLink: { _ in }
                )
            }
        } else {
            Text("No preview item")
        }
    }
    .modelContainer(container)
}
