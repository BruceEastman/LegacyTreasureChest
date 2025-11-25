//
//  ItemDocumentsSection.swift
//  LegacyTreasureChest
//
//  Documents section for item-related documents.
//  - Uses SwiftUI fileImporter to attach PDFs and images.
//  - Persists document files via MediaStorage.
//  - Stores metadata in SwiftData Document model.
//  - Shows a list of attached documents with delete support.
//  - v1: real viewing support:
//      • Images: in-app zoomable viewer
//      • PDFs/others: QuickLook preview
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import QuickLook

// Lightweight wrapper so we can use `.sheet(item:)`
// without modifying the SwiftData model type.
private struct DocumentPreviewItem: Identifiable {
    let id = UUID()
    let document: Document
}

struct ItemDocumentsSection: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var item: LTCItem

    // File importer & error state
    @State private var isImporterPresented: Bool = false
    @State private var importErrorMessage: String?

    // Selected document wrapper for preview
    @State private var selectedDocument: DocumentPreviewItem?

    // MARK: - Derived Data

    /// Documents as stored on the item. In most cases insertion order will
    /// align with createdAt, which is sufficient for v1.
    private var documents: [Document] {
        item.documents
    }

    /// Binding used to present an error alert only when needed.
    private var isImportErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    importErrorMessage = nil
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        Section(header: Text("Documents")) {
            if documents.isEmpty {
                emptyStateContent
            } else {
                populatedStateContent
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .alert(
            "Document Import Failed",
            isPresented: isImportErrorAlertPresented
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            if let message = importErrorMessage {
                Text(message)
            } else {
                Text("An unknown error occurred while importing the document.")
            }
        }
        .sheet(item: $selectedDocument) { preview in
            let document = preview.document

            // Decide how to show the document based on type.
            if document.documentType.uppercased() == "IMAGE" {
                NavigationStack {
                    ZStack {
                        Color.black.ignoresSafeArea()

                        if let image = loadImage(for: document) {
                            ZoomableDocImageView(image: image)
                        } else {
                            Text("Unable to load image.")
                                .foregroundStyle(.white)
                        }
                    }
                    .navigationTitle(displayName(for: document))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                selectedDocument = nil
                            }
                            .foregroundStyle(.white)
                        }
                    }
                }
            } else {
                // PDFs and all other types use QuickLook
                let absoluteURL = MediaStorage.absoluteURL(from: document.filePath)
                QuickLookPreview(url: absoluteURL)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text("Attach appraisals, receipts, and provenance documents.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                isImporterPresented = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Document")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Populated State

    private var populatedStateContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Add button at top when documents exist
            Button {
                isImporterPresented = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Document")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // List of existing documents
            if !documents.isEmpty {
                ForEach(documents, id: \.documentId) { document in
                    Button {
                        // Show viewer sheet
                        selectedDocument = DocumentPreviewItem(document: document)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: iconName(for: document))
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: document))
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                if let subtitle = subtitle(for: document) {
                                    Text(subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteDocument(document)
                        } label: {
                            Label("Remove Document", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteDocuments(at:))
            }

            Text("Tap a document to view it. PDFs open in a system viewer; images open in an in-app viewer.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Import Handling

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                importDocument(from: url)
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func importDocument(from url: URL) {
        // Security-scoped access for files outside the sandbox.
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)

            // Persist file via MediaStorage
            let relativePath = try MediaStorage.saveDocument(
                data,
                suggestedFilename: url.lastPathComponent
            )

            // Infer document type from file extension / UTI
            let inferredType = inferDocumentType(from: url)

            // Create and relate a new Document model
            let document = Document(
                filePath: relativePath,
                documentType: inferredType
            )
            document.item = item
            item.documents.append(document)
            item.updatedAt = .now

            modelContext.insert(document)
        } catch {
            importErrorMessage = "Unable to import document: \(error.localizedDescription)"
            print("❌ Document import failed: \(error)")
        }
    }

    // MARK: - Deletion

    private func deleteDocuments(at indexSet: IndexSet) {
        for index in indexSet {
            guard documents.indices.contains(index) else { continue }
            let document = documents[index]
            deleteDocument(document)
        }
    }

    private func deleteDocument(_ document: Document) {
        // Attempt to remove underlying file; failure is non-fatal.
        do {
            try MediaStorage.deleteFile(at: document.filePath)
        } catch {
            print("⚠️ Failed to delete document file at \(document.filePath): \(error)")
        }

        // Remove from item's collection & SwiftData context.
        if let index = item.documents.firstIndex(where: { $0 === document }) {
            item.documents.remove(at: index)
        }

        modelContext.delete(document)
        item.updatedAt = .now
    }

    // MARK: - Display Helpers

    private func iconName(for document: Document) -> String {
        switch document.documentType.uppercased() {
        case "PDF":
            return "doc.richtext"
        case "IMAGE":
            return "photo.on.rectangle"
        default:
            return "doc.text.fill"
        }
    }

    private func displayName(for document: Document) -> String {
        // Use the last path component as the display name.
        let path = document.filePath as NSString
        let last = path.lastPathComponent
        return last.isEmpty ? "Document" : last
    }

    private func subtitle(for document: Document) -> String? {
        var parts: [String] = []

        if !document.documentType.isEmpty {
            parts.append(document.documentType)
        }

        if let sizeDescription = sizeDescription(for: document) {
            parts.append(sizeDescription)
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private func sizeDescription(for document: Document) -> String? {
        guard let sizeBytes = MediaStorage.fileSize(at: document.filePath) else {
            return nil
        }

        let kb = Double(sizeBytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        } else {
            let mb = kb / 1024.0
            return String(format: "%.1f MB", mb)
        }
    }

    private func inferDocumentType(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .pdf) {
                return "PDF"
            } else if type.conforms(to: .image) {
                return "Image"
            } else {
                return type.identifier
            }
        }

        // Fallback on extension string if UTType is not resolvable.
        if ext == "pdf" {
            return "PDF"
        }

        return ext.isEmpty ? "Other" : ext.uppercased()
    }

    // MARK: - Loading Helpers

    private func loadImage(for document: Document) -> UIImage? {
        let url = MediaStorage.absoluteURL(from: document.filePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Zoomable Image View for Documents

/// A zoom + pan image view used in the document preview sheet.
/// This is local to the documents module to avoid coupling to ItemDetailView.
private struct ZoomableDocImageView: View {
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

// MARK: - Preview

private let itemDocumentsPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    let sample = LTCItem(
        name: "Preview Item with Documents",
        itemDescription: "This is a preview item for the documents section.",
        category: "Documents",
        value: 0
    )

    context.insert(sample)

    return container
}()

#Preview("Item Documents Section – Empty") {
    let container = itemDocumentsPreviewContainer
    let context = ModelContext(container)

    let descriptor = FetchDescriptor<LTCItem>()
    let items = (try? context.fetch(descriptor)) ?? []

    return NavigationStack {
        if let first = items.first {
            Form {
                ItemDocumentsSection(item: first)
            }
        } else {
            Text("No preview item")
        }
    }
    .modelContainer(container)
}
