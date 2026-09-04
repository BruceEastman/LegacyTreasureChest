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
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var drafts: [BatchItemDraft] = []
    @State private var isImporting: Bool = false
    @State private var globalErrorMessage: String?

    @StateObject private var consentGate = AIConsentGate()

    // Batch capacity preflight: blocks the whole batch, before AI analysis
    // begins, when the selection would exceed remaining free capacity.
    @State private var isShowingBatchCapacityLimit = false
    @State private var isShowingFullCatalogAccessPaywall = false
    @State private var isShowingEntitlementResolvingMessage = false
    @State private var remainingFreeCapacityForBatch = 0

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

                // Tip (kept lightweight to avoid clutter)
                Text("💡 Batch works best when the photo clearly shows what it is (brand/model/pattern). For valuable or ambiguous items (jewelry hallmarks, china patterns), add manually first.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.spacing.large)
                    .multilineTextAlignment(.center)

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
            .onChange(of: selectedPhotos) { _, newValue in
                guard !newValue.isEmpty else { return }
                attemptBatchLoad(for: newValue)
            }
            .aiConsentSheet(consentGate)
            .sheet(isPresented: $isShowingBatchCapacityLimit) {
                BatchCapacityLimitView(
                    requestedCount: selectedPhotos.count,
                    remainingFreeCapacity: remainingFreeCapacityForBatch,
                    onUnlock: {
                        isShowingBatchCapacityLimit = false
                        isShowingFullCatalogAccessPaywall = true
                    },
                    onReduceSelection: {
                        isShowingBatchCapacityLimit = false
                        selectedPhotos = []
                    }
                )
            }
            .sheet(isPresented: $isShowingFullCatalogAccessPaywall, onDismiss: {
                // The batch's selected photos are still in memory here.
                // If the purchase succeeded, it's safe to continue with
                // that same selection automatically. If not, the batch
                // stays blocked and the user can reduce their selection.
                if purchaseManager.hasFullCatalogAccess, !selectedPhotos.isEmpty {
                    attemptBatchLoad(for: selectedPhotos)
                }
            }) {
                FullCatalogAccessView()
            }
            .alert(
                "Still Checking",
                isPresented: $isShowingEntitlementResolvingMessage,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text("Still checking Full Catalog Access. Please try again in a moment.")
                }
            )
        }
    }

    // MARK: - Creation Gate

    /// All-or-none capacity preflight, run before AI analysis begins. If
    /// the full requested batch doesn't fit in remaining free capacity,
    /// nothing is analyzed or imported -- the user chooses to reduce their
    /// selection or unlock Full Catalog Access. Runs in a Task since the
    /// gate briefly waits for entitlement resolution if needed (see
    /// ItemCreationGate.evaluate).
    private func attemptBatchLoad(for photos: [PhotosPickerItem]) {
        Task {
            switch await ItemCreationGate.evaluate(
                requestedItemCount: photos.count,
                modelContext: modelContext,
                purchaseManager: purchaseManager
            ) {
            case .allowed:
                await consentGate.perform { await loadDrafts(from: photos) }
            case .requiresFullCatalogAccess(let remaining):
                remainingFreeCapacityForBatch = remaining
                isShowingBatchCapacityLimit = true
            case .entitlementResolving:
                isShowingEntitlementResolvingMessage = true
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
                                Text("Estimated: \(CurrencyFormat.dollarsRange(low: low, high: high))")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                            } else if let est = value.estimatedValue {
                                Text("Estimated: \(CurrencyFormat.dollars(est))")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        Text("Quantity: 1")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    } else if draft.isAnalyzing {
                        HStack(spacing: Theme.spacing.small) {
                            ProgressView()
                            Text("Analyzing…")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else if draft.errorMessage != nil {
                        VStack(alignment: .leading, spacing: Theme.spacing.small) {
                            Text("AI analysis didn’t succeed. Nothing was saved.")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.destructive)

                            Button(action: {
                                Task {
                                    await analyzeDraft(at: index)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Try Again")
                                }
                                .font(Theme.secondaryFont)
                            }
                        }
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
            // Keep full detail for debugging, but show a user-friendly message in the UI.
            print("Batch analyzeItemPhoto failed:", error)
            drafts[index].errorMessage = "AI analysis didn’t succeed this time. Nothing was saved. Tap Try Again."
        }

        drafts[index].isAnalyzing = false
    }
    
    // MARK: - Import

    private func importSelectedDrafts() async {
        let includedCount = drafts.filter { $0.isIncluded && $0.analysis != nil }.count
        guard includedCount > 0 else { return }

        // Defensive re-check immediately before persistence: guards against
        // a stale preflight (count changed since analysis started, e.g. a
        // concurrent Manual Add) rather than trusting the earlier gate
        // result indefinitely. Reuses the same centralized gate -- no
        // capacity arithmetic is duplicated here.
        switch await ItemCreationGate.evaluate(
            requestedItemCount: includedCount,
            modelContext: modelContext,
            purchaseManager: purchaseManager
        ) {
        case .allowed:
            break
        case .requiresFullCatalogAccess:
            await MainActor.run {
                globalErrorMessage = "Your free catalog allowance has been reached. Unlock Full Catalog Access to import these items."
            }
            return
        case .entitlementResolving:
            await MainActor.run {
                globalErrorMessage = "Still checking Full Catalog Access. Please try again in a moment."
            }
            return
        }

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
            category: LTCItem.normalizeCategory(analysis.category),
            value: 0,
            quantity: 1
        )

        // Value handling + create ItemValuation if available (unit valuation).
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

// MARK: - Batch Capacity Limit (local)

/// Shown when the selected batch would exceed remaining free capacity,
/// before any AI analysis has run. Blocks the whole batch -- there is no
/// partial-analyze/partial-import path here.
private struct BatchCapacityLimitView: View {
    let requestedCount: Int
    let remainingFreeCapacity: Int
    let onUnlock: () -> Void
    let onReduceSelection: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {
                Text(capacityHeadline)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(explanation)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onUnlock()
                } label: {
                    Text("Unlock Full Catalog Access")
                        .font(Theme.bodyFont.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing.medium)
                        .background(Theme.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    onReduceSelection()
                } label: {
                    Text("Reduce Selection")
                        .font(Theme.bodyFont.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing.medium)
                        .background(Color(.systemGray6))
                        .foregroundStyle(Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Spacer()
            }
            .padding(Theme.spacing.xl)
            .navigationTitle("Free Catalog Limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var capacityHeadline: String {
        if remainingFreeCapacity == 1 {
            return "You can add 1 more item with the free catalog."
        }
        return "You can add \(remainingFreeCapacity) more items with the free catalog."
    }

    private var explanation: String {
        "You selected \(requestedCount) photos. Reduce your selection to \(remainingFreeCapacity), or unlock Full Catalog Access to add all \(requestedCount)."
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
            .environment(PurchaseManager())
    }
}
#endif
