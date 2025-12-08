//
//  BatchAddItemsFromPhotosView.swift
//  LegacyTreasureChest
//
//  Select multiple photos, analyze each with AI, and import
//  them as LTCItem records with attached ItemImage entries.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// In-memory draft representing one potential item created from a photo.
private struct BatchItemDraft: Identifiable {
    let id = UUID()
    let image: UIImage
    var analysis: ItemAnalysis?
    var isIncluded: Bool = true
    var isAnalyzing: Bool = false
    var errorMessage: String?
}

struct BatchAddItemsFromPhotosView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var drafts: [BatchItemDraft] = []
    @State private var isImporting: Bool = false
    @State private var globalErrorMessage: String?

    private var canImport: Bool {
        !isImporting &&
        drafts.contains(where: { $0.isIncluded && $0.analysis != nil })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacing.medium) {

                // Photo picker
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 20,
                    matching: .images
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Select Photos")
                            .font(Theme.bodyFont.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, Theme.spacing.large)
                .padding(.top, Theme.spacing.medium)

                // Draft list
                if drafts.isEmpty {
                    Text("Select photos to generate draft items using AI.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.spacing.large)
                        .multilineTextAlignment(.center)
                } else {
                    List {
                        ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                            draftRow(for: draft, index: index)
                        }
                    }
                    .listStyle(.plain)
                }

                if let globalErrorMessage {
                    Text(globalErrorMessage)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.destructive)
                        .padding(.horizontal, Theme.spacing.large)
                }

                // Import button
                if !drafts.isEmpty {
                    Button {
                        Task { await importSelectedDrafts() }
                    } label: {
                        HStack {
                            if isImporting {
                                ProgressView()
                            }
                            Image(systemName: "square.and.arrow.down")
                            Text("Import Selected Items")
                                .font(Theme.bodyFont.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canImport ? Theme.primary : Theme.primary.opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, Theme.spacing.large)
                    .padding(.bottom, Theme.spacing.large)
                    .disabled(!canImport)
                }
            }
            .navigationTitle("Add from Photos")
            .navigationBarTitleDisplayMode(.inline)
            .background(Theme.background.ignoresSafeArea())
            .onChange(of: selectedPhotos) { newValue in
                Task { await loadDrafts(from: newValue) }
            }
        }
    }

    // MARK: - Draft Row

    @ViewBuilder
    private func draftRow(for draft: BatchItemDraft, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            HStack(alignment: .top, spacing: Theme.spacing.medium) {
                Image(uiImage: draft.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    if let analysis = draft.analysis {
                        Text(analysis.title)
                            .font(Theme.bodyFont.weight(.semibold))
                            .foregroundStyle(Theme.text)

                        Text(analysis.summary)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(3)

                        Text("Category: \(analysis.category)")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)

                        if let value = analysis.valueHints {
                            // Show either range or single estimate.
                            if let low = value.valueLow, let high = value.valueHigh {
                                Text("Estimated: \(Int(low))–\(Int(high)) \(value.currencyCode)")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                            } else if let est = value.estimatedValue {
                                Text("Estimated: \(Int(est)) \(value.currencyCode)")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    } else if draft.isAnalyzing {
                        HStack(spacing: Theme.spacing.small) {
                            ProgressView()
                            Text("Analyzing…")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else if let error = draft.errorMessage {
                        Text("Analysis failed: \(error)")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.destructive)
                    } else {
                        Text("Waiting for analysis…")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Toggle(isOn: bindingForIncluded(at: index)) {
                Text("Include this item")
                    .font(Theme.secondaryFont)
            }
            .tint(Theme.accent)
        }
        .padding(.vertical, Theme.spacing.small)
    }

    private func bindingForIncluded(at index: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard drafts.indices.contains(index) else { return false }
                return drafts[index].isIncluded
            },
            set: { newValue in
                guard drafts.indices.contains(index) else { return }
                drafts[index].isIncluded = newValue
            }
        )
    }

    // MARK: - Load Drafts & Analyze

    private func loadDrafts(from items: [PhotosPickerItem]) async {
        await MainActor.run {
            drafts.removeAll()
            globalErrorMessage = nil
        }

        var newDrafts: [BatchItemDraft] = []

        for pickerItem in items {
            do {
                guard let data = try await pickerItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    continue
                }
                let draft = BatchItemDraft(image: image)
                newDrafts.append(draft)
            } catch {
                // Ignore individual load failures; user can re-pick if needed.
                print("❌ Failed to load photo: \(error)")
            }
        }

        await MainActor.run {
            drafts = newDrafts
        }

        // Run AI analysis sequentially to avoid hammering the API.
        for index in drafts.indices {
            await analyzeDraft(at: index)
        }
    }

    @MainActor
    private func analyzeDraft(at index: Int) async {
        guard drafts.indices.contains(index) else { return }

        drafts[index].isAnalyzing = true
        drafts[index].errorMessage = nil

        let image = drafts[index].image
        let hints = ItemAIHints(
            userWrittenTitle: nil,
            userWrittenDescription: nil,
            knownCategory: nil
        )

        do {
            let result = try await AIService.shared.analyzeItemPhoto(image, hints: hints)
            drafts[index].analysis = result
        } catch {
            drafts[index].errorMessage = error.localizedDescription
        }

        drafts[index].isAnalyzing = false
    }

    // MARK: - Import

    private func importSelectedDrafts() async {
        await MainActor.run {
            isImporting = true
            globalErrorMessage = nil
        }

        defer {
            Task { @MainActor in
                isImporting = false
            }
        }

        for draft in drafts {
            guard draft.isIncluded, let analysis = draft.analysis else { continue }

            do {
                try await createItem(from: draft, analysis: analysis)
            } catch {
                await MainActor.run {
                    globalErrorMessage = "Failed to import one or more items: \(error.localizedDescription)"
                }
            }
        }

        // After importing, dismiss back to the list.
        await MainActor.run {
            dismiss()
        }
    }

    @MainActor
    private func createItem(from draft: BatchItemDraft, analysis: ItemAnalysis) async throws {
        // Save the image to disk and create an ItemImage.
        let relativePath = try MediaStorage.saveImage(draft.image)
        let imageRecord = ItemImage(filePath: relativePath)

        // Build description similar to the AI analysis sheet.
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
            descriptionLines.append("")
            descriptionLines.append(detailsLine)
        }

        let fullDescription = descriptionLines.joined(separator: "\n")

        let item = LTCItem(
            name: analysis.title,
            itemDescription: fullDescription,
            category: analysis.category,
            value: 0
        )

        // Value handling + create ItemValuation if available.
        if let hints = analysis.valueHints {
            let mid: Double? = {
                if let est = hints.estimatedValue {
                    return est
                }
                if let low = hints.valueLow, let high = hints.valueHigh {
                    return (low + high) / 2.0
                }
                if let low = hints.valueLow {
                    return low
                }
                if let high = hints.valueHigh {
                    return high
                }
                return nil
            }()

            if let mid, mid > 0 {
                item.value = mid
            }

            if let high = hints.valueHigh {
                item.suggestedPriceNew = high
            } else if let est = hints.estimatedValue {
                item.suggestedPriceNew = est
            }

            if let low = hints.valueLow {
                item.suggestedPriceUsed = low
            } else if let est = hints.estimatedValue {
                item.suggestedPriceUsed = est
            }

            // Persist a valuation record.
            let valuation = ItemValuation(
                valueLow: hints.valueLow,
                estimatedValue: hints.estimatedValue,
                valueHigh: hints.valueHigh,
                currencyCode: hints.currencyCode,
                confidenceScore: hints.confidenceScore,
                valuationDate: hints.valuationDate.flatMap(parseISO8601Date),
                aiProvider: hints.aiProvider,
                aiNotes: hints.aiNotes,
                missingDetails: hints.missingDetails ?? [],
                userNotes: nil
            )
            item.valuation = valuation
        }

        item.llmGeneratedTitle = analysis.title
        item.llmGeneratedDescription = analysis.summary

        // Attach image
        item.images.append(imageRecord)

        modelContext.insert(item)
    }

    /// Parse ISO 8601 timestamps like "2025-12-08T21:57:15.698594Z".
    private func parseISO8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }
}

// MARK: - Preview

#if DEBUG
private let batchAddPreviewContainer: ModelContainer = {
    let container = try! ModelContainer(
        for: LTCItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return container
}()

#Preview {
    NavigationStack {
        BatchAddItemsFromPhotosView()
            .modelContainer(batchAddPreviewContainer)
    }
}
#endif
