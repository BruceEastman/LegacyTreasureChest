//
//  AddItemWithAIView.swift
//  LegacyTreasureChest
//
//  AI-assisted item creation flow.
//  1) User picks a photo.
//  2) We call AIService.analyzeItemPhoto.
//  3) We prefill item fields from ItemAnalysis.
//  4) User reviews/edits and saves an LTCItem.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AddItemWithAIView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - AI / Photo state

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    @State private var isAnalyzing: Bool = false
    @State private var analysisResult: ItemAnalysis?
    @State private var errorMessage: String?

    // Optional hint fields to guide AI
    @State private var hintTitle: String = ""
    @State private var hintDescription: String = ""
    @State private var hintCategory: String = ""

    // MARK: - Item form state

    @State private var name: String = ""
    @State private var itemDescription: String = ""

    // quantity
    @State private var quantity: Int = 1

    // Category options (centralized via LTCItem.baseCategories)
    private let baseCategories: [String] = LTCItem.baseCategories

    @State private var categoryOptions: [String] = []
    @State private var selectedCategory: String = "Uncategorized"

    @State private var value: Double? = nil

    // Progressive disclosure persistence
    @AppStorage("ltc_fieldGuidanceCollapsed") private var fieldGuidanceCollapsed: Bool = false
    @AppStorage("ltc_fieldGuidanceUserOverride") private var fieldGuidanceUserOverride: Bool = false
    @AppStorage("ltc_itemCreationCount") private var itemCreationCount: Int = 0

    private let autoCollapseThreshold: Int = 5

    // Currency code based on current locale, defaulting to USD
    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var unitValue: Double {
        max(value ?? 0, 0)
    }

    private var totalValue: Double {
        unitValue * Double(max(quantity, 1))
    }

    // Simple validation: require a name and at least one analysis run
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        analysisResult != nil
    }

    // MARK: - View

    var body: some View {
        Form {
            // MARK: - Photo & AI section

            Section(header: Text("Photo & AI Analysis")) {
                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text(selectedImage == nil ? "Choose Photo" : "Change Photo")
                    }
                }

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.vertical, 4)
                }

                Button {
                    Task { await runAnalysis() }
                } label: {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                        }
                        Text("Analyze Photo with AI")
                            .font(Theme.bodyFont.weight(.semibold))
                    }
                }
                .disabled(selectedImage == nil || isAnalyzing)
            }

            // Optional hints
            Section(
                header: Text("Optional Hints for AI"),
                footer: Text(
                    "💡 Hard facts help AI most: brand/model, stamps or labels, materials, measurements, condition, and quantity.\n\n" +
                    "These hints are only used to guide AI. You can still edit the final item details after analysis."
                )
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
            ) {
                TextField("Working Title (optional)", text: $hintTitle)
                TextField("Short Description (optional)", text: $hintDescription)
                TextField("Known Category (optional)", text: $hintCategory)
            }

            // MARK: - Item Details (prefilled from AI)

            Section(header: Text("Review Item Details")) {
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
                            Text("• **Description**: what it is + traits + story.")
                            Text("• **Best AI results**: add hard facts (stamps, size, condition, quantity).")
                        }
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                    }
                )

                TextField("Description", text: $itemDescription, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)

                Picker("Category", selection: $selectedCategory) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }

                Stepper(value: $quantity, in: 1...999) {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        Text("\(quantity)")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                TextField(
                    "Estimated Value (each)",
                    value: Binding<Int>(
                        get: { Int((value ?? 0).rounded()) },
                        set: { value = Double($0) }
                    ),
                    format: .currency(code: currencyCode).precision(.fractionLength(0))
                )
                .keyboardType(.numberPad)
                
                if quantity > 1, unitValue > 0 {
                    Text("Total: \(CurrencyFormat.dollars(totalValue)) (\(CurrencyFormat.dollars(unitValue)) each)")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let analysisResult {
                Section(header: Text("AI Summary")) {
                    Text(analysisResult.summary)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.destructive)
                        .font(Theme.secondaryFont)
                }
            }
        }
        .navigationTitle("Add Item with AI")
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
        .onAppear {
            if categoryOptions.isEmpty {
                categoryOptions = baseCategories
                selectedCategory = "Uncategorized"
            }

            // Auto-collapse after threshold unless the user has explicitly overridden.
            if !fieldGuidanceUserOverride {
                fieldGuidanceCollapsed = itemCreationCount >= autoCollapseThreshold
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            Task { await loadSelectedImage(from: newValue) }
        }
    }

    // MARK: - AI Helpers

    private func runAnalysis() async {
        guard let selectedImage else {
            errorMessage = "Please choose a photo before running analysis."
            return
        }

        isAnalyzing = true
        errorMessage = nil

        let hints = ItemAIHints(
            userWrittenTitle: hintTitle.isEmpty ? nil : hintTitle,
            userWrittenDescription: hintDescription.isEmpty ? nil : hintDescription,
            knownCategory: hintCategory.isEmpty ? nil : hintCategory
        )

        do {
            let result = try await AIService.shared.analyzeItemPhoto(selectedImage, hints: hints)
            analysisResult = result
            applyAnalysisToForm(result)
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }

    private func applyAnalysisToForm(_ analysis: ItemAnalysis) {
        // Populate form fields from AI results, but let the user edit them.
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = analysis.title
        }

        if itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            itemDescription = analysis.summary
        }

        // Category: ensure it's available in the picker.
        let suggestedCategory = analysis.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if !suggestedCategory.isEmpty {
            if !categoryOptions.contains(where: { $0.caseInsensitiveCompare(suggestedCategory) == .orderedSame }) {
                categoryOptions.append(suggestedCategory)
            }
            selectedCategory = suggestedCategory
        }

        // Value: use midpoint / estimate from valueHints if present.
        if let hints = analysis.valueHints {
            let mid: Double? = {
                if let est = hints.estimatedValue {
                    return est
                }
                if let low = hints.valueLow, let high = hints.valueHigh {
                    return (low + high) / 2.0
                }
                if let low = hints.valueLow {
                    return low
                }
                if let high = hints.valueHigh {
                    return high
                }
                return nil
            }()

            if let mid, mid > 0 {
                value = mid
            }
        }
    }

    private func loadSelectedImage(from item: PhotosPickerItem?) async {
        guard let item else { return }

        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            self.selectedImage = image
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
            value: value ?? 0,
            quantity: quantity
        )

        // Optionally: persist some AI fields into the item and valuation.
        if let analysisResult {
            item.llmGeneratedTitle = analysisResult.title
            item.llmGeneratedDescription = analysisResult.summary

            if let hints = analysisResult.valueHints {
                // Update simple numeric fields on the item.
                let mid: Double? = {
                    if let est = hints.estimatedValue { return est }
                    if let low = hints.valueLow, let high = hints.valueHigh { return (low + high) / 2.0 }
                    if let low = hints.valueLow { return low }
                    if let high = hints.valueHigh { return high }
                    return nil
                }()

                if let mid, mid > 0 {
                    item.value = mid
                }

                if let high = hints.valueHigh {
                    item.suggestedPriceNew = high
                } else if let est = hints.estimatedValue {
                    item.suggestedPriceNew = est
                }

                if let low = hints.valueLow {
                    item.suggestedPriceUsed = low
                } else if let est = hints.estimatedValue {
                    item.suggestedPriceUsed = est
                }

                // Create a valuation record (unit valuation).
                let valuation = ItemValuation(
                    valueLow: hints.valueLow,
                    estimatedValue: hints.estimatedValue,
                    valueHigh: hints.valueHigh,
                    currencyCode: hints.currencyCode,
                    confidenceScore: hints.confidenceScore,
                    valuationDate: hints.valuationDate.flatMap(parseISO8601Date),
                    aiProvider: hints.aiProvider,
                    aiNotes: hints.aiNotes,
                    missingDetails: hints.missingDetails ?? [],
                    userNotes: nil
                )
                item.valuation = valuation
            }
        }

        modelContext.insert(item)

        // Progressive disclosure: track creation count
        itemCreationCount += 1

        dismiss()
    }

    /// Parse ISO 8601 timestamps like "2025-12-08T21:57:15.698594Z".
    private func parseISO8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
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

private let addItemWithAIPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return container
}()

#Preview {
    NavigationStack {
        AddItemWithAIView()
            .modelContainer(addItemWithAIPreviewContainer)
    }
}
