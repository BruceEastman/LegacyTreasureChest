//
//  ItemDetailView.swift
//  LegacyTreasureChest
//
//  Editable detail screen for a single LTCItem.
//
//  Layout (1.3): Item summary (main photo, name, category, quantity,
//  description) → Estimated Resale Value → Improve with AI → supporting
//  photos, documents and audio → beneficiaries and next steps.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import QuickLook

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var item: LTCItem

    private struct PhotoPreviewItem: Identifiable {
        let id = UUID()
        let filePath: String
    }

    private struct DocumentPreviewItem: Identifiable {
        let id = UUID()
        let document: Document
    }

    private struct BeneficiaryEditItem: Identifiable {
        let id = UUID()
        let link: ItemBeneficiary
    }

    @State private var photoPreviewItem: PhotoPreviewItem?
    @State private var documentPreviewItem: DocumentPreviewItem?

    @State private var isPhotoSharePresented: Bool = false
    @State private var photoShareURL: URL?

    @State private var isBeneficiaryPickerPresented: Bool = false
    @State private var editingLinkItem: BeneficiaryEditItem?

    @State private var isAIAnalysisPresented: Bool = false

    @State private var saveErrorMessage: String?
    @State private var showSaveErrorAlert: Bool = false

    private let defaultCategories: [String] = LTCItem.baseCategories

    @AppStorage("ltc_fieldGuidanceCollapsed") private var fieldGuidanceCollapsed: Bool = false
    @AppStorage("ltc_fieldGuidanceUserOverride") private var fieldGuidanceUserOverride: Bool = false
    @AppStorage("ltc_aiGuidanceCollapsed") private var aiGuidanceCollapsed: Bool = false
    @AppStorage("ltc_aiGuidanceUserOverride") private var aiGuidanceUserOverride: Bool = false

    private var categoryOptions: [String] {
        let current = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty, !defaultCategories.contains(current) else {
            return defaultCategories
        }
        return defaultCategories + [current]
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    // MARK: - Liquidate (optional gating)

    private var gateLiquidateOnMarketAI: Bool { false }

    private var shouldShowLiquidate: Bool {
        if gateLiquidateOnMarketAI {
            return FeatureFlags().enableMarketAI
        }
        return true
    }

    // Summary editing state
    @FocusState private var isDescriptionFocused: Bool
    @State private var isDescriptionExpanded: Bool = false
    @State private var summaryPhotoSelection: [PhotosPickerItem] = []
    @State private var isAddingSummaryPhoto: Bool = false
    @State private var summaryPhotoError: String?

    private let summaryPhotoSize: CGFloat = 84

    /// A description longer than this shows a "Show full description" control
    /// instead of the whole text while not being edited.
    private let collapsedDescriptionLines = 3

    private var isDescriptionLong: Bool {
        let text = item.itemDescription
        return text.count > 160 || text.filter { $0 == "\n" }.count >= collapsedDescriptionLines
    }

    var body: some View {
        let valuation = ItemValuationPresentation(item: item)

        Form {
            // MARK: - 1. Item Summary
            Section {
                summaryHeader

                Picker("Category", selection: $item.category) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Text(category)
                            .font(Theme.bodyFont)
                            .tag(category)
                    }
                }

                Stepper(value: $item.quantity, in: 1...999) {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        Text("×\(max(item.quantity, 1))")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                descriptionEditor

                FieldGuidanceDisclosure(
                    title: "Writing Tips",
                    collapsed: $fieldGuidanceCollapsed,
                    onToggle: {
                        fieldGuidanceUserOverride = true
                        withAnimation(.easeInOut(duration: 0.2)) {
                            fieldGuidanceCollapsed.toggle()
                        }
                    },
                    content: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• **Name**: brand + item type + key detail (3–7 words).")
                            Text("  Example: “Waterford Lismore Vase”.")
                            Text("• **Description**: what it is + traits + story.")
                            Text("  Save hard facts (stamps, size, condition, quantity) for AI details.")
                        }
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                    }
                )
            } header: {
                Text("Item")
                    .ltcSectionHeaderStyle()
            }

            // MARK: - 2. Estimated Resale Value
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(valuation.quantity > 1 ? "Value each" : "Estimated value")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Theme.text)
                        Text(valuation.sourceCaption)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer(minLength: 12)

                    TextField(
                        "Estimated Unit Value",
                        value: Binding<Int?>(
                            get: { item.estimatedUnitValue.map { Int($0.rounded()) } },
                            set: { item.value = Double(max($0 ?? 0, 0)) }
                        ),
                        format: .currency(code: currencyCode).precision(.fractionLength(0)),
                        prompt: Text(CurrencyFormat.notEstimated)
                    )
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(valuation.quantity > 1 ? "Value each" : "Estimated value")
                    .accessibilityHint("Edit the value.")
                }

                if let total = valuation.totalValue {
                    HStack {
                        Text("Total for \(valuation.quantity)")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(CurrencyFormat.dollars(total))
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.text)
                    }
                    .accessibilityElement(children: .combine)
                }

                ItemValuationSummaryView(presentation: valuation)
            } header: {
                Text("Estimated Resale Value")
                    .ltcSectionHeaderStyle()
            } footer: {
                Text(valuation.quantity > 1
                     ? "Tap the value to change it. The total is the value each × quantity."
                     : "Tap the value to change it.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            // MARK: - 3. Improve with AI
            Section {
                Button {
                    isAIAnalysisPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Improve with AI")
                            .font(Theme.bodyFont.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.accent)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                // IMPORTANT: do not block this. The sheet supports text-only now.

                VStack(alignment: .leading, spacing: 12) {
                    Text("Add details, photos, or documents to improve identification and estimated resale value.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Why the current estimate, then the AI's own suggestions.
                    ItemValuationExplanationView(explanation: valuation.explanation)
                    ItemValuationSuggestionsView(suggestions: valuation.suggestions)
                }
                .listRowSeparator(.hidden, edges: .top)

                FieldGuidanceDisclosure(
                    title: "What helps most",
                    collapsed: $aiGuidanceCollapsed,
                    onToggle: {
                        aiGuidanceUserOverride = true
                        withAnimation(.easeInOut(duration: 0.2)) {
                            aiGuidanceCollapsed.toggle()
                        }
                    },
                    content: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• **Most impact**: a clear photo + hard facts.")
                            Text("• Add: brand/model, stamps/labels, materials, measurements, condition, quantity.")
                            Text("• Title helps; description adds context.")
                        }
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                    }
                )
                .padding(.bottom, 4)
            }

            // MARK: - 4. Supporting Information
            ItemPhotosSection(item: item) { image in
                photoPreviewItem = PhotoPreviewItem(filePath: image.filePath)
            }

            ItemDocumentsSection(item: item) { document in
                documentPreviewItem = DocumentPreviewItem(document: document)
            }

            ItemAudioSection(item: item)

            // MARK: - 5. Decisions & Next Steps
            ItemBeneficiariesSection(
                item: item,
                onAddTapped: { isBeneficiaryPickerPresented = true },
                onEditLink: { link in editingLinkItem = BeneficiaryEditItem(link: link) },
                onRemoveLink: { link in removeItemBeneficiary(link) }
            )

            if shouldShowLiquidate {
                Section {
                    NavigationLink {
                        LiquidationSectionView(item: item)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox.and.arrow.backward")
                                .foregroundStyle(Theme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Liquidate")
                                    .font(Theme.bodyFont.weight(.semibold))
                                    .foregroundStyle(Theme.text)

                                Text("Generate a Brief, choose an approach, and follow a checklist Plan.")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }

                    if FeatureFlags().dispositionEngineUI {
                        // Find Help: available with or without a Plan.
                        NavigationLink {
                            DispositionPartnersView(item: item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.2.wave.2")
                                    .foregroundStyle(Theme.accent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Find Help")
                                        .font(Theme.bodyFont.weight(.semibold))
                                        .foregroundStyle(Theme.text)

                                    Text("Find businesses that can help with this item.")
                                        .font(Theme.secondaryFont)
                                        .foregroundStyle(Theme.textSecondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Next Steps")
                        .ltcSectionHeaderStyle()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
        .sheet(item: $photoPreviewItem) { preview in
            photoPreviewSheet(for: preview.filePath)
        }
        .sheet(item: $documentPreviewItem) { preview in
            documentPreviewSheet(for: preview.document)
        }
        .sheet(isPresented: $isBeneficiaryPickerPresented) {
            BeneficiaryPickerSheet(item: item, user: item.user)
        }
        .sheet(item: $editingLinkItem) { editItem in
            ItemBeneficiaryEditSheet(link: editItem.link)
        }
        .sheet(isPresented: $isAIAnalysisPresented) {
            ItemAIAnalysisSheet(item: item)
        }
        .onChange(of: summaryPhotoSelection) {
            guard !summaryPhotoSelection.isEmpty else { return }
            let picked = summaryPhotoSelection
            Task { @MainActor in
                isAddingSummaryPhoto = true
                let succeeded = await ItemPhotoImporter.importPhotos(picked, into: item, context: modelContext)
                isAddingSummaryPhoto = false
                summaryPhotoSelection = []
                if !succeeded { summaryPhotoError = ItemPhotoImporter.failureMessage }
            }
        }
        .onChange(of: isDescriptionFocused) {
            if isDescriptionFocused { isDescriptionExpanded = true }
        }
        .onAppear {
            // Guidance starts collapsed; the owner's own choice is kept.
            if !fieldGuidanceUserOverride {
                fieldGuidanceCollapsed = true
            }
            if !aiGuidanceUserOverride {
                aiGuidanceCollapsed = true
            }
        }
        .onDisappear {
            saveContextIfNeeded()
        }
        .alert("Could not save changes", isPresented: $showSaveErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage ?? "Unknown error.")
        }
        .alert(
            "Photo Error",
            isPresented: Binding(
                get: { summaryPhotoError != nil },
                set: { if !$0 { summaryPhotoError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { summaryPhotoError = nil }
        } message: {
            Text(summaryPhotoError ?? "")
        }
    }

    // MARK: - Item Summary

    private var summaryHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            summaryPhoto

            VStack(alignment: .leading, spacing: 4) {
                TextField("Item name", text: $item.name, axis: .vertical)
                    .font(Theme.bodyFont.weight(.semibold))
                    .textInputAutocapitalization(.words)
                    .lineLimit(1...3)

                if let caption = attachmentCaption {
                    Text(caption)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var summaryPhoto: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        if let primary = item.primaryImage {
            Button {
                photoPreviewItem = PhotoPreviewItem(filePath: primary.filePath)
            } label: {
                Group {
                    if let uiImage = MediaStorage.loadImage(from: primary.filePath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Theme.textSecondary.opacity(0.15)
                            Image(systemName: "photo.slash")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .frame(width: summaryPhotoSize, height: summaryPhotoSize)
                .clipShape(shape)
                .overlay(shape.stroke(Theme.textSecondary.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Main photo")
            .accessibilityHint("Opens the photo.")
        } else {
            PhotosPicker(
                selection: $summaryPhotoSelection,
                maxSelectionCount: 10,
                matching: .images,
                photoLibrary: .shared()
            ) {
                VStack(spacing: 4) {
                    if isAddingSummaryPhoto {
                        ProgressView()
                    } else {
                        Image(systemName: "camera")
                            .font(.title3)
                        Text("Add Photo")
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(Theme.accent)
                .frame(width: summaryPhotoSize, height: summaryPhotoSize)
                .background(shape.fill(Theme.accent.opacity(0.08)))
                .overlay(shape.stroke(Theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.plain)
            .disabled(isAddingSummaryPhoto)
            .accessibilityLabel("Add photo")
        }
    }

    /// "3 photos · 1 document", pointing to Supporting Information below.
    private var attachmentCaption: String? {
        var parts: [String] = []
        let photos = item.orderedImages.count
        if photos > 0 { parts.append(photos == 1 ? "1 photo" : "\(photos) photos") }
        let documents = item.documents.count
        if documents > 0 { parts.append(documents == 1 ? "1 document" : "\(documents) documents") }
        let audio = item.audioRecordings.count
        if audio > 0 { parts.append(audio == 1 ? "1 audio story" : "\(audio) audio stories") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var descriptionEditor: some View {
        let showAll = isDescriptionExpanded || isDescriptionFocused || !isDescriptionLong

        return VStack(alignment: .leading, spacing: 6) {
            TextField("Description", text: $item.itemDescription, axis: .vertical)
                .font(Theme.bodyFont)
                .lineLimit(showAll ? 1...500 : 1...collapsedDescriptionLines)
                .focused($isDescriptionFocused)

            if isDescriptionLong && !isDescriptionFocused {
                Button(isDescriptionExpanded ? "Show less" : "Show full description") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDescriptionExpanded.toggle()
                    }
                }
                .font(Theme.secondaryFont.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Photo Preview Sheet (with Share)

    private func photoPreviewSheet(for filePath: String) -> some View {
        let url = MediaStorage.absoluteURL(from: filePath)

        return NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = MediaStorage.loadImage(from: filePath) {
                    ZoomableImageView(image: image)
                } else {
                    Text("Unable to load image.")
                        .foregroundStyle(.white)
                }
            }
            .onAppear { photoShareURL = url }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { photoPreviewItem = nil }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPhotoSharePresented = true } label: {
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
        if let index = item.itemBeneficiaries.firstIndex(where: { $0 === link }) {
            item.itemBeneficiaries.remove(at: index)
        }
        modelContext.delete(link)
        saveContextIfNeeded()
    }

    // MARK: - Helpers – Save

    private func saveContextIfNeeded() {
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }
}

// MARK: - Collapsible Guidance (local)

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

// MARK: - Document Preview Screen

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

                if isImageDoc {
                    Button { isSharePresented = true } label: {
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
                    Button("Done") { onDone() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isImageDoc {
                        Button { isSharePresented = true } label: {
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
                if scale < minScale { scale = minScale }
            }
    }

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

// MARK: - QuickLook wrapper

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

    func updateUIViewController(_ controller: QLPreviewController, context: Context) { }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Activity View

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
