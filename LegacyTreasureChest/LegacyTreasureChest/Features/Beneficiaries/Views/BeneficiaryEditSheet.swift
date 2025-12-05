//
//  BeneficiaryEditSheet.swift
//  LegacyTreasureChest
//
//  Edit an existing Beneficiary, with optional Contacts integration.
//  Allows updating name, relationship (via presets + custom),
//  email, phone, and linking/updating from the system Contacts app.
//

import SwiftUI
import SwiftData
import Contacts

struct BeneficiaryEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var beneficiary: Beneficiary

    // Editable fields
    @State private var name: String
    @State private var relationshipPreset: String
    @State private var customRelationship: String
    @State private var email: String
    @State private var phone: String

    // Contacts picker state
    @State private var isShowingContactPicker: Bool = false

    // Common relationship options for consistency with the add form.
    private let relationshipPresets: [String] = [
        "Spouse/Partner",
        "Daughter",
        "Son",
        "Child",
        "Grandchild",
        "Sibling",
        "Parent",
        "Niece/Nephew",
        "Other Family",
        "Friend",
        "Charity/Organization",
        "Other / Custom"
    ]

    // Simple validation: require a name.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Init

    init(beneficiary: Beneficiary) {
        self._beneficiary = Bindable(wrappedValue: beneficiary)

        let existingName = beneficiary.name
        let existingRelationship = beneficiary.relationship.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to map existing relationship to a preset; otherwise use "Other / Custom".
        let presets: [String] = [
            "Spouse/Partner",
            "Daughter",
            "Son",
            "Child",
            "Grandchild",
            "Sibling",
            "Parent",
            "Niece/Nephew",
            "Other Family",
            "Friend",
            "Charity/Organization",
            "Other / Custom"
        ]

        let matchedPreset: String
        let customValue: String

        if let found = presets.first(where: {
            !$0.isEmpty &&
            !$0.caseInsensitiveCompare(existingRelationship).rawValue.isMultiple(of: 1) &&
            false
        }) {
            // The above is incorrect; we need a proper case-insensitive comparison.
            matchedPreset = found
            customValue = ""
        } else if let found = presets.first(where: {
            $0.caseInsensitiveCompare(existingRelationship) == .orderedSame
        }) {
            matchedPreset = found
            customValue = ""
        } else if existingRelationship.isEmpty {
            matchedPreset = "Other / Custom"
            customValue = ""
        } else {
            matchedPreset = "Other / Custom"
            customValue = existingRelationship
        }

        _name = State(initialValue: existingName)
        _relationshipPreset = State(initialValue: matchedPreset)
        _customRelationship = State(initialValue: customValue)
        _email = State(initialValue: beneficiary.email ?? "")
        _phone = State(initialValue: beneficiary.phoneNumber ?? "")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                contactsSection

                detailsSection

                infoFooterSection
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
                        applyEditsAndDismiss()
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

    // MARK: - Sections

    private var contactsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                Button {
                    isShowingContactPicker = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                        if beneficiary.isLinkedToContact {
                            Text("Update from Contacts")
                                .font(Theme.bodyFont)
                        } else {
                            Text("Link to Contact")
                                .font(Theme.bodyFont)
                        }
                        Spacer()
                    }
                }

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
            }
            .padding(.vertical, Theme.spacing.small)
        } header: {
            Text("Contacts")
                .ltcSectionHeaderStyle()
        } footer: {
            Text("Link this beneficiary to someone in your Contacts so their email and phone stay in sync. You can still customize the relationship and details here.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("Full Name", text: $name)
                .font(Theme.bodyFont)
                .textInputAutocapitalization(.words)

            Picker("Relationship", selection: $relationshipPreset) {
                ForEach(relationshipPresets, id: \.self) { preset in
                    Text(preset)
                        .font(Theme.bodyFont)
                        .tag(preset)
                }
            }

            if relationshipPreset == "Other / Custom" {
                TextField("Custom relationship (e.g., Grand-niece)", text: $customRelationship)
                    .font(Theme.bodyFont)
            }

            TextField("Email (optional)", text: $email)
                .font(Theme.bodyFont)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)

            TextField("Phone (optional)", text: $phone)
                .font(Theme.bodyFont)
                .keyboardType(.phonePad)
        } header: {
            Text("Details")
                .ltcSectionHeaderStyle()
        }
    }

    private var infoFooterSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("Changes here are saved only in Legacy Treasure Chest and won’t modify the person in your Contacts app.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, Theme.spacing.small)
        }
    }

    // MARK: - Actions

    private func applyEditsAndDismiss() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let trimmedCustom = customRelationship.trimmingCharacters(in: .whitespacesAndNewlines)
        let relationshipValue: String
        if relationshipPreset == "Other / Custom" {
            relationshipValue = trimmedCustom
        } else {
            relationshipValue = relationshipPreset
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        beneficiary.name = trimmedName
        beneficiary.relationship = relationshipValue
        beneficiary.email = trimmedEmail.isEmpty ? nil : trimmedEmail
        beneficiary.phoneNumber = trimmedPhone.isEmpty ? nil : trimmedPhone
        beneficiary.updatedAt = .now

        dismiss()
    }

    /// Apply details from a CNContact to this beneficiary and to the form fields.
    private func applyContact(_ contact: CNContact) {
        // Build full name from contact.
        let fullName: String
        if !contact.givenName.isEmpty || !contact.familyName.isEmpty {
            fullName = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } else if !contact.organizationName.isEmpty {
            fullName = contact.organizationName
        } else {
            fullName = name.isEmpty ? beneficiary.name : name
        }

        // Treat this as an explicit “refresh” from Contacts.
        beneficiary.name = fullName
        name = fullName

        let emailValue: String? = contact.emailAddresses.first?.value as String?
        let phoneValue: String? = contact.phoneNumbers.first?.value.stringValue

        if let emailValue, !emailValue.isEmpty {
            beneficiary.email = emailValue
            email = emailValue
        }

        if let phoneValue, !phoneValue.isEmpty {
            beneficiary.phoneNumber = phoneValue
            phone = phoneValue
        }

        beneficiary.contactIdentifier = contact.identifier
        beneficiary.isLinkedToContact = true
        beneficiary.updatedAt = .now
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
        contactIdentifier: "CONTACT-ALEX",
        isLinkedToContact: true
    )

    context.insert(sample)

    return container
}()

#Preview("Edit Beneficiary") {
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
