//
//  LotExecutionView.swift
//  LegacyTreasureChest
//
//  Execution Mode v1: Lot-centric checklist UI.
//  - Uses the standard checklist (ExecutionChecklistV1)
//  - Persists only: completion Bool, optional timestamp, optional executor note
//  - Derives progress locally (no persisted batch-level state)
//
//  iOS 18+, Swift 6.
//

import SwiftUI
import SwiftData

struct LotExecutionView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var batch: LiquidationBatch
    let lotNumber: String

    @State private var lotState: LotExecutionState?
    @State private var errorMessage: String?

    // Note editor
    @State private var isNoteEditorPresented: Bool = false
    @State private var editingStepId: String?
    @State private var noteDraft: String = ""

    private let store = LotExecutionStateStore()

    var body: some View {
        Form {
            Section {
                headerCard()
            }

            if let lotState {
                checklistSections(for: lotState)
            } else {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading lot checklist…")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Lot \(lotNumberDisplay)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadLotStateIfNeeded()
        }
        .sheet(isPresented: $isNoteEditorPresented) {
            NoteEditorSheet(
                stepTitle: stepTitle(for: editingStepId),
                note: $noteDraft,
                onCancel: { isNoteEditorPresented = false },
                onSave: { saveNoteDraft() }
            )
        }
    }

    // MARK: - Header / Progress

    @ViewBuilder
    private func headerCard() -> some View {
        let total = ExecutionChecklistV1.allItems.count
        let completed = completedCount(for: lotState)
        let pct = total > 0 ? Double(completed) / Double(total) : 0

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Progress")
                    .font(.headline)
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: pct)

            Text("\(completed) of \(total) complete")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func completedCount(for lotState: LotExecutionState?) -> Int {
        guard let lotState else { return 0 }
        let ids = Set(ExecutionChecklistV1.allItems.map { $0.id })
        return lotState.checklistItems.filter { ids.contains($0.stepId) && $0.isComplete }.count
    }

    // MARK: - Checklist Rendering

    @ViewBuilder
    private func checklistSections(for lotState: LotExecutionState) -> some View {
        ForEach(ExecutionChecklistV1.sections) { sectionDef in
            Section(header: Text(sectionDef.title)) {
                ForEach(sectionDef.items) { itemDef in
                    checklistRow(lotState: lotState, itemDef: itemDef)
                }
            }
        }
    }

    @ViewBuilder
    private func checklistRow(lotState: LotExecutionState, itemDef: ExecutionChecklistV1.ItemDefinition) -> some View {
        let row = rowState(in: lotState, stepId: itemDef.id)

        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { row?.isComplete ?? false },
                set: { newValue in
                    setCompletion(stepId: itemDef.id, isComplete: newValue)
                }
            )) {
                Text(itemDef.title)
                    .font(.body)
            }

            HStack(spacing: 10) {
                if let completedAt = row?.completedAt {
                    Text("Completed \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not completed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    beginEditingNote(stepId: itemDef.id)
                } label: {
                    Label(noteButtonTitle(for: row?.note), systemImage: "square.and.pencil")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func noteButtonTitle(for note: String?) -> String {
        let trimmed = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Add Note" : "Edit Note"
    }

    // MARK: - Data Access

    private func loadLotStateIfNeeded() {
        if lotState != nil { return }

        errorMessage = nil
        let normalized = lotNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            errorMessage = "Missing lot number."
            return
        }

        let state = store.getOrCreateLotState(for: batch, lotNumber: normalized, modelContext: modelContext)
        lotState = state

        // Persist new records if created
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Could not save lot state: \(error.localizedDescription)"
        }
    }

    private func rowState(in lotState: LotExecutionState, stepId: String) -> LotChecklistItemState? {
        lotState.checklistItems.first(where: { $0.stepId == stepId })
    }

    private func setCompletion(stepId: String, isComplete: Bool) {
        guard let lotState else { return }
        errorMessage = nil
        do {
            try store.setCompletion(lotState: lotState, stepId: stepId, isComplete: isComplete, modelContext: modelContext)
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: - Notes

    private func beginEditingNote(stepId: String) {
        guard let lotState else { return }
        errorMessage = nil

        editingStepId = stepId
        let existing = rowState(in: lotState, stepId: stepId)?.note ?? ""
        noteDraft = existing
        isNoteEditorPresented = true
    }

    private func saveNoteDraft() {
        guard let lotState, let stepId = editingStepId else {
            isNoteEditorPresented = false
            return
        }

        errorMessage = nil

        // Store nil instead of empty string (cleaner persistence)
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteToSave: String? = trimmed.isEmpty ? nil : trimmed

        do {
            try store.setNote(lotState: lotState, stepId: stepId, note: noteToSave, modelContext: modelContext)
            isNoteEditorPresented = false
        } catch {
            errorMessage = "Could not save note: \(error.localizedDescription)"
        }
    }

    private func stepTitle(for stepId: String?) -> String {
        guard let stepId else { return "Note" }
        return ExecutionChecklistV1.allItems.first(where: { $0.id == stepId })?.title ?? "Note"
    }

    // MARK: - Display helpers

    private var lotNumberDisplay: String {
        let trimmed = lotNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }
}

// MARK: - Note Editor Sheet

private struct NoteEditorSheet: View {
    let stepTitle: String
    @Binding var note: String

    let onCancel: () -> Void
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(stepTitle)) {
                    TextEditor(text: $note)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle("Executor Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

