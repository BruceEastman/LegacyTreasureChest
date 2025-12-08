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
            Text("AI Suggestions")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                Text(result.title)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)

                Text(result.summary)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)

                Text("Category: \(result.category)")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.text)
            }

            Divider()

            // Tags / confidence
            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                let tagsText = (result.tags ?? []).joined(separator: ", ")
                if !tagsText.isEmpty {
                    Text("Tags: \(tagsText)")
                        .font(Theme.secondaryFont)
                }

                if let c = result.confidence {
                    Text(String(format: "Confidence: %.2f", c))
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // Value hints (ValueHints model)
            if let value = result.valueHints {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Value Estimate (\(value.currencyCode))")
                        .font(Theme.bodyFont.weight(.semibold))

                    // Range / point estimate
                    if let low = value.valueLow, let high = value.valueHigh {
                        Text("Range: \(Int(low)) – \(Int(high))")
                    } else if let est = value.estimatedValue {
                        Text("Estimated: \(Int(est))")
                    }

                    // Confidence
                    if let c = value.confidenceScore {
                        Text(String(format: "Confidence: %.2f", c))
                    }

                    // Provider + timestamp
                    if let provider = value.aiProvider, !provider.isEmpty {
                        Text("Provider: \(provider)")
                    }
                    if let updated = value.valuationDate, !updated.isEmpty {
                        Text("Valuation Date: \(updated)")
                    }

                    // AI notes
                    if let notes = value.aiNotes,
                       !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("AI Notes:")
                            .font(Theme.secondaryFont.weight(.semibold))
                        Text(notes)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    // Missing details
                    if let missing = value.missingDetails, !missing.isEmpty {
                        Text("Missing Details (for better accuracy):")
                            .font(Theme.secondaryFont.weight(.semibold))
                        ForEach(missing, id: \.self) { detail in
                            Text("• \(detail)")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.text)
            }

            // Brand / model / details
            VStack(alignment: .leading, spacing: Theme.spacing.small) {
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

            // Extracted text
            if let text = result.extractedText,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Extracted Text")
                        .font(Theme.bodyFont.weight(.semibold))
                    Text(text)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .ltcCardBackground()
        .padding(.top, Theme.spacing.large)
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

    // MARK: - Logic

    private func loadPreviewImageIfNeeded() {
        guard let path = firstImagePath else { return }
        previewImage = MediaStorage.loadImage(from: path)
    }

    private func runAnalysis() async {
        guard let previewImage else {
            errorMessage = "No photo available for analysis."
            return
        }

        isAnalyzing = true
        errorMessage = nil
        analysisResult = nil

        let hints = ItemAIHints(
            userWrittenTitle: item.name.isEmpty ? nil : item.name,
            userWrittenDescription: item.itemDescription.isEmpty ? nil : item.itemDescription,
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
        valuation.missingDetails = hints.missingDetails ?? valuation.missingDetails

        // Preserve any existing userNotes; we never overwrite them from AI.
        // valuation.userNotes stays as-is.

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
        category: "Furniture",
        value: 100
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
