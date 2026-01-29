import SwiftUI
import SwiftData

struct BatchListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LiquidationBatch.createdAt, order: .reverse) private var batches: [LiquidationBatch]

    @State private var showingCreateSheet = false

    var body: some View {
        List {
            if batches.isEmpty {
                ContentUnavailableView(
                    "No Batches Yet",
                    systemImage: "shippingbox",
                    description: Text("Create a batch to begin grouping items and sets for an estate sale.")
                )
            } else {
                ForEach(batches) { batch in
                    NavigationLink {
                        BatchDetailView(batch: batch)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(batch.name)
                                .font(.headline)

                            HStack(spacing: 12) {
                                Text(batch.statusRaw.capitalized)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text(batch.saleTypeRaw.capitalized)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if let target = batch.targetDate {
                                Text(target, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteBatches)
            }
        }
        .navigationTitle("Batches")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Label("Create Batch", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateBatchWizardView()
        }
    }

    private func deleteBatches(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(batches[index])
        }
        // SwiftData saves automatically in most setups; no explicit save required
    }
}

private struct BatchDetailView: View {
    @Bindable var batch: LiquidationBatch

    @State private var hasTargetDate: Bool = false
    @State private var draftTargetDate: Date = .now

    @State private var showingAddItemsSheet = false
    @State private var showingAddSetsSheet = false

    var body: some View {
        Form {
            Section("Batch") {
                TextField("Name", text: $batch.name)
                    .onChange(of: batch.name) { _, _ in touchUpdatedAt() }

                // We intentionally edit the raw fields to avoid guessing enum cases.
                TextField("Status (raw)", text: $batch.statusRaw)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: batch.statusRaw) { _, _ in touchUpdatedAt() }

                TextField("Sale Type (raw)", text: $batch.saleTypeRaw)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: batch.saleTypeRaw) { _, _ in touchUpdatedAt() }

                Toggle("Target Date", isOn: $hasTargetDate)
                    .onChange(of: hasTargetDate) { _, newValue in
                        if newValue {
                            if batch.targetDate == nil {
                                batch.targetDate = draftTargetDate
                            }
                        } else {
                            batch.targetDate = nil
                        }
                        touchUpdatedAt()
                    }

                if hasTargetDate {
                    DatePicker(
                        "Date",
                        selection: Binding<Date>(
                            get: { batch.targetDate ?? draftTargetDate },
                            set: { newDate in
                                batch.targetDate = newDate
                                draftTargetDate = newDate
                                touchUpdatedAt()
                            }
                        ),
                        displayedComponents: [.date]
                    )
                }

                TextField(
                    "Venue (raw)",
                    text: Binding(
                        get: { batch.venueRaw ?? "" },
                        set: { newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            batch.venueRaw = trimmed.isEmpty ? nil : trimmed
                            touchUpdatedAt()
                        }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                TextField(
                    "Provider",
                    text: Binding(
                        get: { batch.provider ?? "" },
                        set: { newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            batch.provider = trimmed.isEmpty ? nil : trimmed
                            touchUpdatedAt()
                        }
                    )
                )
                .autocorrectionDisabled()

                LabeledContent("Created") {
                    Text(batch.createdAt, style: .date)
                }

                LabeledContent("Updated") {
                    Text(batch.updatedAt, style: .date)
                }

                Text("Note: Status, Sale Type, and Venue are edited as raw values for now. We’ll convert these to pickers once we wire in the exact enum case list safely.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Contents") {
                LabeledContent("Items", value: "\(batch.items.count)")
                LabeledContent("Sets", value: "\(batch.sets.count)")
            }

            Section("Items in Batch") {
                Button {
                    showingAddItemsSheet = true
                } label: {
                    Label("Add Items…", systemImage: "plus")
                }

                if batch.items.isEmpty {
                    Text("No items yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(batch.items) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.item?.name ?? "Unnamed Item")
                                .font(.body)

                            Text(entry.dispositionRaw.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Sets in Batch") {
                Button {
                    showingAddSetsSheet = true
                } label: {
                    Label("Add Sets…", systemImage: "plus")
                }

                if batch.sets.isEmpty {
                    Text("No sets yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(batch.sets) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.itemSet?.name ?? "Unnamed Set")
                                .font(.body)

                            Text(entry.dispositionRaw.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Scope Builder") {
                Text("Coming next: choose which items and sets belong in this batch, then generate lot numbers and handling notes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(batch.name.isEmpty ? "Batch" : batch.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasTargetDate = (batch.targetDate != nil)
            if let t = batch.targetDate {
                draftTargetDate = t
            }
        }
        .sheet(isPresented: $showingAddItemsSheet) {
            AddItemsStubSheet(batchName: batch.name)
        }
        .sheet(isPresented: $showingAddSetsSheet) {
            AddSetsStubSheet(batchName: batch.name)
        }
    }

    private func touchUpdatedAt() {
        batch.updatedAt = .now
    }
}

private struct AddItemsStubSheet: View {
    @Environment(\.dismiss) private var dismiss
    let batchName: String

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This is a placeholder for the Batch Scope Builder.")
                        .font(.body)
                    Text("Next we’ll add a selection UI that lets you choose items from your catalog and create BatchItem join records.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(batchName.isEmpty ? "Add Items" : "Add Items to \(batchName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct AddSetsStubSheet: View {
    @Environment(\.dismiss) private var dismiss
    let batchName: String

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This is a placeholder for the Batch Scope Builder.")
                        .font(.body)
                    Text("Next we’ll add a selection UI that lets you choose sets from your catalog and create BatchSet join records.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(batchName.isEmpty ? "Add Sets" : "Add Sets to \(batchName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

