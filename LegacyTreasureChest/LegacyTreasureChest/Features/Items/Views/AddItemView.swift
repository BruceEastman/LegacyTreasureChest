//
//  AddItemView.swift
//  LegacyTreasureChest
//
//  Full-screen form pushed from ItemsListView to create a new LTCItem.
//  Saves to SwiftData and pops back to the list, which updates via @Query.
//

import SwiftUI
import SwiftData

struct AddItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var itemDescription: String = ""

    // Category options for new items (centralized via LTCItem.baseCategories)
    private let defaultCategories: [String] = LTCItem.baseCategories
    @State private var selectedCategory: String = "Uncategorized"

    // Quantity (sets / identical units)
    @State private var quantity: Int = 1

    // Use a Double? so the field can start empty, with currency formatting
    @State private var value: Double? = nil

    // UX feedback
    @State private var errorMessage: String?
    @State private var didSave: Bool = false

    // Simple validation: require a name
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Currency code based on current locale, defaulting to USD
    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var body: some View {
        Form {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.destructive)
                }
            }

            if didSave {
                Section {
                    Text("Saved.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Section(header: Text("Basic Info")) {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                TextField("Description", text: $itemDescription, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }

            Section(header: Text("Details")) {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(defaultCategories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }

                Stepper(value: $quantity, in: 1...999) {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        Text("×\(quantity)")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                TextField(
                    "Estimated Unit Value",
                    value: $value,
                    format: .currency(code: currencyCode)
                )
                .keyboardType(.decimalPad)

                if quantity > 1 {
                    let unit = max(value ?? 0, 0)
                    let total = unit * Double(quantity)
                    Text("Total: \(total, format: .currency(code: currencyCode)) (\(unit, format: .currency(code: currencyCode)) each)")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Section(
                footer: Text("You can add photos, documents, audio stories, and beneficiaries from the item details screen.")
            ) {
                EmptyView()
            }
        }
        .navigationTitle("Add Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveItem() }
                    .disabled(!canSave)
            }
        }
    }

    // MARK: - Save

    private func saveItem() {
        errorMessage = nil
        didSave = false

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let item = LTCItem(
            name: trimmedName,
            itemDescription: trimmedDescription,
            category: selectedCategory,
            value: value ?? 0
        )

        // Ensure quantity is always valid.
        item.quantity = max(quantity, 1)

        modelContext.insert(item)

        do {
            try modelContext.save()
            didSave = true
            dismiss()
        } catch {
            // If save fails, keep the view open and show the error
            errorMessage = "Could not save item: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

private let addItemPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return container
}()

#Preview {
    NavigationStack {
        AddItemView()
            .modelContainer(addItemPreviewContainer)
    }
}
