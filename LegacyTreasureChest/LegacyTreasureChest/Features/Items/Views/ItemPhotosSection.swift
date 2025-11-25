//
//  ItemPhotosSection.swift
//  LegacyTreasureChest
//
//  Photos section for attaching images to an LTCItem.
//  Uses PhotosPicker, MediaStorage, and SwiftData-backed ItemImage records.
//  NOTE: This view does not own any sheet/full-screen presentation.
//  It surfaces taps via a callback so the parent view can present a preview.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct ItemPhotosSection: View {
    // We take a @Bindable LTCItem so that we can attach images to it.
    @Bindable var item: LTCItem

    @Environment(\.modelContext) private var modelContext

    // Callback for when a photo thumbnail is tapped.
    // The parent view (ItemDetailView) can use this to present a preview.
    var onImageTap: (ItemImage) -> Void

    // PhotosPicker state
    @State private var selectedItems: [PhotosPickerItem] = []

    // UI state
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?

    // Responsive grid for thumbnails
    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 90, maximum: 130), spacing: 10)
    ]

    var body: some View {
        Section(header: Text("Photos")) {
            if item.images.isEmpty {
                emptyStateView
            } else {
                photosGridView
            }

            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Adding photos…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .alert(
            "Photo Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { newValue in
                    if !newValue { errorMessage = nil }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            },
            message: {
                Text(errorMessage ?? "An unknown error occurred while handling photos.")
            }
        )
        // iOS 17+ style onChange (no parameter)
        .onChange(of: selectedItems) {
            guard !selectedItems.isEmpty else { return }
            Task { @MainActor in
                await handlePickedItems(selectedItems)
            }
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Add photos of this item")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 10,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Photo")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }

    private var photosGridView: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(
                    item.images.sorted(by: { $0.createdAt < $1.createdAt }),
                    id: \.imageId
                ) { image in
                    thumbnailView(for: image)
                }
            }

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 10,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add More Photos")
                }
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private func thumbnailView(for itemImage: ItemImage) -> some View {
        let uiImage = MediaStorage.loadImage(from: itemImage.filePath)

        let thumbnail = ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle()
                        .fill(.secondary.opacity(0.15))
                    Image(systemName: "photo.slash")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                }
            }
        }
        .frame(width: 100, height: 100)        // 🔥 fixed square for grid
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 2)

        return ZStack(alignment: .topTrailing) {
            thumbnail
                .contentShape(Rectangle())
                .onTapGesture {
                    onImageTap(itemImage)
                }

            Button {
                deletePhoto(itemImage)
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(
                        Circle().fill(Color.red.opacity(0.9))
                    )
            }
            .padding(4)
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button(role: .destructive) {
                deletePhoto(itemImage)
            } label: {
                Label("Delete Photo", systemImage: "trash")
            }
        }
    }

    // MARK: - Logic

    @MainActor
    private func handlePickedItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        isProcessing = true
        defer {
            isProcessing = false
            selectedItems = []   // reset picker selection so it can be used again
        }

        var encounteredError = false

        for pickerItem in items {
            do {
                guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                    continue
                }

                guard let uiImage = UIImage(data: data) else {
                    print("❌ Failed to create UIImage from picked data.")
                    encounteredError = true
                    continue
                }

                let relativePath = try MediaStorage.saveImage(uiImage)

                let newImage = ItemImage(filePath: relativePath)
                newImage.item = item
                item.images.append(newImage)
                modelContext.insert(newImage)
            } catch {
                print("❌ Failed to import photo: \(error)")
                encounteredError = true
            }
        }

        if encounteredError {
            errorMessage = "Unable to add one or more photos. Please try again."
        }
    }

    @MainActor
    private func deletePhoto(_ itemImage: ItemImage) {
        // Remove from SwiftData first (source of truth).
        modelContext.delete(itemImage)

        // Best-effort file deletion.
        do {
            try MediaStorage.deleteFile(at: itemImage.filePath)
        } catch {
            // Soft failure: log but don't surface to user.
            print("⚠️ Failed to delete image file at \(itemImage.filePath): \(error)")
        }
    }
}

// MARK: - Preview

private let itemPhotosPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    let sample = LTCItem(
        name: "Preview Item",
        itemDescription: "This is a preview item for the photos section.",
        category: "Art",
        value: 100
    )

    context.insert(sample)

    return container
}()

#Preview("Item Photos Section – No Images") {
    let container = itemPhotosPreviewContainer
    let context = ModelContext(container)

    let descriptor = FetchDescriptor<LTCItem>()
    let items = (try? context.fetch(descriptor)) ?? []

    return NavigationStack {
        if let first = items.first {
            Form {
                // For preview, pass a no-op closure for onImageTap.
                ItemPhotosSection(item: first, onImageTap: { _ in })
            }
        } else {
            Text("No preview item")
        }
    }
    .modelContainer(container)
}
