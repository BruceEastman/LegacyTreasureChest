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

    // AI analysis sheet
    @State private var isAIAnalysisPresented: Bool = false

    // surface save failures (prevents “disappearing” edits)
    @State private var saveErrorMessage: String?
    @State private var showSaveErrorAlert: Bool = false

    // Base category options (centralized via LTCItem.baseCategories)
    private let defaultCategories: [String] = LTCItem.baseCategories

    // Progressive disclosure persistence (shared across screens)
    @AppStorage("ltc_fieldGuidanceCollapsed") private var fieldGuidanceCollapsed: Bool = false
    @AppStorage("ltc_fieldGuidanceUserOverride") private var fieldGuidanceUserOverride: Bool = false
    @AppStorage("ltc_aiGuidanceCollapsed") private var aiGuidanceCollapsed: Bool = false
    @AppStorage("ltc_aiGuidanceUserOverride") private var aiGuidanceUserOverride: Bool = false
    @AppStorage("ltc_itemCreationCount") private var itemCreationCount: Int = 0

    private let autoCollapseThreshold: Int = 5

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

    // MARK: - Liquidate (optional gating)

    /// Set to `true` if you want to hide Liquidate unless Market AI is enabled.
    /// For now, default is `false` so Liquidate is always reachable and can fall back locally.
    private var gateLiquidateOnMarketAI: Bool { false }

    private var shouldShowLiquidate: Bool {
        if gateLiquidateOnMarketAI {
            return FeatureFlags().enableMarketAI
        }
        return true
    }

    var body: some View {
        Form {
            // MARK: - Basic Info

            Section {
                TextField("Name", text: $item.name)
                    .textInputAutocapitalization(.words)
                    .font(Theme.bodyFont)

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
                            Text("• **Description**: what it is + traits + story.")
                            Text("  Save hard facts (stamps, size, condition, quantity) for AI details.")
                        }
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                    }
                )

                TextField("Description", text: $item.itemDescription, axis: .vertical)
                    .font(Theme.bodyFont)
            } header: {
                Text("Basic Info")
                    .ltcSectionHeaderStyle()
            }

            // MARK: - Details

            Section {
                Picker("Category", selection: $item.category) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Text(category)
                            .font(Theme.bodyFont)
                            .tag(category)
                    }
                }

                // Quantity
                Stepper(value: $item.quantity, in: 1...999) {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        Text("×\(max(item.quantity, 1))")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                TextField(
                    "Estimated Unit Value",
                    value: $item.value,
                    format: .currency(code: currencyCode)
                )
                .keyboardType(.decimalPad)
                .font(Theme.bodyFont)

                if max(item.quantity, 1) > 1 {
                    let qty = Double(max(item.quantity, 1))
                    let unit = max(item.valuation?.estimatedValue ?? item.value, 0)
                    let total = unit * qty
                    Text("Total: \(total, format: .currency(code: currencyCode)) (\(unit, format: .currency(code: currencyCode)) each)")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Details")
                    .ltcSectionHeaderStyle()
            }

            // MARK: - AI Assistance

            Section {
                FieldGuidanceDisclosure(
                    title: "AI Guidance",
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

                Button {
                    isAIAnalysisPresented = true
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Improve with AI")
                            .font(Theme.bodyFont.weight(.semibold))
                    }
                }
                .disabled(item.images.isEmpty)
            } header: {
                Text("AI Assistance")
                    .ltcSectionHeaderStyle()
            } footer: {
                if item.images.isEmpty {
                    Text("Add at least one photo in the Photos section to enable AI analysis.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Use AI to refine the title, description, category, and estimated value using your photos and added details.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // MARK: - Photos

            ItemPhotosSection(item: item) { image in
                photoPreviewItem = PhotoPreviewItem(filePath: image.filePath)
            }

            // MARK: - Documents

            ItemDocumentsSection(item: item) { document in
                documentPreviewItem = DocumentPreviewItem(document: document)
            }

            // MARK: - Audio

            ItemAudioSection(item: item)

            // MARK: - Beneficiaries

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

            // MARK: - Liquidate (Next Step)

            if shouldShowLiquidate {
                Section {

                    // Row 1: Liquidate
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

                                Text("Generate a brief, choose a path, and follow a checklist plan.")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()

                            
                        }
                        .padding(.vertical, 4)
                    }

                    // Row 2: Local Help (Disposition Engine)
                    if FeatureFlags().dispositionEngineUI {
                        NavigationLink {
                            DispositionPartnersView(item: item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.2.wave.2")
                                    .foregroundStyle(Theme.accent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Local Help")
                                        .font(Theme.bodyFont.weight(.semibold))
                                        .foregroundStyle(Theme.text)

                                    Text("Find nearby services for this item (advisor mode).")
                                        .font(Theme.secondaryFont)
                                        .foregroundStyle(Theme.textSecondary)
                                }

                                Spacer()

                            
                            }
                            .padding(.vertical, 4)
                        }
                    }

                } header: {
                    Text("Next Step")
                        .ltcSectionHeaderStyle()
                } footer: {
                    Text("Liquidation uses backend-first AI for both Brief and Plan, with local fallback only when the backend fails.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // MARK: - Footer

            Section {
                EmptyView()
            } footer: {
                Text("In future versions, you’ll be able to fully manage photos, documents, audio stories, and beneficiaries for this item.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Theme.spacing.small)
            }
        }
        .scrollContentBackground(.hidden)
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
        .onAppear {
            // Auto-collapse after threshold unless the user has explicitly overridden.
            if !fieldGuidanceUserOverride {
                fieldGuidanceCollapsed = itemCreationCount >= autoCollapseThreshold
            }
            if !aiGuidanceUserOverride {
                aiGuidanceCollapsed = itemCreationCount >= autoCollapseThreshold
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
