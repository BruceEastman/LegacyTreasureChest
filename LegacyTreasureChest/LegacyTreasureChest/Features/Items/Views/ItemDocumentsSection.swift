//
//  ItemDocumentsSection.swift
//  LegacyTreasureChest
//
//  Documents section for item-related documents.
//  - Uses SwiftUI fileImporter to attach PDFs and images.
//  - Persists document files via MediaStorage.
//  - Stores metadata in SwiftData Document model.
//  - Shows a list of attached documents with delete support.
//  - Taps are reported back to the parent view for preview.
//  - Includes a simple file size guard on import (50 MB).
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ItemDocumentsSection: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var item: LTCItem
    var onDocumentTap: (Document) -> Void

    // File importer & error state
    @State private var isImporterPresented: Bool = false
    @State private var importErrorMessage: String?

    // MARK: - Derived Data

    private var documents: [Document] {
        item.documents
    }

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
        Section {
            if documents.isEmpty {
                emptyStateContent
            } else {
                populatedStateContent
            }
        } header: {
            Text("Documents")
                .ltcSectionHeaderStyle()
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
    }

    // MARK: - Empty State

    private var emptyStateContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)

                Text("Attach appraisals, receipts, and provenance documents.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                isImporterPresented = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Document")
                        .font(Theme.bodyFont)
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
            Button {
                isImporterPresented = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Document")
                        .font(Theme.bodyFont)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if !documents.isEmpty {
                ForEach(documents, id: \.documentId) { document in
                    Button {
                        onDocumentTap(document)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: iconName(for: document))
                                .foregroundStyle(Theme.textSecondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: document))
                                    .font(Theme.bodyFont)
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                if let subtitle = subtitle(for: document) {
                                    Text(subtitle)
                                        .font(Theme.secondaryFont)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary.opacity(0.7))
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
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
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
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)

            // Simple file size guard: 50 MB max
            let maxSizeBytes = 50 * 1024 * 1024 // 50 MB
            if data.count > maxSizeBytes {
                importErrorMessage = "This document is too large (over 50 MB). Please choose a smaller file."
                return
            }

            let relativePath = try MediaStorage.saveDocument(
                data,
                suggestedFilename: url.lastPathComponent
            )

            let inferredType = inferDocumentType(from: url)
            let originalFilename = url.lastPathComponent

            let document = Document(
                filePath: relativePath,
                documentType: inferredType,
                originalFilename: originalFilename
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
        do {
            try MediaStorage.deleteFile(at: document.filePath)
        } catch {
            print("⚠️ Failed to delete document file at \(document.filePath): \(error)")
        }

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
        // Prefer the user-visible original filename, if present.
        if let name = document.originalFilename, !name.isEmpty {
            return name
        }
        // Fallback: use the stored path's last component.
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

        if ext == "pdf" {
            return "PDF"
        }

        return ext.isEmpty ? "Other" : ext.uppercased()
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
                ItemDocumentsSection(item: first) { _ in }
            }
        } else {
            Text("No preview item")
        }
    }
    .modelContainer(container)
}
