//
//  LotExecutionStateStore.swift
//  LegacyTreasureChest
//
//  Execution Mode v1: SwiftData helper for lot-centric checklist state.
//  - Lot state is owned by LiquidationBatch and keyed by lotNumber.
//  - Persists only checklist completion + optional timestamp + optional note.
//  - Progress/status/warnings are derived elsewhere (not persisted).
//
//  iOS 18+, Swift 6.
//

import Foundation
import SwiftData

@MainActor
final class LotExecutionStateStore {

    /// Returns the `LotExecutionState` for (batch, lotNumber), creating it (and its default checklist rows)
    /// if it does not exist.
    ///
    /// v1 rules:
    /// - checklist is standard and non-configurable
    /// - we only ever *add missing* checklist item rows (we do not delete unknown rows)
    func getOrCreateLotState(
        for batch: LiquidationBatch,
        lotNumber: String,
        modelContext: ModelContext
    ) -> LotExecutionState {
        let normalizedLotNumber = lotNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = findLotState(in: batch, lotNumber: normalizedLotNumber) {
            ensureChecklistRowsExist(for: existing, modelContext: modelContext)
            return existing
        }

        let state = LotExecutionState(
            lotNumber: normalizedLotNumber,
            createdAt: .now,
            updatedAt: .now
        )
        state.batch = batch

        // Persist + attach to batch relationship collection
        modelContext.insert(state)
        batch.lotExecutionStates.append(state)

        // Create default checklist rows (all v1 items)
        for def in ExecutionChecklistV1.allItems {
            let row = LotChecklistItemState(
                stepId: def.id,
                isComplete: false,
                completedAt: nil,
                note: nil,
                createdAt: .now,
                updatedAt: .now
            )
            row.lotState = state
            modelContext.insert(row)
            state.checklistItems.append(row)
        }

        return state
    }

    /// Toggle a checklist item and persist.
    /// This keeps the mutation logic in one place (boring, consistent).
    func setCompletion(
        lotState: LotExecutionState,
        stepId: String,
        isComplete: Bool,
        modelContext: ModelContext
    ) throws {
        let normalizedStepId = stepId.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure the row exists (should already, but defensive in v1)
        ensureChecklistRowsExist(for: lotState, modelContext: modelContext)

        guard let row = lotState.checklistItems.first(where: { $0.stepId == normalizedStepId }) else {
            return
        }

        // No-op if unchanged (avoid needless saves)
        if row.isComplete == isComplete { return }

        row.isComplete = isComplete
        row.completedAt = isComplete ? .now : nil
        row.updatedAt = .now

        lotState.updatedAt = .now
        try modelContext.save()
    }

    /// Update executor note and persist.
    func setNote(
        lotState: LotExecutionState,
        stepId: String,
        note: String?,
        modelContext: ModelContext
    ) throws {
        let normalizedStepId = stepId.trimmingCharacters(in: .whitespacesAndNewlines)

        ensureChecklistRowsExist(for: lotState, modelContext: modelContext)

        guard let row = lotState.checklistItems.first(where: { $0.stepId == normalizedStepId }) else {
            return
        }

        // No-op if unchanged
        if row.note == note { return }

        row.note = note
        row.updatedAt = .now

        lotState.updatedAt = .now
        try modelContext.save()
    }

    // MARK: - Private helpers

    private func findLotState(in batch: LiquidationBatch, lotNumber: String) -> LotExecutionState? {
        batch.lotExecutionStates.first(where: { $0.lotNumber == lotNumber })
    }

    /// Ensures the SwiftData rows exist for every canonical v1 checklist item.
    /// We only *add missing* rows. We do not delete extras (reversible + safe).
    private func ensureChecklistRowsExist(for lotState: LotExecutionState, modelContext: ModelContext) {
        var existingIds = Set(lotState.checklistItems.map { $0.stepId })

        for def in ExecutionChecklistV1.allItems {
            guard !existingIds.contains(def.id) else { continue }

            let row = LotChecklistItemState(
                stepId: def.id,
                isComplete: false,
                completedAt: nil,
                note: nil,
                createdAt: .now,
                updatedAt: .now
            )
            row.lotState = lotState
            modelContext.insert(row)
            lotState.checklistItems.append(row)

            existingIds.insert(def.id)
            lotState.updatedAt = .now
        }
    }
}

