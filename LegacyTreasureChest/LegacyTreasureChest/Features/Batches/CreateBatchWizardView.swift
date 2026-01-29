import SwiftUI
import SwiftData

struct CreateBatchWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Batch Name") {
                    TextField("e.g., Spring Estate Sale", text: $name)
                }

                Section {
                    Text("B1: This creates an empty batch only. We’ll add scope selection (items/sets) in a later step.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Batch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createBatch()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func createBatch() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let batch = LiquidationBatch(name: trimmed)
        modelContext.insert(batch)
    }
}

