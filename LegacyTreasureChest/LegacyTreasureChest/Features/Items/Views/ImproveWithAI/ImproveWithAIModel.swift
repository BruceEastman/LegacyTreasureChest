//
//  ImproveWithAIModel.swift
//  LegacyTreasureChest
//
//  State for the two-step Improve with AI sheet (LTC 1.3):
//  1. Compose: owner notes, explicitly selected evidence, and a summary of
//     what will be sent (from AIEvidencePreparer.plan, which owns the limits).
//  2. Review: what the AI proposes versus the item, with per-field choices.
//  Nothing is written to the item until apply(). New attachments added while
//  composing are normal item attachments and stay attached either way.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ImproveWithAIModel {

    enum Phase {
        case compose
        case analyzing
        case review(ItemAnalysis, ItemAnalysisReview)
    }

    typealias Analyzer = @MainActor (ItemAnalysisRequest) async throws -> ItemAnalysis

    let item: LTCItem
    private let preparer: AIEvidencePreparer
    private let analyzer: Analyzer

    private(set) var selection = AIEvidenceSelection()
    private(set) var plan: AIEvidencePlan?
    private(set) var planError: AIEvidenceError?

    /// Required before analysis when a selected PDF has more than 10 pages.
    var acknowledgedTruncation = false

    private(set) var phase: Phase = .compose
    private(set) var errorMessage: String?
    /// The review choices (starts from the review's conservative defaults).
    var choices = ItemAnalysisApplier.Choices()

    /// The document was part of the analysis being reviewed.
    private(set) var analyzedWithDocument = false

    private var analysisTask: Task<Void, Never>?

    init(item: LTCItem,
         preparer: AIEvidencePreparer? = nil,
         analyzer: Analyzer? = nil) {
        self.item = item
        self.preparer = preparer ?? AIEvidencePreparer()
        self.analyzer = analyzer ?? { request in try await AIService.shared.analyzeItem(request) }
        refreshPlan()
    }

    var limits: AIEvidenceLimits { preparer.limits }

    // MARK: - Selection

    var selectedPhotoIDs: [UUID] { selection.supplementaryImageIDs }
    var selectedDocumentID: UUID? { selection.documentIDs.first }

    var canSelectMorePhotos: Bool { selection.supplementaryImageIDs.count < limits.maxSupplementaryPhotos }

    func isPhotoSelected(_ id: UUID) -> Bool { selection.supplementaryImageIDs.contains(id) }

    /// Selects or deselects an additional photo. Returns false (and changes
    /// nothing) when selecting would exceed the limit.
    @discardableResult
    func togglePhoto(_ id: UUID) -> Bool {
        if let index = selection.supplementaryImageIDs.firstIndex(of: id) {
            selection.supplementaryImageIDs.remove(at: index)
        } else {
            guard canSelectMorePhotos else { return false }
            selection.supplementaryImageIDs.append(id)
        }
        refreshPlan()
        return true
    }

    /// One document at a time; selecting another replaces it. Nil deselects.
    func selectDocument(_ id: UUID?) {
        selection.documentIDs = id.map { [$0] } ?? []
        acknowledgedTruncation = false
        refreshPlan()
    }

    func toggleDocument(_ id: UUID) {
        selectDocument(selection.documentIDs.first == id ? nil : id)
    }

    /// Photos the owner just added: they become attachments (already done by
    /// the importer) and are selected for this analysis while slots remain.
    func didImportPhotos(_ images: [ItemImage]) {
        for image in images where canSelectMorePhotos && image.imageId != item.primaryImage?.imageId {
            if !selection.supplementaryImageIDs.contains(image.imageId) {
                selection.supplementaryImageIDs.append(image.imageId)
            }
        }
        refreshPlan()
    }

    func didImportDocument(_ document: Document) {
        selectDocument(document.documentId)
    }

    /// Re-validates the selection (counts, limits, PDF page counts, locked or
    /// unreadable files) through the preparer.
    func refreshPlan() {
        // Drop selections whose attachments were deleted elsewhere.
        let liveImages = Set(item.images.filter { !$0.isDeleted }.map(\.imageId))
        let liveDocs = Set(item.documents.filter { !$0.isDeleted }.map(\.documentId))
        selection.supplementaryImageIDs.removeAll { !liveImages.contains($0) || $0 == item.primaryImage?.imageId }
        selection.documentIDs.removeAll { !liveDocs.contains($0) }

        do {
            plan = try preparer.plan(for: item, selection: selection)
            planError = nil
        } catch let error as AIEvidenceError {
            plan = nil
            planError = error
        } catch {
            plan = nil
            planError = .documentUnreadable
        }
    }

    // MARK: - Analyze

    var needsTruncationAcknowledgement: Bool {
        !(plan?.truncatedDocuments.isEmpty ?? true)
    }

    /// Supplementary evidence needs the expanded (version 2) disclosure.
    var requiresEvidenceDisclosure: Bool { !selection.isEmpty }

    var hasTextToAnalyze: Bool {
        !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(item.valuation?.userNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isAnalyzing: Bool {
        if case .analyzing = phase { return true }
        return false
    }

    var canAnalyze: Bool {
        guard case .compose = phase, let plan, planError == nil else { return false }
        if needsTruncationAcknowledgement && !acknowledgedTruncation { return false }
        return !plan.isTextOnly || hasTextToAnalyze
    }

    /// Starts one analysis. Ignored while one is running (no duplicate
    /// submissions). On failure or cancellation the item is unchanged.
    func startAnalysis() {
        guard canAnalyze, analysisTask == nil else { return }
        errorMessage = nil
        phase = .analyzing
        let selection = self.selection
        analysisTask = Task { [weak self] in
            await self?.runAnalysis(selection: selection)
        }
    }

    private func runAnalysis(selection: AIEvidenceSelection) async {
        defer { analysisTask = nil }
        do {
            let prepared = try await preparer.prepare(for: item, selection: selection)
            try Task.checkCancellation()
            let request = ItemAnalysisRequestBuilder.build(for: item, prepared: prepared)
            let analysis = try await analyzer(request)
            try Task.checkCancellation()
            let includedDocument = !selection.documentIDs.isEmpty
            let review = ItemAnalysisReview(item: item, analysis: analysis, includedDocument: includedDocument)
            analyzedWithDocument = includedDocument
            choices = review.defaults
            phase = .review(analysis, review)
        } catch {
            phase = .compose
            if Task.isCancelled || error is CancellationError || (error as? AIError).map(Self.isCancellation) == true {
                errorMessage = AIError.cancelled.localizedDescription
            } else {
                errorMessage = ItemAIAnalysisSheet.userMessage(for: error)
            }
        }
    }

    private static func isCancellation(_ error: AIError) -> Bool {
        if case .cancelled = error { return true }
        return false
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
    }

    // MARK: - Review

    /// Leaves the review without applying anything (selections are kept).
    func discardReview() {
        guard case .review = phase else { return }
        phase = .compose
        choices = ItemAnalysisApplier.Choices()
    }

    /// Applies only the chosen fields. Returns false when not in review.
    @discardableResult
    func apply() -> Bool {
        guard case .review(let analysis, let review) = phase else { return false }
        // The valuation is stored per unit: as returned for a per-unit
        // estimate, or equally allocated for a group estimate. An ambiguous
        // valuation is never applied.
        var perUnit = analysis
        perUnit.valueHints = review.valueHintsToApply
        var chosen = choices
        chosen.valuation = choices.valuation && review.valuation.canApply
        ItemAnalysisApplier.apply(perUnit, to: item, choices: chosen)
        return true
    }

    func previewDescription() -> String? {
        guard case .review(let analysis, let review) = phase else { return nil }
        return review.previewDescription(analysis: analysis,
                                         llmGeneratedDescription: item.llmGeneratedDescription,
                                         choices: choices)
    }

    func clearError() { errorMessage = nil }
}
