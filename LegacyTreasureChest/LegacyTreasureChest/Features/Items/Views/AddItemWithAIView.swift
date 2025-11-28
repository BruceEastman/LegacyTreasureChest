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

    // Category options (can expand based on AI output)
    private let baseCategories: [String] = [
        "Uncategorized",
        "Art",
        "Furniture",
        "Jewelry",
        "Collectibles",
        "Documents",
        "Electronics",
        "Luggage",
        "Rug",
        "Appliance",
        "Other"
    ]

    @State private var categoryOptions: [String] = []
    @State private var selectedCategory: String = "Uncategorized"

    @State private var value: Double? = nil

    // Currency code based on current locale, defaulting to USD
    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    // Simple validation: require a name and at least one analysis run
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        analysisResult != nil
    }

    // MARK: - Init

    init() {
        // categoryOptions is initialized in .onAppear so we can use @State
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
            Section(header: Text("Optional Hints for AI"),
                    footer: Text("These hints are only used to guide AI. You can still edit the final item details after analysis.")) {
                TextField("Working Title (optional)", text: $hintTitle)
                TextField("Short Description (optional)", text: $hintDescription)
                TextField("Known Category (optional)", text: $hintCategory)
            }

            // MARK: - Item Details (prefilled from AI)

            Section(header: Text("Review Item Details")) {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                TextField("Description", text: $itemDescription, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)

                Picker("Category", selection: $selectedCategory) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }

                TextField("Estimated Value", value: $value, format: .currency(code: currencyCode))
                    .keyboardType(.decimalPad)
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

        // Value: use midpoint of valueHints if present.
        if let hints = analysis.valueHints {
            let mid = (hints.low + hints.high) / 2.0
            if mid > 0 {
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
            value: value ?? 0
        )

        // Optionally: persist some AI fields into the item for later reference
        if let analysisResult {
            item.llmGeneratedTitle = analysisResult.title
            item.llmGeneratedDescription = analysisResult.summary
            if let hints = analysisResult.valueHints {
                item.suggestedPriceNew = hints.high
                item.suggestedPriceUsed = hints.low
            }
        }

        modelContext.insert(item)
        dismiss()
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
