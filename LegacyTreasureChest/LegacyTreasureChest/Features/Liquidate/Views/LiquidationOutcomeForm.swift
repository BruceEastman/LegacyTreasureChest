//
//  LiquidationOutcomeForm.swift
//  LegacyTreasureChest
//
//  Record or edit what actually happened with a Plan. Local only: nothing is
//  sent to the backend, and no item value, beneficiary, or classification is
//  changed. Cancel leaves the Plan exactly as it was.
//

import SwiftUI

struct LiquidationOutcomeForm: View {
    let planTitle: String
    let existing: LiquidationPlanOutcomeDTO?
    let currencyCode: String
    /// The business chosen for the Plan, offered (never filled in automatically).
    var suggestedCounterparty: String? = nil
    let onSave: (LiquidationPlanOutcomeDTO) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var result: LiquidationOutcomeResult?
    @State private var amount: Double?
    @State private var counterparty: String = ""
    @State private var date: Date = .now
    @State private var notes: String = ""

    init(
        planTitle: String,
        existing: LiquidationPlanOutcomeDTO?,
        currencyCode: String,
        suggestedCounterparty: String? = nil,
        onSave: @escaping (LiquidationPlanOutcomeDTO) -> Void
    ) {
        self.planTitle = planTitle
        self.existing = existing
        self.currencyCode = currencyCode
        self.suggestedCounterparty = suggestedCounterparty
        self.onSave = onSave
        _result = State(initialValue: existing?.result)
        _amount = State(initialValue: existing?.amountReceived)
        _counterparty = State(initialValue: existing?.counterparty ?? "")
        _date = State(initialValue: existing?.date ?? .now)
        _notes = State(initialValue: existing?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Result", selection: $result) {
                        ForEach(LiquidationOutcomeResult.allCases, id: \.self) { option in
                            Text(option.displayName).tag(Optional(option))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("What happened?")
                } footer: {
                    if let result {
                        Text(Self.statusExplanation(result))
                    }
                }

                if let result {
                    if result.recordsAmount {
                        Section {
                            TextField(
                                "Amount received",
                                value: $amount,
                                format: .currency(code: currencyCode).precision(.fractionLength(0)),
                                prompt: Text("Optional")
                            )
                            .keyboardType(.numberPad)
                        } header: {
                            Text(result == .consigned ? "Amount received so far" : "Amount received")
                        } footer: {
                            Text("Enter what you actually received, after any fees. Brief estimates are not used.")
                        }
                    }

                    if let label = result.counterpartyLabel {
                        Section(label) {
                            TextField("Business or person (optional)", text: $counterparty)
                                .textInputAutocapitalization(.words)
                            if let suggestion = Self.counterpartySuggestion(suggestedCounterparty, current: counterparty) {
                                Button("Use \(suggestion)") { counterparty = suggestion }
                                    .font(.footnote)
                            }
                        }
                    }

                    Section {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }

                    Section("Notes") {
                        TextField("Optional", text: $notes, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Record the Outcome" : "Edit Outcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let result else { return }
                        onSave(LiquidationPlanOutcomeDTO.fromForm(
                            result: result,
                            amount: amount,
                            currencyCode: currencyCode,
                            counterparty: counterparty,
                            date: date,
                            notes: notes,
                            previous: existing
                        ))
                        dismiss()
                    }
                    .disabled(result == nil)
                }
            }
        }
    }

    /// Offered only while the field is empty, so typed text is never replaced.
    static func counterpartySuggestion(_ suggestion: String?, current: String) -> String? {
        guard current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let s = suggestion?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    static func statusExplanation(_ result: LiquidationOutcomeResult) -> String {
        switch result.planStatus {
        case .completed: return "This finishes the Plan."
        case .inProgress: return "The Plan stays in progress until the sale or payout is complete."
        case .onHold: return "The Plan is put on hold. You can change the outcome or the approach later."
        case .notStarted: return ""
        }
    }
}
