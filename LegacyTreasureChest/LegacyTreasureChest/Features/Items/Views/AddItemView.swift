//
//  AddItemView.swift
//  LegacyTreasureChest
//
//  Full-screen form pushed from ItemsListView to create a new LTCItem.
//  Saves to SwiftData and pops back to the list, which updates via @Query.
//
//  UPDATE (2026-01): Supports adding photos during item creation.
//  Photos are kept in-memory until Save to avoid orphan files and to ensure Cancel creates nothing.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

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
    @State private var isSaving: Bool = false

    // Progressive disclosure persistence
    @AppStorage("ltc_fieldGuidanceCollapsed") private var fieldGuidanceCollapsed: Bool = false
    @AppStorage("ltc_fieldGuidanceUserOverride") private var fieldGuidanceUserOverride: Bool = false
    @AppStorage("ltc_itemCreationCount") private var itemCreationCount: Int = 0

    private let autoCollapseThreshold: Int = 5

    // MARK: - Photos (in-memory until Save)

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pickedImages: [UIImage] = []
    @State private var isProcessingPhotos: Bool = false

    // Simple validation: require a name
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
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

            // MARK: - Photos (during creation, in-memory)

            photosSection

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
            ) { EmptyView() }

            Section(
                footer: Text("You can add documents, audio stories, and beneficiaries from the item details screen.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            ) { EmptyView() }
        }
        .navigationTitle("Add Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }

            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { saveItem() }
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            // Auto-collapse after threshold unless the user has explicitly overridden.
            if !fieldGuidanceUserOverride {
                fieldGuidanceCollapsed = itemCreationCount >= autoCollapseThreshold
            }
        }
        // When picker selection changes, load images into memory.
        .onChange(of: selectedPhotoItems) {
            guard !selectedPhotoItems.isEmpty else { return }
            Task { @MainActor in
                await loadPickedPhotos(selectedPhotoItems)
            }
        }
    }

    // MARK: - Photos UI

    private var photosSection: some View {
        Section {
            if pickedImages.isEmpty {
                VStack(alignment: .center, spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textSecondary)

                    Text("Add photos of this item")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)

                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 10,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Photo")
                                .font(Theme.bodyFont)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessingPhotos || isSaving)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 10) {
                            ForEach(Array(pickedImages.enumerated()), id: \.offset) { index, uiImage in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipped()
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Theme.textSecondary.opacity(0.2), lineWidth: 0.5)
                                        )

                                    Button {
                                        removePickedImage(at: index)
                                    } label: {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(6)
                                            .background(Circle().fill(Theme.destructive.opacity(0.9)))
                                    }
                                    .padding(4)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if isProcessingPhotos {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Adding photos…")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top, 2)
                    }

                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 10,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add More Photos")
                                .font(Theme.secondaryFont)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessingPhotos || isSaving)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Photos")
                .ltcSectionHeaderStyle()
        }
    }

    @MainActor
    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        isProcessingPhotos = true
        defer {
            isProcessingPhotos = false
            selectedPhotoItems = [] // reset so picker can be used again
        }

        var encounteredError = false

        for pickerItem in items {
            do {
                guard let data = try await pickerItem.loadTransferable(type: Data.self) else { continue }
                guard let uiImage = UIImage(data: data) else {
                    encounteredError = true
                    continue
                }
                pickedImages.append(uiImage)
            } catch {
                encounteredError = true
                print("❌ Failed to load picked photo: \(error)")
            }
        }

        if encounteredError {
            errorMessage = "Unable to add one or more photos. Please try again."
        }
    }

    private func removePickedImage(at index: Int) {
        guard pickedImages.indices.contains(index) else { return }
        pickedImages.remove(at: index)
    }

    // MARK: - Save

    private func saveItem() {
        errorMessage = nil
        didSave = false
        isSaving = true

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let item = LTCItem(
            name: trimmedName,
            itemDescription: trimmedDescription,
            category: selectedCategory,
            value: value ?? 0
        )
        item.quantity = max(quantity, 1)

        modelContext.insert(item)

        // If image saving fails mid-way, we delete any files we already created (best effort).
        var savedPaths: [String] = []

        do {
            // First save the item itself.
            try modelContext.save()

            // Now attach photos (disk + SwiftData ItemImage).
            for uiImage in pickedImages {
                let relativePath = try MediaStorage.saveImage(uiImage)
                savedPaths.append(relativePath)

                let newImage = ItemImage(filePath: relativePath)
                newImage.item = item
                item.images.append(newImage)
                modelContext.insert(newImage)
            }

            // Save again with images attached.
            try modelContext.save()

            didSave = true
            itemCreationCount += 1
            isSaving = false
            dismiss()
        } catch {
            // Rollback best-effort for saved image files.
            for path in savedPaths {
                try? MediaStorage.deleteFile(at: path)
            }

            isSaving = false
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
