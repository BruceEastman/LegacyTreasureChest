//
//  ItemAIAnalysisSheet.swift
//  LegacyTreasureChest
//
//  Improve with AI (LTC 1.3), two states:
//  1. Supply information: owner notes, category tips, optional additional
//     photos and one document chosen explicitly, and a summary of exactly
//     what will be sent. One "Analyze with AI" action.
//  2. Review suggestions (ImproveWithAIReviewView): current vs proposed with
//     per-field choices; nothing is saved until "Apply Selected".
//
//  The item's main photo and its details are included automatically; extra
//  photos and documents only when selected. Photos and documents added here
//  become normal item attachments whether or not suggestions are applied.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ItemAIAnalysisSheet: View {
    // We edit the existing item; changes auto-save because this is a bound model.
    @Bindable var item: LTCItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var model: ImproveWithAIModel
    @StateObject private var consentGate = AIConsentGate()

    /// Extra owner-supplied details that should help the AI value this item.
    /// Stored in ItemValuation.userNotes so it persists per item.
    @State private var extraDetailsText: String = ""

    /// Navigation to editor (instead of a nested sheet).
    @State private var showExtraDetailsEditor: Bool = false

    @State private var showAllTips = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isImportingPhotos = false
    @State private var isDocumentImporterPresented = false
    @State private var previewDocument: Document?
    @State private var noticeMessage: String?
    @State private var confirmDiscardReview = false

    init(item: LTCItem) {
        self.item = item
        _model = State(initialValue: ImproveWithAIModel(item: item))
    }

    /// Test/preview hook: a model with an injected analyzer.
    init(item: LTCItem, model: ImproveWithAIModel) {
        self.item = item
        _model = State(initialValue: model)
    }

    private var isReviewing: Bool {
        if case .review = model.phase { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .compose, .analyzing:
                    composeView
                case .review(let analysis, let review):
                    ImproveWithAIReviewView(
                        model: model,
                        analysis: analysis,
                        review: review,
                        onApply: applyAndClose,
                        onKeepCurrent: { dismiss() }
                    )
                }
            }
            .navigationTitle(isReviewing ? "Review Suggestions" : "Improve with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isReviewing {
                        Button("Back") { confirmDiscardReview = true }
                    } else {
                        Button("Close") {
                            model.cancelAnalysis()
                            dismiss()
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showExtraDetailsEditor) {
                ExtraDetailsEditorView(
                    title: "More Details",
                    prompt: extraDetailsHelpText,
                    placeholder: extraDetailsPlaceholderText,
                    text: $extraDetailsText,
                    onSaveAndDismiss: {
                        // ✅ Persist immediately when leaving the editor
                        saveExtraDetailsToValuation()
                    }
                )
            }
            .confirmationDialog(
                "Go back without applying?",
                isPresented: $confirmDiscardReview,
                titleVisibility: .visible
            ) {
                Button("Discard Suggestions", role: .destructive) { model.discardReview() }
                Button("Stay", role: .cancel) { }
            } message: {
                Text("Nothing has been changed on this item. You can analyze again after going back.")
            }
            .sheet(item: $previewDocument) { document in
                DocumentPreviewScreen(
                    document: document,
                    url: MediaStorage.absoluteURL(from: document.filePath),
                    onDone: { previewDocument = nil }
                )
            }
            .fileImporter(isPresented: $isDocumentImporterPresented, allowedContentTypes: [.pdf]) { result in
                importDocument(result)
            }
            .onChange(of: photoPickerItems) {
                importPickedPhotos()
            }
            .onAppear {
                loadExtraDetailsIfNeeded()
                model.refreshPlan()
            }
            .aiConsentSheet(consentGate)
        }
        .tint(Theme.accent)
        // Leaving the review must be a deliberate choice (Apply, Keep, Back).
        .interactiveDismissDisabled(isReviewing || model.isAnalyzing)
    }

    // MARK: - State 1: Supply information

    private var composeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {
                headerCard

                if let error = model.errorMessage {
                    messageCard(error, systemImage: "exclamationmark.triangle", tint: Theme.destructive)
                }

                notesSection
                photosSection
                documentSection
                summarySection

                Spacer(minLength: 24)
            }
            .padding(.horizontal, Theme.spacing.large)
            .padding(.top, Theme.spacing.medium)
            .disabled(model.isAnalyzing)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { analyzeBar }
        .overlay {
            if model.isAnalyzing { analyzingOverlay }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            HStack(alignment: .center, spacing: 12) {
                thumbnail(for: item.primaryImage, size: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? "Untitled Item" : item.name)
                        .font(Theme.bodyFont.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Text(item.quantity > 1 ? "\(item.category) · ×\(item.quantity)" : item.category)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            Text(item.primaryImage != nil
                 ? "The main photo is included automatically."
                 : "No main photo. The analysis uses the item's details and anything you add below.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ltcCardBackground()
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Details You Know")
                .ltcSectionHeaderStyle()

            Text(showAllTips ? extraDetailsHelpText : tipsSummary)
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(showAllTips ? "Fewer tips" : "More tips") {
                withAnimation(.easeInOut(duration: 0.2)) { showAllTips.toggle() }
            }
            .font(Theme.secondaryFont.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)

            Button {
                showExtraDetailsEditor = true
            } label: {
                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    if extraDetailsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(extraDetailsPlaceholderText)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                            .lineLimit(3)
                    } else {
                        Text(extraDetailsText)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.text)
                            .lineLimit(6)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                        Text("Tap to edit")
                    }
                    .font(Theme.secondaryFont.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .ltcCardBackground()
        }
    }

    /// The category help without its generic first sentence.
    private var tipsSummary: String {
        let text = extraDetailsHelpText
        if let range = text.range(of: "Helpful information includes ") {
            let rest = text[range.upperBound...]
            return "Helpful: " + rest
        }
        return text
    }

    // MARK: Photos

    private var photosSection: some View {
        let others = item.supplementaryImages
        let selectedCount = model.selectedPhotoIDs.count

        return VStack(alignment: .leading, spacing: Theme.spacing.small) {
            HStack {
                Text("Additional Photos")
                    .ltcSectionHeaderStyle()
                Spacer()
                Text("\(selectedCount) of \(model.limits.maxSupplementaryPhotos) selected")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("Optional. Choose photos of maker's marks, labels, stamps, or other details.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                if others.isEmpty {
                    Text("No other photos of this item yet.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(others, id: \.imageId) { image in
                                photoChoice(image)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                PhotosPicker(
                    selection: $photoPickerItems,
                    maxSelectionCount: model.limits.maxSupplementaryPhotos,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack {
                        if isImportingPhotos { ProgressView() } else { Image(systemName: "plus") }
                        Text("Add Photo")
                            .font(Theme.secondaryFont.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isImportingPhotos)

                if let noticeMessage {
                    Text(noticeMessage)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.destructive)
                }
            }
            .ltcCardBackground()
        }
    }

    private func photoChoice(_ image: ItemImage) -> some View {
        let selected = model.isPhotoSelected(image.imageId)
        return Button {
            noticeMessage = model.togglePhoto(image.imageId)
                ? nil
                : "You can include up to \(model.limits.maxSupplementaryPhotos) additional photos."
        } label: {
            thumbnail(for: image, size: 76)
                .opacity(selected ? 1 : 0.55)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Theme.accent : Color.white)
                        .background(Circle().fill(selected ? Color.white : Color.black.opacity(0.25)))
                        .padding(4)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Theme.accent : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "Additional photo, selected" : "Additional photo, not selected")
        .accessibilityHint("Double tap to \(selected ? "remove it from" : "include it in") the analysis.")
    }

    // MARK: Document

    private var documentChoices: [Document] {
        item.documents
            .filter { !$0.isDeleted }
            .filter { ["PDF", "IMAGE"].contains($0.documentType.uppercased()) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var documentSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Document")
                .ltcSectionHeaderStyle()

            Text("Optional. Choose one PDF or image, such as an appraisal, certificate, or receipt.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                if documentChoices.isEmpty {
                    Text("No documents attached to this item yet.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                ForEach(documentChoices, id: \.documentId) { document in
                    documentRow(document)
                }

                Button {
                    isDocumentImporterPresented = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add PDF")
                            .font(Theme.secondaryFont.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .ltcCardBackground()
        }
    }

    private func documentRow(_ document: Document) -> some View {
        let selected = model.selectedDocumentID == document.documentId
        let planned = model.plan?.documents.first { $0.documentId == document.documentId }

        return HStack(spacing: 10) {
            Button {
                model.toggleDocument(document.documentId)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                    Image(systemName: document.documentType.uppercased() == "PDF" ? "doc.richtext" : "photo")
                        .foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName(for: document))
                            .font(Theme.bodyFont)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let planned {
                            Text(planned.totalPages == 1 ? "1 page" : "\(planned.totalPages) pages")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(displayName(for: document)), \(selected ? "selected" : "not selected")")

            if selected {
                Button("Preview") { previewDocument = document }
                    .font(Theme.secondaryFont.weight(.semibold))
                    .buttonStyle(.bordered)
            }
        }
    }

    private func displayName(for document: Document) -> String {
        if let name = document.originalFilename, !name.isEmpty { return name }
        return (document.filePath as NSString).lastPathComponent
    }

    // MARK: Summary of what will be sent

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("What Will Be Sent")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: 8) {
                if let error = model.planError {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.destructive)
                } else if let plan = model.plan {
                    ForEach(summaryLines(plan), id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                            Text(line).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.text)
                    }

                    if let truncated = plan.truncatedDocuments.first {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("“\(truncated.displayName)” has \(truncated.totalPages) pages. Only the first \(truncated.pagesToSend) will be analyzed.",
                                  systemImage: "doc.on.doc")
                                .font(Theme.secondaryFont.weight(.semibold))
                                .foregroundStyle(Theme.text)
                            Toggle("Analyze the first \(truncated.pagesToSend) pages", isOn: $model.acknowledgedTruncation)
                                .font(Theme.secondaryFont)
                                .tint(Theme.accent)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.10)))
                    }

                    if !plan.documents.isEmpty {
                        Text("Everything visible on the document's pages, including names, addresses, and report or certificate numbers, is sent to Google Gemini for this analysis. LTC's server does not keep it.")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if plan.isTextOnly && !model.hasTextToAnalyze {
                        Text("Add a name, description, notes, photo, or document before analyzing.")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.destructive)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ltcCardBackground()
        }
    }

    private func summaryLines(_ plan: AIEvidencePlan) -> [String] {
        var lines: [String] = []
        if plan.includesPrimaryPhoto { lines.append("The main photo") }
        let photos = plan.supplementaryPhotoCount
        if photos > 0 { lines.append(photos == 1 ? "1 additional photo" : "\(photos) additional photos") }
        for doc in plan.documents {
            let pages = doc.pagesToSend == 1 ? "1 page" : "\(doc.pagesToSend) pages"
            lines.append("“\(doc.displayName)” (\(pages), as images)")
        }
        if plan.isTextOnly { lines.append("No photos: the analysis uses text only") }
        lines.append("The item's name, category, quantity, and description, and your notes")
        return lines
    }

    // MARK: Analyze

    private var analyzeBar: some View {
        Button {
            startAnalysis()
        } label: {
            HStack {
                Image(systemName: "sparkles")
                Text("Analyze with AI")
                    .font(Theme.bodyFont.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(model.canAnalyze ? Theme.accent : Theme.textSecondary.opacity(0.35)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!model.canAnalyze)
        .padding(.horizontal, Theme.spacing.large)
        .padding(.vertical, Theme.spacing.small)
        .background(.thinMaterial)
    }

    private var analyzingOverlay: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Analyzing with AI…")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(model.plan?.hasSupplementaryEvidence == true
                     ? "With additional photos or a document this can take up to a minute."
                     : "This usually takes a few seconds.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Cancel") { model.cancelAnalysis() }
                    .buttonStyle(.bordered)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
            .padding(40)
        }
    }

    private func startAnalysis() {
        // Persist extra details into ItemValuation.userNotes before running AI.
        saveExtraDetailsToValuation()
        model.refreshPlan()
        guard model.canAnalyze else { return }
        let requiresDisclosure = model.requiresEvidenceDisclosure
        Task {
            await consentGate.perform(requiresEvidenceDisclosure: requiresDisclosure) {
                model.startAnalysis()
            }
        }
    }

    private func applyAndClose() {
        guard model.apply() else { return }
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Imports (become normal item attachments)

    private func importPickedPhotos() {
        guard !photoPickerItems.isEmpty else { return }
        let picked = photoPickerItems
        let before = Set(item.images.map(\.imageId))
        isImportingPhotos = true
        Task { @MainActor in
            let ok = await ItemPhotoImporter.importPhotos(picked, into: item, context: modelContext)
            photoPickerItems = []
            isImportingPhotos = false
            let added = item.images
                .filter { !before.contains($0.imageId) }
                .sorted(by: ItemImage.isOrderedBefore)
            let slots = model.limits.maxSupplementaryPhotos - model.selectedPhotoIDs.count
            model.didImportPhotos(added)
            if !ok {
                noticeMessage = ItemPhotoImporter.failureMessage
            } else if added.count > slots {
                noticeMessage = "Added \(added.count) photos to the item. Only \(model.limits.maxSupplementaryPhotos) can be included in one analysis."
            } else {
                noticeMessage = nil
            }
        }
    }

    private func importDocument(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let document = try ItemDocumentImporter.importDocument(from: url, into: item, context: modelContext)
                model.didImportDocument(document)
            } catch {
                noticeMessage = error.localizedDescription
            }
        case .failure(let error):
            noticeMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func thumbnail(for image: ItemImage?, size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let image, let uiImage = MediaStorage.loadImage(from: image.filePath) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.textSecondary.opacity(0.12)
                    Image(systemName: image == nil ? "photo" : "photo.slash")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }

    private func messageCard(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                model.clearError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss message")
        }
        .font(Theme.secondaryFont)
        .foregroundStyle(tint)
        .ltcCardBackground()
    }

    // MARK: - Extra details helper text (category-aware)

    private var extraDetailsHelpText: String {
        switch item.category {
        case "Jewelry":
            return "Add any details you know that affect this jewelry item’s value, such as metal purity and weight, stone details, chain length, provenance, or certificates."
        case "Rug":
            return "Add any details you know that affect this rug’s value. Helpful information includes approximate knots per square inch (KPSI), materials (wool, silk, cotton foundation), origin, approximate age, condition, and where it was purchased."
        case "Luxury Personal Items":
            return "Add any details you know that affect this luxury item’s value. Helpful information includes brand, model or collection name, materials, condition, and whether you have the original box, papers, receipts, dust bag, or authenticity cards."
        case "Art":
            return "Add any details you know that affect this artwork’s value. Helpful information includes the artist’s name, title of the work, medium (oil, acrylic, print, photograph), whether it is an original or a print, any edition number, approximate size, condition, and where it was purchased."
        case "China & Crystal":
            return "Add any details you know that affect this china or crystal’s value. Helpful information includes the brand (for example, Waterford, Wedgwood, Royal Doulton, Lenox), pattern name, how many matching pieces or place settings you have, whether the pattern is discontinued, and any chips, cracks, or cloudiness."
        case "Furniture":
            return "Add any details you know that affect this furniture item’s value. Helpful information includes the maker or brand, approximate dimensions, wood or materials, age or era (for example, mid-century), any known designer or line, condition issues (scratches, stains, repairs), and whether it has been refinished or reupholstered."
        case "Electronics":
            return "Add any details you know that affect this electronic item’s value. Helpful information includes the brand and model, approximate year of purchase, key features (for example, 4K, SSD), whether it still works properly, and any notable wear or damage."
        case "Appliance":
            return "Add any details you know that affect this appliance’s value. Helpful information includes the brand and model, approximate age, whether it is in good working order, any major repairs, and any visible dents, rust, or wear."
        case "Tools":
            return "Add any details you know that affect this tool’s value. Helpful information includes the brand and model, tool type, whether it works properly, and whether batteries, chargers, or accessories are included."
        case "Clothing":
            return "Add any details you know that affect this clothing item’s value. Helpful information includes the brand, size, type of garment, whether it is designer or specialty (for example, wedding dress), and any stains, tears, or alterations."
        case "Luggage":
            return "Add any details you know that affect this luggage item’s value. Helpful information includes the brand, size, type (carry-on vs checked), materials, and the condition of wheels, handles, zippers, and interior."
        case "Decor":
            return "Add any details you know that affect this decor item’s value. Helpful information includes the maker or brand (if any), style (modern, traditional, mid-century, etc.), materials, size, and any chips, scratches, or wear."
        case "Collectibles":
            return "Add any details you know that affect this collectible’s value. Helpful information includes the maker or line (for example, Hummel, Lladro), character or subject, edition or year, whether the original box or certificates are included, and overall condition."
        case "Documents":
            return "Add any details you know about this document. Most documents have organizational value rather than monetary value, unless it is a signed or historical item. Helpful information includes whether it is signed, dated, and if it has any known historical or collectible significance."
        case "Uncategorized", "Other":
            return "Add any details you know that affect this item’s value, such as brand or maker, materials, size, age, condition, and where or how it was purchased. If it does not fit a normal category, briefly explain what it is used for."
        default:
            return "Add any details you know that affect this item’s value, such as brand or maker, materials, size, age, condition, and where or how it was purchased."
        }
    }

    private var extraDetailsPlaceholderText: String {
        switch item.category {
        case "Jewelry":
            return "Example: 14k gold chain, approx. 18\"; cross and chain ~8g total; diamond is ~1.2ct, G/VS2 with GIA certificate; purchased at a local jeweler around 1995."
        case "Rug":
            return "Example: Persian Luri hand-knotted rug, approx. 4.5 × 7 ft, ~290 KPSI on the back, wool and silk pile with cotton foundation, very good condition, purchased in a high-end rug gallery in San Francisco around 1995."
        case "Luxury Personal Items":
            return "Example: Cartier Panthère watch in yellow gold and steel, runs well, light surface wear on bracelet, no major scratches on crystal, includes original box but no papers, purchased in the mid-1990s."
        case "Art":
            return "Example: Signed oil painting on canvas by a local artist, approx. 24\" × 36\" including frame, good condition with no visible tears or flaking, purchased at a gallery in 2005 for around $1,200."
        case "China & Crystal":
            return "Example: Waterford Lismore pattern, 8 wine glasses and 8 water goblets, all matching, no chips or cracks, crystal still clear (no dishwasher haze), wedding gifts from the late 1980s, original boxes for 4 of the pieces."
        case "Furniture":
            return "Example: Mid-century teak sideboard, approx. 72\" wide, likely Danish, solid wood with veneer doors, original hardware, minor surface scratches, no major damage, purchased from a vintage furniture shop around 2010."
        case "Electronics":
            return "Example: Samsung 55\" 4K TV, purchased around 2018, works well, includes remote, no major screen damage, a few small cosmetic scuffs on the frame."
        case "Appliance":
            return "Example: Whirlpool front-load washer, purchased around 2016, still in good working order, minor cosmetic scratches on the side, no known major repairs."
        case "Tools":
            return "Example: DeWalt cordless drill, 20V platform, includes 2 batteries and charger, used for home projects only, still works well, light wear on housing."
        case "Clothing":
            return "Example: Women’s Burberry trench coat, size 8, classic tan color, lightly worn, no visible stains or tears, purchased around 2012."
        case "Luggage":
            return "Example: Samsonite hard-shell spinner suitcase, medium checked size, navy blue, all wheels and handles work, some scuffing from use but no cracks."
        case "Decor":
            return "Example: Large decorative wall mirror with gold-tone frame, approx. 36\" × 48\", traditional style, minor wear on frame edges, glass in good condition."
        case "Collectibles":
            return "Example: Hummel figurine, \"Apple Tree Boy\", with Goebel mark on base, no chips or cracks, original box included, purchased in the late 1980s."
        case "Documents":
            return "Example: Framed signed letter from a local public figure from the 1970s, original signature (not a copy), good condition, no major stains or tears."
        case "Uncategorized", "Other":
            return "Example: Unique handmade item from a local craft fair, wooden and metal materials, approx. 18\" tall, good condition, purchased around 2010."
        default:
            return "Example: Mid-century teak sideboard from Danish maker, approx. 72\" wide, original hardware, minor surface wear, purchased from a vintage furniture shop in 2015."
        }
    }

    // MARK: - Notes persistence

    private func loadExtraDetailsIfNeeded() {
        if let notes = item.valuation?.userNotes {
            extraDetailsText = notes
        }
    }

    /// Nothing is applied on failure; the message says so where relevant.
    static func userMessage(for error: Error) -> String {
        if let evidenceError = error as? AIEvidenceError {
            return evidenceError.localizedDescription
        }
        if let aiError = error as? AIError {
            switch aiError {
            case .evidenceRejected, .evidenceNotProcessed, .cancelled, .timeout, .offline, .consentRequired:
                return aiError.localizedDescription
            default:
                break
            }
        }
        let message = error.localizedDescription
        if message.contains("/ai/analyze-item-text") || message.contains("404") {
            return "Text-only analysis isn’t enabled on the backend yet. Photo analysis will continue to work."
        }
        return "AI analysis didn’t succeed this time. Nothing was saved. Please try again."
    }
    
    private func applyAnalysis(_ analysis: ItemAnalysis) {
        // Title, category, value and valuation are written as before. The
        // description keeps owner text and a single generated details line
        // (see ItemAnalysisApplier). Owner notes are not touched.
        ItemAnalysisApplier.apply(analysis, to: item)
        dismiss()
    }

    // MARK: - Valuation Mapping

    private func saveExtraDetailsToValuation() {
        let trimmed = extraDetailsText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if let valuation = item.valuation {
                valuation.userNotes = nil
                valuation.updatedAt = .now
            }
            return
        }

        let valuation: ItemValuation
        if let existing = item.valuation {
            valuation = existing
        } else {
            let defaultCurrency = Locale.current.currency?.identifier ?? "USD"
            valuation = ItemValuation(currencyCode: defaultCurrency)
            item.valuation = valuation
        }

        valuation.userNotes = trimmed
        valuation.updatedAt = .now
    }
}

// MARK: - Dedicated “More Details” editor (keyboard-safe)

private struct ExtraDetailsEditorView: View {
    let title: String
    let prompt: String
    let placeholder: String

    @Binding var text: String

    /// Called when the user leaves the editor (Done or back gesture) to persist changes upstream.
    let onSaveAndDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var keyboardInset: CGFloat = 0

    private var keyboardWillChange: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
    }

    private var keyboardWillHide: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
    }


    var body: some View {
        VStack(spacing: 0) {

            VStack(alignment: .leading, spacing: 16) {

                Text(prompt)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(Theme.bodyFont)
                        .focused($isFocused)
                        .frame(minHeight: 220)
                        .padding(12)

                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                            .padding(18)
                            .onTapGesture { isFocused = true }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(radius: 1)
                )
            }
            .padding()

            .onReceive(keyboardWillChange) { note in
                guard
                    let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return }

                // When keyboard is visible, use its height as bottom inset.
                // (Works well with .ignoresSafeArea(.keyboard))
                keyboardInset = frame.height
            }
            .onReceive(keyboardWillHide) { _ in
                keyboardInset = 0
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {

            // Nav Done = save + dismiss screen
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    onSaveAndDismiss()
                    dismiss()
                }
                .fontWeight(.semibold)
            }

            // Keyboard button = dismiss keyboard only (avoid double "Done" confusion)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide Keyboard") {
                    isFocused = false
                }
            }
        }


        // ✅ If user leaves via back swipe / back button, still save.
        .onDisappear {
            onSaveAndDismiss()
        }

        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isFocused = true
            }
        }
    }
}
