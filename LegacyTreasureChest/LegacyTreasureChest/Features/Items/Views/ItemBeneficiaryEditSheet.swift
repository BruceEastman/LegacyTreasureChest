//
//  ItemBeneficiaryEditSheet.swift
//  LegacyTreasureChest
//
//  Editor for a single ItemBeneficiary link.
//  Allows updating access permission, optional date, and a personal message.
//

import SwiftUI
import SwiftData

struct ItemBeneficiaryEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var link: ItemBeneficiary

    @State private var permission: AccessPermission
    @State private var accessDate: Date
    @State private var message: String

    init(link: ItemBeneficiary) {
        self._link = Bindable(wrappedValue: link)
        _permission = State(initialValue: link.accessPermission)
        _accessDate = State(initialValue: link.accessDate ?? .now)
        _message = State(initialValue: link.personalMessage ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                // Access rules
                Section {
                    Picker("Access Permission", selection: $permission) {
                        ForEach(AccessPermission.allCases, id: \.self) { option in
                            Text(label(for: option))
                                .font(Theme.bodyFont)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if permission == .afterSpecificDate {
                        DatePicker(
                            "Access Date",
                            selection: $accessDate,
                            displayedComponents: .date
                        )
                        .font(Theme.bodyFont)
                    }
                } header: {
                    Text("Access")
                        .ltcSectionHeaderStyle()
                } footer: {
                    Text(accessHelpText)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Personal message
                Section {
                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("Message to Beneficiary")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Theme.text)

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.systemBackground))
                                .shadow(radius: 1)

                            TextEditor(text: $message)
                                .padding(Theme.spacing.small)
                                .font(Theme.bodyFont)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                        }
                        .frame(minHeight: 120)
                    }
                    .padding(.vertical, Theme.spacing.small)
                } footer: {
                    Text("This note is saved with this item and beneficiary and can be included in future notifications.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Notification status (read-only for now)
                Section {
                    HStack {
                        Text("Notification Status")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Theme.text)

                        Spacer()

                        Text(notificationLabel(for: link.notificationStatus))
                            .font(Theme.secondaryFont)
                            .padding(.horizontal, Theme.spacing.small)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(notificationBackground(for: link.notificationStatus))
                            )
                            .foregroundStyle(notificationForeground(for: link.notificationStatus))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Edit Beneficiary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        applyChangesAndDismiss()
                    }
                    .font(Theme.bodyFont)
                }
            }
            .tint(Theme.accent)
        }
    }

    // MARK: - Helpers

    private func applyChangesAndDismiss() {
        // Access rules
        link.accessPermission = permission

        if permission == .afterSpecificDate {
            link.accessDate = accessDate
        } else {
            link.accessDate = nil
        }

        // Message
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        link.personalMessage = trimmed.isEmpty ? nil : trimmed

        dismiss()
    }

    private func label(for permission: AccessPermission) -> String {
        switch permission {
        case .immediate:
            return "Immediate"
        case .afterSpecificDate:
            return "After Date"
        case .uponPassing:
            return "Upon Passing"
        }
    }

    private var accessHelpText: String {
        switch permission {
        case .immediate:
            return "The beneficiary can access this item as soon as your plan is shared with them."
        case .afterSpecificDate:
            return "Choose a date when this beneficiary should be allowed to access this item."
        case .uponPassing:
            return "This item is only available to the beneficiary as part of your estate after your passing."
        }
    }

    private func notificationLabel(for status: NotificationStatus) -> String {
        switch status {
        case .notSent: return "Not Sent"
        case .sent: return "Sent"
        case .accepted: return "Accepted"
        }
    }

    private func notificationForeground(for status: NotificationStatus) -> Color {
        switch status {
        case .notSent: return Theme.textSecondary
        case .sent: return Theme.accent
        case .accepted: return Theme.text
        }
    }

    private func notificationBackground(for status: NotificationStatus) -> Color {
        switch status {
        case .notSent: return Theme.background.opacity(0.7)
        case .sent: return Theme.accent.opacity(0.12)
        case .accepted: return Theme.primary.opacity(0.12)
        }
    }
}

// MARK: - Preview

private let editSheetPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self, ItemBeneficiary.self, Beneficiary.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    let item = LTCItem(
        name: "Preview Item",
        itemDescription: "Preview for editing ItemBeneficiary.",
        category: "Art",
        value: 100
    )

    let beneficiary = Beneficiary(
        name: "Alex Johnson",
        relationship: "Daughter",
        email: "alex@example.com"
    )

    let link = ItemBeneficiary(
        accessPermission: .afterSpecificDate,
        accessDate: Calendar.current.date(byAdding: .year, value: 1, to: .now),
        personalMessage: "This painting has always reminded me of you.",
        notificationStatus: .notSent
    )

    link.item = item
    link.beneficiary = beneficiary

    context.insert(item)
    context.insert(beneficiary)
    context.insert(link)

    return container
}()

#Preview("Item Beneficiary Edit Sheet") {
    let container = editSheetPreviewContainer
    let context = ModelContext(container)

    let descriptor = FetchDescriptor<ItemBeneficiary>()
    let links = (try? context.fetch(descriptor)) ?? []

    return NavigationStack {
        if let first = links.first {
            ItemBeneficiaryEditSheet(link: first)
        } else {
            Text("No link")
        }
    }
    .modelContainer(container)
}
