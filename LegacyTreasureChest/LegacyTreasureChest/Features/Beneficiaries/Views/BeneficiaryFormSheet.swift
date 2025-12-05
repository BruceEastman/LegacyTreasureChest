//
//  BeneficiaryFormSheet.swift
//  LegacyTreasureChest
//
//  Simple form sheet to create a new Beneficiary manually.
//

import SwiftUI
import SwiftData

struct BeneficiaryFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var relationship: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""

    // Simple validation: require a name.
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
                    Text("New Beneficiary")
                        .ltcSectionHeaderStyle()
                } footer: {
                    Text("This person will appear in your beneficiary list and can be assigned to items in your legacy plan.")
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

    // MARK: - Actions

    private func saveBeneficiary() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let trimmedRelationship = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        let beneficiary = Beneficiary(
            name: trimmedName,
            relationship: trimmedRelationship,
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

#Preview("Add Beneficiary Form") {
    BeneficiaryFormSheet()
        .modelContainer(beneficiaryFormPreviewContainer)
}
