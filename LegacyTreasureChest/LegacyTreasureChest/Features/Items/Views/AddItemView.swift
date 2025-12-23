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

    // Progressive disclosure persistence
    @AppStorage("ltc_fieldGuidanceCollapsed") private var fieldGuidanceCollapsed: Bool = false
    @AppStorage("ltc_fieldGuidanceUserOverride") private var fieldGuidanceUserOverride: Bool = false
    @AppStorage("ltc_itemCreationCount") private var itemCreationCount: Int = 0

    private let autoCollapseThreshold: Int = 5

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

            // MARK: - Basic Info

            Section(header: Text("Basic Info")) {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                FieldGuidanceDisclosure(
                    title: "Field Guidance",
                    collapsed: $fieldGuidanceCollapsed,
                    onToggle: {
                        fieldGuidanceUserOverride = true
                        withAnimation(.easeInOut(duration: 0.2)) {
                            fieldGuidanceCollapsed.toggle()
                        }
                    },
                    content: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• **Title**: brand + item type + key detail (3–7 words).")
                            Text("  Example: “Waterford Lismore Vase”.")
                            Text("• **Description**: what it is + notable traits + story.")
                            Text("  Save hard facts (stamps, size, condition) for AI details.")
                        }
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                    }
                )

                TextField("Description", text: $itemDescription, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }

            // MARK: - Details

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

            // MARK: - Footer Guidance

            Section(
                footer: Text("💡 Best AI results: add key details first → add a photo → tap Improve with AI on the item details screen.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            ) {
                EmptyView()
            }

            Section(
                footer: Text("You can add photos, documents, audio stories, and beneficiaries from the item details screen.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
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
        .onAppear {
            // Auto-collapse after threshold unless the user has explicitly overridden.
            if !fieldGuidanceUserOverride {
                fieldGuidanceCollapsed = itemCreationCount >= autoCollapseThreshold
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

            // Progressive disclosure: track creation count
            itemCreationCount += 1

            dismiss()
        } catch {
            // If save fails, keep the view open and show the error
            errorMessage = "Could not save item: \(error.localizedDescription)"
        }
    }
}

// MARK: - Collapsible Field Guidance (local)

private struct FieldGuidanceDisclosure<Content: View>: View {
    let title: String
    @Binding var collapsed: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(Theme.accent)

                    Text(title)
                        .font(Theme.secondaryFont.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)

                    Spacer()

                    Image(systemName: collapsed ? "chevron.forward" : "chevron.down")
                        .foregroundStyle(Theme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                content
                    .padding(.vertical, Theme.spacing.small)
                    .padding(.horizontal, Theme.spacing.medium)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.top, 4)
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
