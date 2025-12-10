//
//  ItemAIAnalysisSheet.swift
//  LegacyTreasureChest
//
//  Sheet for analyzing an existing LTCItem with AI using its photo.
//  Uses the item's first image and current fields as hints,
//  then allows applying suggestions back onto the item.
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

    // Derived: whether the item has at least one image we can use.
    private var firstImagePath: String? {
        item.images.first?.filePath
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing.large) {

                    // Current item summary
                    currentItemCard

                    // Photo preview or guidance
                    photoSection

                    // Extra details for AI expert
                    extraDetailsSection

                    // Run analysis
                    analyzeButton

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.destructive)
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
            .navigationTitle("AI Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let result = analysisResult {
                        Button("Apply") {
                            applyAnalysis(result)
                        }
                    }
                }
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
                Text(item.name)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)

                if !item.itemDescription.isEmpty {
                    Text(item.itemDescription)
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
                    Text(item.value, format: .currency(code: currencyCode))
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
                Text("No photo found for this item. Add at least one photo in the Photos section, then run analysis again.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .ltcCardBackground()
            }
        }
    }

    /// Section where the user can provide extra details that matter for valuation.
    private var extraDetailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("More Details for AI Expert")
                .ltcSectionHeaderStyle()

            Text(extraDetailsHelpText)
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $extraDetailsText)
                    .font(Theme.secondaryFont)
                    .padding(8)

                if extraDetailsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(extraDetailsPlaceholderText)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                        .padding(12)
                }
            }
            .frame(minHeight: 120)
            .ltcCardBackground()
        }
    }

    private var analyzeButton: some View {
        Button {
            Task { await runAnalysis() }
        } label: {
            HStack {
                if isAnalyzing {
                    ProgressView()
                }
                Image(systemName: "sparkles")
                Text("Run Analysis")
                    .font(Theme.bodyFont.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.accent)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(.top, Theme.spacing.medium)
        .disabled(previewImage == nil || isAnalyzing)
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

            // Main value line
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

            // Confidence label (High / Medium / Low)
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
            // Improve this estimate (Missing details)
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

            // Why this range (AI Notes + provider + date)
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
                    Text("The AI based this estimate on similar items, materials, and visible condition in the photo.")
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
        guard let previewImage else {
            errorMessage = "No photo available for analysis."
            return
        }

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
            let result = try await AIService.shared.analyzeItemPhoto(previewImage, hints: hints)
            analysisResult = result
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }

    private func applyAnalysis(_ analysis: ItemAnalysis) {
        // Core fields
        item.name = analysis.title
        item.category = analysis.category

        // Build a richer description that includes key AI details.
        var descriptionLines: [String] = []
        descriptionLines.append(analysis.summary)

        var detailsParts: [String] = []

        if let maker = analysis.maker, !maker.isEmpty {
            detailsParts.append("Maker: \(maker)")
        }
        if let materialsArray = analysis.materials, !materialsArray.isEmpty {
            let joined = materialsArray.joined(separator: ", ")
            detailsParts.append("Materials: \(joined)")
        }
        if let style = analysis.style, !style.isEmpty {
            detailsParts.append("Style: \(style)")
        }
        if let condition = analysis.condition, !condition.isEmpty {
            detailsParts.append("Condition: \(condition)")
        }
        if let featuresArray = analysis.features, !featuresArray.isEmpty {
            let joined = featuresArray.joined(separator: ", ")
            detailsParts.append("Features: \(joined)")
        }

        if !detailsParts.isEmpty {
            let detailsLine = detailsParts.joined(separator: " • ")
            descriptionLines.append("")              // blank line between summary and details
            descriptionLines.append(detailsLine)
        }

        item.itemDescription = descriptionLines.joined(separator: "\n")

        // Value: use ValueHints if present for item.value and ItemValuation.
        if let valueHints = analysis.valueHints {
            // 1) Update the item's simple numeric value.
            let mid: Double? = {
                if let est = valueHints.estimatedValue {
                    return est
                }
                if let low = valueHints.valueLow, let high = valueHints.valueHigh {
                    return (low + high) / 2.0
                }
                if let low = valueHints.valueLow {
                    return low
                }
                if let high = valueHints.valueHigh {
                    return high
                }
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

            // 2) Upsert the ItemValuation record.
            upsertValuation(from: valueHints)
        }

        // Store AI metadata for future use.
        item.llmGeneratedTitle = analysis.title
        item.llmGeneratedDescription = analysis.summary

        // Close sheet after applying.
        dismiss()
    }

    // MARK: - Valuation Mapping

    /// Persist extra details into ItemValuation.userNotes so they survive across runs.
    private func saveExtraDetailsToValuation() {
        let trimmed = extraDetailsText.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the user cleared the field and we have a valuation, clear the notes.
        if trimmed.isEmpty {
            if let valuation = item.valuation {
                valuation.userNotes = nil
                valuation.updatedAt = .now
            }
            return
        }

        // Ensure there is a valuation object to hang these notes on.
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

    /// Create or update the item's ItemValuation from backend ValueHints.
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
        // Preserve any existing userNotes; we never overwrite them from AI.
        valuation.missingDetails = hints.missingDetails ?? valuation.missingDetails

        if let dateString = hints.valuationDate {
            valuation.valuationDate = parseISO8601Date(dateString)
        }

        valuation.updatedAt = .now
    }

    /// Parse ISO 8601 timestamps like "2025-12-08T21:57:15.698594Z".
    private func parseISO8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }

    // MARK: - Helpers

    /// Simple currency formatter that respects the provided ISO 4217 code.
    private func formattedCurrency(_ value: Double, code: String) -> String {
        let intValue = Int(value.rounded())
        return "\(intValue) \(code)"
    }

    /// Map confidence score into a human-readable label.
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

// MARK: - Preview

#if DEBUG
private let itemAIAnalysisPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = ModelContext(container)

    let sample = LTCItem(
        name: "Sample Item",
        itemDescription: "Sample description for AI analysis preview.",
        category: "Jewelry",
        value: 250
    )

    context.insert(sample)

    return container
}()

#Preview {
    let container = itemAIAnalysisPreviewContainer
    let context = ModelContext(container)

    let descriptor = FetchDescriptor<LTCItem>()
    let items = (try? context.fetch(descriptor)) ?? []

    return NavigationStack {
        if let first = items.first {
            ItemAIAnalysisSheet(item: first)
        } else {
            Text("No preview item")
        }
    }
    .modelContainer(container)
}
#endif
