//
//  SetEditorSheet.swift
//  LegacyTreasureChest
//
//  Sets v1: Create / Edit sheet.
//

import SwiftUI
import SwiftData

struct SetEditorSheet: View {
    enum Mode {
        case create
        case edit(LTCItemSet)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let mode: Mode

    @State private var name: String = ""
    @State private var setType: SetType = .other
    @State private var sellPref: SellTogetherPreference = .togetherPreferred
    @State private var completeness: Completeness = .unknown
    @State private var story: String = ""
    @State private var notes: String = ""

    init(mode: Mode) {
        self.mode = mode
    }

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Set name", text: $name)

                Picker("Type", selection: $setType) {
                    ForEach(SetType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }

                Picker("Sell preference", selection: $sellPref) {
                    ForEach(SellTogetherPreference.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }

                Picker("Completeness", selection: $completeness) {
                    ForEach(Completeness.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
            }

            Section("Story (optional)") {
                TextEditor(text: $story)
                    .frame(minHeight: 80)
            }

            Section("Notes (optional)") {
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
            }
        }
        .navigationTitle(modeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { loadIfEditing() }
    }

    private var modeTitle: String {
        switch mode {
        case .create: return "New Set"
        case .edit: return "Edit Set"
        }
    }

    private func loadIfEditing() {
        guard case let .edit(itemSet) = mode else { return }
        name = itemSet.name
        setType = itemSet.setType
        sellPref = itemSet.sellTogetherPreference
        completeness = itemSet.completeness
        story = itemSet.story ?? ""
        notes = itemSet.notes ?? ""
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            let newSet = LTCItemSet(
                name: trimmedName,
                setType: setType,
                story: story.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                sellTogetherPreference: sellPref,
                completeness: completeness,
                estimatedSetPremium: nil,
                createdAt: .now,
                updatedAt: .now
            )
            modelContext.insert(newSet)

        case .edit(let itemSet):
            itemSet.name = trimmedName
            itemSet.setType = setType
            itemSet.sellTogetherPreference = sellPref
            itemSet.completeness = completeness
            itemSet.story = story.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            itemSet.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            itemSet.updatedAt = .now
        }
    }
}

// MARK: - Small helper

private extension String {
    var nilIfEmpty: String? {
        let t = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
