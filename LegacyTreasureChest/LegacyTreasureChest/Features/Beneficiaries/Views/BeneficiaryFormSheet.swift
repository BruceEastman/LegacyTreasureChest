//
//  BeneficiaryFormSheet.swift
//  LegacyTreasureChest
//
//  Sheet for manually creating a new Beneficiary.
//  Uses a relationship preset picker + optional custom relationship,
//  and supports basic contact details.
//

import SwiftUI
import SwiftData

struct BeneficiaryFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var relationshipPreset: String = "Other / Custom"
    @State private var customRelationship: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""

    // Common relationship options for consistency.
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

    // Require a name; relationship can be preset or custom.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Full Name", text: $name)
                        .font(Theme.bodyFont)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Name")
                        .ltcSectionHeaderStyle()
                }

                relationshipSection

                Section {
                    TextField("Email (optional)", text: $email)
                        .font(Theme.bodyFont)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)

                    TextField("Phone (optional)", text: $phone)
                        .font(Theme.bodyFont)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Contact")
                        .ltcSectionHeaderStyle()
                } footer: {
                    Text("You can also link or update this person from Contacts later.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Add Beneficiary")
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
                        saveBeneficiary()
                    }
                    .disabled(!canSave)
                    .font(Theme.bodyFont.weight(.semibold))
                }
            }
            .tint(Theme.accent)
        }
    }

    // MARK: - Relationship Section

    private var relationshipSection: some View {
        Section {
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
        } header: {
            Text("Relationship")
                .ltcSectionHeaderStyle()
        } footer: {
            Text("Choose the closest description, or use a custom label that makes sense for your family.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Save

    private func saveBeneficiary() {
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

        let beneficiary = Beneficiary(
            name: trimmedName,
            relationship: relationshipValue,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            phoneNumber: trimmedPhone.isEmpty ? nil : trimmedPhone
        )

        modelContext.insert(beneficiary)
        dismiss()
    }
}

// MARK: - Preview

private let beneficiaryFormPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: Beneficiary.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return container
}()

#Preview("Add Beneficiary") {
    NavigationStack {
        BeneficiaryFormSheet()
    }
    .modelContainer(beneficiaryFormPreviewContainer)
}
