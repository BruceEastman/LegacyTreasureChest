//
//  ItemDetailView.swift
//  LegacyTreasureChest
//
//  Editable detail screen for a single LTCItem.
//  Uses SwiftData @Bindable so changes auto-save and
//  are reflected immediately when navigating back.
//  Includes sections for Photos, Documents,
//  Audio stories, and Beneficiaries.
//  NOTE: This view owns the photo and document preview sheets.
//

import SwiftUI
import SwiftData
import UIKit
import QuickLook

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // SwiftData model binding – edits persist automatically.
    @Bindable var item: LTCItem

    // Preview sheet state for photos
    private struct PhotoPreviewItem: Identifiable {
        let id = UUID()
        let filePath: String
    }

    // Preview sheet state for documents
    private struct DocumentPreviewItem: Identifiable {
        let id = UUID()
        let document: Document
    }

    // Wrapper for editing an ItemBeneficiary in a sheet.
    private struct BeneficiaryEditItem: Identifiable {
        let id = UUID()
        let link: ItemBeneficiary
    }

    @State private var photoPreviewItem: PhotoPreviewItem?
    @State private var documentPreviewItem: DocumentPreviewItem?

    // Photo share state
    @State private var isPhotoSharePresented: Bool = false
    @State private var photoShareURL: URL?

    // Beneficiaries sheet
    @State private var isBeneficiaryPickerPresented: Bool = false
    @State private var editingLinkItem: BeneficiaryEditItem?

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
            Section {
                TextField("Name", text: $item.name)
                    .textInputAutocapitalization(.words)
                    .font(Theme.bodyFont)

                TextField("Description", text: $item.itemDescription, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .font(Theme.bodyFont)
            } header: {
                Text("Basic Info")
                    .ltcSectionHeaderStyle()
            }

            Section {
                Picker("Category", selection: $item.category) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Text(category)
                            .font(Theme.bodyFont)
                            .tag(category)
                    }
                }

                TextField(
                    "Estimated Value",
                    value: $item.value,
                    format: .currency(code: currencyCode)
                )
                .keyboardType(.decimalPad)
                .font(Theme.bodyFont)
            } header: {
                Text("Details")
                    .ltcSectionHeaderStyle()
            }

            // Photos section reports taps back to this parent view.
            ItemPhotosSection(item: item) { image in
                photoPreviewItem = PhotoPreviewItem(filePath: image.filePath)
            }

            // Documents section also reports taps back to this parent view.
            ItemDocumentsSection(item: item) { document in
                documentPreviewItem = DocumentPreviewItem(document: document)
            }

            ItemAudioSection(item: item)

            ItemBeneficiariesSection(
                item: item,
                onAddTapped: {
                    isBeneficiaryPickerPresented = true
                },
                onEditLink: { link in
                    editingLinkItem = BeneficiaryEditItem(link: link)
                },
                onRemoveLink: { link in
                    removeItemBeneficiary(link)
                }
            )

            Section {
                EmptyView()
            } footer: {
                Text("In future versions, you’ll be able to fully manage photos, documents, audio stories, and beneficiaries for this item.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Theme.spacing.small)
            }
        }
        .scrollContentBackground(.hidden)              // hide default gray background
        .background(Theme.background)                  // use branded background
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)                            // branded accent for controls
        // Single sheet at the parent level hosts the zoomable photo preview.
        .sheet(item: $photoPreviewItem) { preview in
            photoPreviewSheet(for: preview.filePath)
        }
        // Separate sheet for document preview (with share support).
        .sheet(item: $documentPreviewItem) { preview in
            documentPreviewSheet(for: preview.document)
        }
        // Beneficiary picker / creator sheet.
        .sheet(isPresented: $isBeneficiaryPickerPresented) {
            BeneficiaryPickerSheet(item: item, user: item.user)
        }
        // Beneficiary link editor sheet.
        .sheet(item: $editingLinkItem) { editItem in
            ItemBeneficiaryEditSheet(link: editItem.link)
        }
    }

    // MARK: - Photo Preview Sheet (with Share)

    private func photoPreviewSheet(for filePath: String) -> some View {
        let url = MediaStorage.absoluteURL(from: filePath)

        return NavigationStack {
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
            .onAppear {
                photoShareURL = url
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        photoPreviewItem = nil
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPhotoSharePresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $isPhotoSharePresented) {
                if let url = photoShareURL {
                    ActivityView(activityItems: [url])
                }
            }
        }
    }

    // MARK: - Document Preview Sheet (with Share)

    private func documentPreviewSheet(for document: Document) -> some View {
        let absoluteURL = MediaStorage.absoluteURL(from: document.filePath)
        return DocumentPreviewScreen(
            document: document,
            url: absoluteURL,
            onDone: { documentPreviewItem = nil }
        )
    }

    // MARK: - Helpers – Beneficiaries

    private func removeItemBeneficiary(_ link: ItemBeneficiary) {
        // Remove from the item's collection
        if let index = item.itemBeneficiaries.firstIndex(where: { $0 === link }) {
            item.itemBeneficiaries.remove(at: index)
        }
        // Also delete the link object from the context
        modelContext.delete(link)
    }
}

// MARK: - Document Preview Screen

/// Full-screen document preview with:
/// - Image viewer for "IMAGE" documents (in Documents section)
/// - QuickLook for PDFs/others
/// - "Done" and "Share" controls
/// - Extra overlay Share button for image docs to ensure visibility
private struct DocumentPreviewScreen: View {
    let document: Document
    let url: URL
    let onDone: () -> Void

    @State private var isSharePresented: Bool = false

    private var isImageDoc: Bool {
        document.documentType.uppercased() == "IMAGE"
    }

    private var displayName: String {
        if let original = document.originalFilename, !original.isEmpty {
            return original
        }
        let path = document.filePath as NSString
        let last = path.lastPathComponent
        return last.isEmpty ? "Document" : last
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Group {
                    if isImageDoc, let image = loadImage() {
                        ZStack {
                            Color.black.ignoresSafeArea()
                            ZoomableImageView(image: image)
                        }
                    } else {
                        QuickLookPreview(url: url)
                            .ignoresSafeArea()
                    }
                }

                // Explicit overlay Share button for image docs
                if isImageDoc {
                    Button {
                        isSharePresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .imageScale(.large)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .padding(.top, 12)
                            .padding(.trailing, 12)
                    }
                }
            }
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        onDone()
                    }
                }
                // Keep toolbar Share for non-image docs (PDFs, etc.)
                ToolbarItem(placement: .topBarTrailing) {
                    if !isImageDoc {
                        Button {
                            isSharePresented = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $isSharePresented) {
                ActivityView(activityItems: [url])
            }
        }
    }

    private func loadImage() -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Zoomable Image View

/// A standalone zoom + pan image view used in the photo and document preview sheets.
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

// MARK: - QuickLook wrapper for PDFs and other docs

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        // No-op; single static URL.
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Activity View (Share Sheet)

/// Simple wrapper around UIActivityViewController to present
/// the system share sheet from SwiftUI.
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        // No update needed.
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
