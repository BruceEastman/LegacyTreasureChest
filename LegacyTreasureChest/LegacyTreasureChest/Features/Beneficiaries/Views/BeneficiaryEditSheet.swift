//
//  BeneficiaryEditSheet.swift
//  LegacyTreasureChest
//
//  Edit form for an existing Beneficiary.
//  Now supports linking to / updating from Contacts.
//

import SwiftUI
import SwiftData
import Contacts

struct BeneficiaryEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var beneficiary: Beneficiary

    @State private var name: String
    @State private var relationship: String
    @State private var email: String
    @State private var phone: String

    // Contacts linkage
    @State private var contactIdentifier: String?
    @State private var isLinkedToContact: Bool
    @State private var isShowingContactPicker: Bool = false

    // Simple validation: require a name.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(beneficiary: Beneficiary) {
        self._beneficiary = Bindable(wrappedValue: beneficiary)

        _name = State(initialValue: beneficiary.name)
        _relationship = State(initialValue: beneficiary.relationship)
        _email = State(initialValue: beneficiary.email ?? "")
        _phone = State(initialValue: beneficiary.phoneNumber ?? "")

        _contactIdentifier = State(initialValue: beneficiary.contactIdentifier)
        _isLinkedToContact = State(initialValue: beneficiary.isLinkedToContact)
    }

    var body: some View {
        NavigationStack {
            Form {
                // CONTACT LINK
                Section {
                    Button {
                        isShowingContactPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.plus")
                            Text(isLinkedToContact ? "Update from Contacts" : "Link to Contacts")
                                .font(Theme.bodyFont)
                            Spacer()
                            if isLinkedToContact {
                                Text("Linked")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                } footer: {
                    Text("Link this beneficiary to an entry in your Contacts. You can refresh their details from Contacts at any time.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                // DETAILS
                Section {
                    TextField("Full Name", text: $name)
                        .font(Theme.bodyFont)
                        .textInputAutocapitalization(.words)

                    TextField("Relationship (e.g., Daughter)", text: $relationship)
                        .font(Theme.bodyFont)

                    TextField("Email (optional)", text: $email)
                        .font(Theme.bodyFont)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)

                    TextField("Phone (optional)", text: $phone)
                        .font(Theme.bodyFont)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Edit Beneficiary")
                        .ltcSectionHeaderStyle()
                } footer: {
                    Text("Changes will update this person everywhere they appear in your legacy plan.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Edit Beneficiary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(Theme.bodyFont)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        applyChangesAndDismiss()
                    }
                    .disabled(!canSave)
                    .font(Theme.bodyFont.weight(.semibold))
                }
            }
            .tint(Theme.accent)
            .sheet(isPresented: $isShowingContactPicker) {
                ContactPickerView(
                    onSelect: { contact in
                        applyContact(contact)
                        isShowingContactPicker = false
                    },
                    onCancel: {
                        isShowingContactPicker = false
                    }
                )
            }
        }
    }

    // MARK: - Actions

    private func applyChangesAndDismiss() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let trimmedRelationship = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        beneficiary.name = trimmedName
        beneficiary.relationship = trimmedRelationship
        beneficiary.email = trimmedEmail.isEmpty ? nil : trimmedEmail
        beneficiary.phoneNumber = trimmedPhone.isEmpty ? nil : trimmedPhone

        beneficiary.contactIdentifier = contactIdentifier
        beneficiary.isLinkedToContact = contactIdentifier != nil

        beneficiary.updatedAt = .now

        dismiss()
    }

    private func applyContact(_ contact: CNContact) {
        // Name: prefer given + family; fall back to organization if needed.
        let fullName: String
        if !contact.givenName.isEmpty || !contact.familyName.isEmpty {
            fullName = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } else if !contact.organizationName.isEmpty {
            fullName = contact.organizationName
        } else {
            fullName = name // keep whatever was there
        }

        name = fullName

        // Email: use first email if available.
        if let firstEmail = contact.emailAddresses.first?.value as String? {
            email = firstEmail
        }

        // Phone: use first phone if available.
        if let firstPhone = contact.phoneNumbers.first?.value.stringValue {
            phone = firstPhone
        }

        contactIdentifier = contact.identifier
        isLinkedToContact = true
    }
}

// MARK: - Preview

private let beneficiaryEditPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: Beneficiary.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    let sample = Beneficiary(
        name: "Alex Johnson",
        relationship: "Daughter",
        email: "alex@example.com",
        phoneNumber: "555-123-4567",
        contactIdentifier: "SAMPLE-CONTACT-ID",
        isLinkedToContact: true
    )

    context.insert(sample)

    return container
}()

#Preview("Edit Beneficiary Sheet") {
    let container = beneficiaryEditPreviewContainer
    let context = ModelContext(container)

    let descriptor = FetchDescriptor<Beneficiary>()
    let beneficiaries = (try? context.fetch(descriptor)) ?? []

    return NavigationStack {
        if let first = beneficiaries.first {
            BeneficiaryEditSheet(beneficiary: first)
        } else {
            Text("No beneficiary")
        }
    }
    .modelContainer(container)
}
