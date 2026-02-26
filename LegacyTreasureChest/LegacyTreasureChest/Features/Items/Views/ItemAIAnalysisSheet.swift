//
//  ItemAIAnalysisSheet.swift
//  LegacyTreasureChest
//
//  Sheet for analyzing an existing LTCItem with AI.
//  - If photo exists: uses photo-based analysis
//  - If no photo: uses text-only analysis (title/description/category + extra details)
//

import SwiftUI
import SwiftData
import UIKit

struct ItemAIAnalysisSheet: View {
    // We edit the existing item; changes auto-save because this is a bound model.
    @Bindable var item: LTCItem

    @Environment(\.dismiss) private var dismiss

    @State private var previewImage: UIImage?
    @State private var isAnalyzing: Bool = false
    @State private var analysisResult: ItemAnalysis?
    @State private var errorMessage: String?

    /// Extra owner-supplied details that should help the AI value this item.
    /// Stored in ItemValuation.userNotes so it persists per item.
    @State private var extraDetailsText: String = ""

    /// Navigation to editor (instead of a nested sheet).
    @State private var showExtraDetailsEditor: Bool = false

    // Derived: whether the item has at least one image we can use.
    private var firstImagePath: String? {
        item.images.first?.filePath
    }

    private var hasPhoto: Bool { previewImage != nil }

    /// Require at least a title or a description for text-only.
    private var hasEnoughTextForTextOnly: Bool {
        let title = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty || !desc.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing.large) {

                    // Current item summary
                    currentItemCard

                    // Mode explanation (photo vs text-only)
                    analysisModeCard

                    // Photo preview or guidance
                    photoSection

                    // Extra details for AI expert
                    extraDetailsSection

                    // Run analysis
                    analyzeButton

                    if let errorMessage {
                        VStack(alignment: .leading, spacing: Theme.spacing.small) {
                            Text(errorMessage)
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.destructive)

                            if !isAnalyzing {
                                Button(action: {
                                    Task { await runAnalysis() }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Try Again")
                                            .font(Theme.secondaryFont.weight(.semibold))
                                    }
                                }
                            }
                        }
                        .padding()
                        .ltcCardBackground()
                    }
                    if let result = analysisResult {
                        analysisCard(result)

                        Button {
                            applyAnalysis(result)
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Apply Suggestions to Item")
                                    .font(Theme.bodyFont.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.primary)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.top, Theme.spacing.medium)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, Theme.spacing.large)
                .padding(.top, Theme.spacing.large)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("AI Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let result = analysisResult {
                        Button("Apply") { applyAnalysis(result) }
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
            .onAppear {
                loadPreviewImageIfNeeded()
                loadExtraDetailsIfNeeded()
            }
        }
    }

    // MARK: - Subviews

    private var currentItemCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Current Item")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                Text(item.name.isEmpty ? "Untitled Item" : item.name)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)

                if !item.itemDescription.isEmpty {
                    Text(item.itemDescription)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Add a short description to improve text-only analysis.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                if !item.category.isEmpty {
                    Text("Category: \(item.category)")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                if item.value > 0 {
                    let currencyCode = Locale.current.currency?.identifier ?? "USD"
                    CurrencyText.view(item.value)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .ltcCardBackground()
        }
    }

    private var analysisModeCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("How This Will Run")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                if hasPhoto {
                    Text("Photo-based analysis")
                        .font(Theme.bodyFont.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("This uses your photo plus any details you’ve added. Best accuracy.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Text-only analysis (no photo yet)")
                        .font(Theme.bodyFont.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("You can run an estimate now using title/description/category. Add photos later to improve confidence.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .ltcCardBackground()
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Photo Used for Analysis")
                .ltcSectionHeaderStyle()

            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 2)
            } else {
                Text("No photo found for this item. You can still run text-only analysis now. Add a photo later for better accuracy.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .ltcCardBackground()
            }
        }
    }

    /// Section where the user can provide extra details that matter for valuation.
    /// We navigate to a dedicated editor (no nested sheet).
    private var extraDetailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("More Details for AI Expert")
                .ltcSectionHeaderStyle()

            Text(extraDetailsHelpText)
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)

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

    private var analyzeButton: some View {
        Button {
            Task { await runAnalysis() }
        } label: {
            HStack {
                if isAnalyzing { ProgressView() }
                Image(systemName: "sparkles")
                Text(isAnalyzing ? "Analyzing…" : (hasPhoto ? "Run Analysis" : "Run Text-Only Analysis"))
                    .font(Theme.bodyFont.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.accent)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(.top, Theme.spacing.medium)
        .disabled(isAnalyzing || (!hasPhoto && !hasEnoughTextForTextOnly))
    }

    @ViewBuilder
    private func analysisCard(_ result: ItemAnalysis) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {

            // 1. Valuation Summary (if available)
            if let valueHints = result.valueHints {
                valuationSummarySection(valueHints)
                Divider()
            }

            // 2. AI Suggestions (title / summary / category / tags)
            suggestionsSection(result)

            // 3. Valuation details, missing details, AI notes
            if let valueHints = result.valueHints {
                Divider()
                valuationDetailsSection(valueHints)
            }

            // 4. Item details (brand, maker, materials, etc.)
            Divider()
            itemDetailsSection(result)

            // 5. Extracted text (if present)
            if let text = result.extractedText,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                extractedTextSection(text)
            }
        }
        .ltcCardBackground()
        .padding(.top, Theme.spacing.large)
    }

    // MARK: - Analysis Sections

    private func valuationSummarySection(_ value: ValueHints) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Valuation Summary")
                .ltcSectionHeaderStyle()

            if let low = value.valueLow, let high = value.valueHigh {
                Text("\(formattedCurrency(low, code: value.currencyCode)) – \(formattedCurrency(high, code: value.currencyCode))")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
            } else if let est = value.estimatedValue {
                Text(formattedCurrency(est, code: value.currencyCode))
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
            } else {
                Text("No value estimate available")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let confidenceLabel = confidenceDescription(for: value.confidenceScore) {
                Text("Confidence: \(confidenceLabel)")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func suggestionsSection(_ result: ItemAnalysis) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("AI Suggestions")
                .ltcSectionHeaderStyle()

            Text(result.title)
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)

            Text(result.summary)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)

            Text("Category: \(result.category)")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.text)

            let tagsText = (result.tags ?? []).joined(separator: ", ")
            if !tagsText.isEmpty {
                Text("Tags: \(tagsText)")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let c = result.confidence {
                Text(String(format: "Overall analysis confidence: %.2f", c))
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func valuationDetailsSection(_ value: ValueHints) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            if let missing = value.missingDetails, !missing.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Improve This Estimate")
                        .ltcSectionHeaderStyle()

                    Text("For a more precise value, the AI suggests providing:")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)

                    ForEach(missing, id: \.self) { detail in
                        Text("• \(detail)")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                Text("Why This Estimate")
                    .ltcSectionHeaderStyle()

                if let provider = value.aiProvider, !provider.isEmpty {
                    Text("Provider: \(provider)")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let updated = value.valuationDate, !updated.isEmpty {
                    Text("Valuation Date: \(updated)")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let notes = value.aiNotes,
                   !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(notes)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("The AI based this estimate on similar items, materials, and visible condition (or your text details if no photo).")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func itemDetailsSection(_ result: ItemAnalysis) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Item Details")
                .ltcSectionHeaderStyle()

            detailRow(label: "Brand", value: result.brand)
            detailRow(label: "Model", value: result.modelNumber)
            detailRow(label: "Maker", value: result.maker)

            let materials = (result.materials ?? []).joined(separator: ", ")
            if !materials.isEmpty {
                detailRow(label: "Materials", value: materials)
            }

            detailRow(label: "Style", value: result.style)
            detailRow(label: "Origin", value: result.origin)
            detailRow(label: "Condition", value: result.condition)
            detailRow(label: "Dimensions", value: result.dimensions)
            detailRow(label: "Era / Year", value: result.eraOrYear)

            let features = (result.features ?? []).joined(separator: ", ")
            if !features.isEmpty {
                detailRow(label: "Features", value: features)
            }
        }
    }

    private func extractedTextSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Extracted Text")
                .font(Theme.bodyFont.weight(.semibold))
            Text(text)
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: Theme.spacing.small) {
                Text("\(label):")
                    .font(Theme.secondaryFont.weight(.semibold))
                Text(value)
                    .font(Theme.secondaryFont)
            }
            .foregroundStyle(Theme.text)
        }
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

    // MARK: - Logic

    private func loadPreviewImageIfNeeded() {
        guard let path = firstImagePath else { return }
        previewImage = MediaStorage.loadImage(from: path)
    }

    /// Load any previously-saved extra details from the current valuation.
    private func loadExtraDetailsIfNeeded() {
        if let notes = item.valuation?.userNotes {
            extraDetailsText = notes
        }
    }

    private func runAnalysis() async {
        // Persist extra details into ItemValuation.userNotes before running AI.
        saveExtraDetailsToValuation()

        isAnalyzing = true
        errorMessage = nil
        analysisResult = nil

        // Base description from the item.
        let baseDescription = item.itemDescription.isEmpty ? nil : item.itemDescription

        // Extra owner details from the current valuation.
        let extraDetails = item.valuation?.userNotes?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let combinedDescription: String?
        if let base = baseDescription, let extra = extraDetails, !extra.isEmpty {
            combinedDescription = base + "\n\nAdditional details from owner:\n" + extra
        } else if let extra = extraDetails, !extra.isEmpty {
            combinedDescription = "Additional details from owner:\n" + extra
        } else {
            combinedDescription = baseDescription
        }

        let hints = ItemAIHints(
            userWrittenTitle: item.name.isEmpty ? nil : item.name,
            userWrittenDescription: combinedDescription,
            knownCategory: item.category.isEmpty ? nil : item.category
        )

        do {
            if let previewImage {
                // Photo path (existing behavior)
                let result = try await AIService.shared.analyzeItemPhoto(previewImage, hints: hints)
                analysisResult = result
            } else {
                // Text-only path (new)
                let result = try await AIService.shared.analyzeItemText(hints: hints)
                analysisResult = result
            }
        } catch {
            // Keep full detail for debugging, but avoid surfacing raw 502/body in the UI.
            print("ItemAIAnalysisSheet runAnalysis error:", error)

            let message = error.localizedDescription
            if message.contains("/ai/analyze-item-text") || message.contains("404") {
                errorMessage = "Text-only analysis isn’t enabled on the backend yet. Photo analysis will continue to work."
            } else {
                errorMessage = "AI analysis didn’t succeed this time. Nothing was saved. Please try again."
            }
        }

        isAnalyzing = false
    }
    
    private func applyAnalysis(_ analysis: ItemAnalysis) {
        item.name = analysis.title
        item.category = analysis.category

        var descriptionLines: [String] = []
        descriptionLines.append(analysis.summary)

        var detailsParts: [String] = []

        if let maker = analysis.maker, !maker.isEmpty {
            detailsParts.append("Maker: \(maker)")
        }
        if let materialsArray = analysis.materials, !materialsArray.isEmpty {
            detailsParts.append("Materials: \(materialsArray.joined(separator: ", "))")
        }
        if let style = analysis.style, !style.isEmpty {
            detailsParts.append("Style: \(style)")
        }
        if let condition = analysis.condition, !condition.isEmpty {
            detailsParts.append("Condition: \(condition)")
        }
        if let featuresArray = analysis.features, !featuresArray.isEmpty {
            detailsParts.append("Features: \(featuresArray.joined(separator: ", "))")
        }

        if !detailsParts.isEmpty {
            descriptionLines.append("")
            descriptionLines.append(detailsParts.joined(separator: " • "))
        }

        item.itemDescription = descriptionLines.joined(separator: "\n")

        if let valueHints = analysis.valueHints {
            let mid: Double? = {
                if let est = valueHints.estimatedValue { return est }
                if let low = valueHints.valueLow, let high = valueHints.valueHigh { return (low + high) / 2.0 }
                if let low = valueHints.valueLow { return low }
                if let high = valueHints.valueHigh { return high }
                return nil
            }()

            if let mid, mid > 0 {
                item.value = mid
            }

            if let high = valueHints.valueHigh {
                item.suggestedPriceNew = high
            } else if let est = valueHints.estimatedValue {
                item.suggestedPriceNew = est
            }

            if let low = valueHints.valueLow {
                item.suggestedPriceUsed = low
            } else if let est = valueHints.estimatedValue {
                item.suggestedPriceUsed = est
            }

            upsertValuation(from: valueHints)
        }

        item.llmGeneratedTitle = analysis.title
        item.llmGeneratedDescription = analysis.summary

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

    private func upsertValuation(from hints: ValueHints) {
        let valuation: ItemValuation

        if let existing = item.valuation {
            valuation = existing
        } else {
            valuation = ItemValuation(currencyCode: hints.currencyCode)
            item.valuation = valuation
        }

        valuation.valueLow = hints.valueLow
        valuation.estimatedValue = hints.estimatedValue
        valuation.valueHigh = hints.valueHigh
        valuation.currencyCode = hints.currencyCode
        valuation.confidenceScore = hints.confidenceScore
        valuation.aiProvider = hints.aiProvider
        valuation.aiNotes = hints.aiNotes
        valuation.missingDetails = hints.missingDetails ?? valuation.missingDetails

        if let dateString = hints.valuationDate {
            valuation.valuationDate = parseISO8601Date(dateString)
        }

        valuation.updatedAt = .now
    }

    private func parseISO8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }

    private func formattedCurrency(_ value: Double, code: String) -> String {
        let intValue = Int(value.rounded())
        return "\(intValue) \(code)"
    }

    private func confidenceDescription(for score: Double?) -> String? {
        guard let score else { return nil }
        let numeric = String(format: "%.2f", score)

        switch score {
        case 0.8...1.0:
            return "High (\(numeric))"
        case 0.5..<0.8:
            return "Medium (\(numeric))"
        case 0..<0.5:
            return "Low (\(numeric))"
        default:
            return numeric
        }
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
