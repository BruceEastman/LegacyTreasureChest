//
//  ItemDetailView.swift
//  LegacyTreasureChest
//
//  Editable detail screen for a single LTCItem.
//  Uses SwiftData @Bindable so changes auto-save and
//  are reflected immediately when navigating back.
//  Includes sections for Photos, Documents,
//  Audio stories, and Beneficiaries.
//  NOTE: This view owns the photo preview sheet.
//

import SwiftUI
import SwiftData
import UIKit

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss

    // SwiftData model binding – edits persist automatically.
    @Bindable var item: LTCItem

    // Preview sheet state for photos
    private struct PhotoPreviewItem: Identifiable {
        let id = UUID()
        let filePath: String
    }

    @State private var photoPreviewItem: PhotoPreviewItem?

    // Base category options
    private let defaultCategories: [String] = [
        "Uncategorized",
        "Art",
        "Furniture",
        "Jewelry",
        "Collectibles",
        "Documents",
        "Electronics",
        "Other"
    ]

    // Include the item's current category if it's not in the defaults
    private var categoryOptions: [String] {
        let current = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty, !defaultCategories.contains(current) else {
            return defaultCategories
        }
        return defaultCategories + [current]
    }

    // Currency code based on current locale, defaulting to USD
    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var body: some View {
        Form {
            Section(header: Text("Basic Info")) {
                TextField("Name", text: $item.name)
                    .textInputAutocapitalization(.words)

                TextField("Description", text: $item.itemDescription, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }

            Section(header: Text("Details")) {
                Picker("Category", selection: $item.category) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }

                TextField("Estimated Value", value: $item.value, format: .currency(code: currencyCode))
                    .keyboardType(.decimalPad)
            }

            // Photos section reports taps back to this parent view.
            ItemPhotosSection(item: item) { image in
                photoPreviewItem = PhotoPreviewItem(filePath: image.filePath)
            }

            ItemDocumentsSection(item: item)
            ItemAudioSection(item: item)
            ItemBeneficiariesSection(item: item)

            Section(footer: Text("In future versions, you’ll be able to fully manage photos, documents, audio stories, and beneficiaries for this item.")) {
                EmptyView()
            }
        }
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
        // Single sheet at the parent level hosts the zoomable photo preview.
        .sheet(item: $photoPreviewItem) { preview in
            photoPreviewSheet(for: preview.filePath)
        }
    }

    // MARK: - Photo Preview Sheet

    private func photoPreviewSheet(for filePath: String) -> some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if let image = MediaStorage.loadImage(from: filePath) {
                    ZoomableImageView(image: image)
                } else {
                    Text("Unable to load image.")
                        .foregroundStyle(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        photoPreviewItem = nil
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - Zoomable Image View

/// A standalone zoom + pan image view used in the photo preview sheet.
/// All gesture state is local to this view to avoid interfering with navigation/sheets.
private struct ZoomableImageView: View {
    let image: UIImage

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    magnificationGesture().simultaneously(with: dragGesture())
                )
                .animation(.easeInOut(duration: 0.15), value: scale)
                .animation(.easeInOut(duration: 0.15), value: offset)
        }
    }

    // Pinch to zoom
    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                var newScale = scale * delta
                newScale = max(minScale, min(newScale, maxScale))
                scale = newScale
                lastScale = value
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale < minScale {
                    scale = minScale
                }
            }
    }

    // Drag to pan
    private func dragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
}

// MARK: - Preview

private let itemDetailPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    let sample = LTCItem(
        name: "Vintage Camera",
        itemDescription: "A family heirloom camera passed down from my grandfather.",
        category: "Collectibles",
        value: 250
    )

    context.insert(sample)

    return container
}()

#Preview {
    let container = itemDetailPreviewContainer
    let context = ModelContext(container)

    let descriptor = FetchDescriptor<LTCItem>()
    let items = (try? context.fetch(descriptor)) ?? []

    return NavigationStack {
        if let first = items.first {
            ItemDetailView(item: first)
        } else {
            Text("No preview item")
        }
    }
    .modelContainer(container)
}
