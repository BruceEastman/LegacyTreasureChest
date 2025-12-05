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

    // Use a Double? so the field can start empty, with currency formatting
    @State private var value: Double? = nil

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

                TextField(
                    "Estimated Value",
                    value: $value,
                    format: .currency(code: currencyCode)
                )
                .keyboardType(.decimalPad)
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
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveItem()
                }
                .disabled(!canSave)
            }
        }
    }

    // MARK: - Save

    private func saveItem() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let item = LTCItem(
            name: trimmedName,
            itemDescription: trimmedDescription,
            category: selectedCategory,
            value: value ?? 0
        )

        modelContext.insert(item)
        dismiss()
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
