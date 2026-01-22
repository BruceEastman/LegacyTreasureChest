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

    enum ClosetConditionBand: String, CaseIterable, Identifiable {
        case likeNew = "LikeNew"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"

        var id: String { rawValue }

        var displayLabel: String {
            switch self {
            case .likeNew: return "Like New"
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Poor"
            }
        }
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

    // Closet lot metadata (v1 minimal capture)
    @State private var approxItemCount: String = ""
    @State private var sizeBand: String = ""
    @State private var conditionBand: ClosetConditionBand = .good
    @State private var brandList: String = ""

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

            if setType == .closetLot {
                Section("Closet Lot Details (recommended)") {
                    TextField("Approx item count (e.g., 20–40)", text: $approxItemCount)
                        .textInputAutocapitalization(.never)

                    TextField("Size band (e.g., Men’s 42R / L, Women’s M, Mixed)", text: $sizeBand)

                    Picker("Condition", selection: $conditionBand) {
                        ForEach(ClosetConditionBand.allCases) { b in
                            Text(b.displayLabel).tag(b)
                        }
                    }

                    TextField("Brands (comma-separated, up to ~12)", text: $brandList)
                }

                Section("Closet Lot Guidance") {
                    Text("Photos to capture:")
                    Text("• Rail / pile overview")
                    Text("• Label collage (5–12 labels)")
                    Text("• 1–3 hero examples")
                        .foregroundStyle(.secondary)
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

        // Closet lot fields (safe defaults)
        approxItemCount = itemSet.closetApproxItemCount ?? ""
        sizeBand = itemSet.closetSizeBand ?? ""
        brandList = itemSet.closetBrandList ?? ""

        if let raw = itemSet.closetConditionBandRaw,
           let parsed = ClosetConditionBand(rawValue: raw) {
            conditionBand = parsed
        } else {
            conditionBand = .good
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Normalize closet fields (store only when closetLot; otherwise clear)
        let savedApproxCount = setType == .closetLot ? approxItemCount.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil
        let savedSizeBand = setType == .closetLot ? sizeBand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil
        let savedBrandList = setType == .closetLot ? brandList.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil
        let savedConditionRaw = setType == .closetLot ? conditionBand.rawValue : nil

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

            // Closet lot fields
            newSet.closetApproxItemCount = savedApproxCount
            newSet.closetSizeBand = savedSizeBand
            newSet.closetConditionBandRaw = savedConditionRaw
            newSet.closetBrandList = savedBrandList

            modelContext.insert(newSet)

        case .edit(let itemSet):
            itemSet.name = trimmedName
            itemSet.setType = setType
            itemSet.sellTogetherPreference = sellPref
            itemSet.completeness = completeness
            itemSet.story = story.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            itemSet.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

            // Closet lot fields
            itemSet.closetApproxItemCount = savedApproxCount
            itemSet.closetSizeBand = savedSizeBand
            itemSet.closetConditionBandRaw = savedConditionRaw
            itemSet.closetBrandList = savedBrandList

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
