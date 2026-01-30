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
    @Environment(\.modelContext) private var modelContext
    @Bindable var batch: LiquidationBatch

    @State private var hasTargetDate: Bool = false
    @State private var draftTargetDate: Date = .now

    @State private var showingAddItemsSheet = false
    @State private var showingAddSetsSheet = false

    @State private var selectedBatchItem: BatchItem?
    @State private var selectedBatchSet: BatchSet?

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
                        Button {
                            selectedBatchItem = entry
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.item?.name ?? "Unnamed Item")
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text(entry.dispositionRaw.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteBatchItems)
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
                        Button {
                            selectedBatchSet = entry
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.itemSet?.name ?? "Unnamed Set")
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text(entry.dispositionRaw.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteBatchSets)
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
            AddItemsToBatchSheet(batch: batch)
        }
        .sheet(isPresented: $showingAddSetsSheet) {
            AddSetsToBatchSheet(batch: batch)
        }
        .sheet(item: $selectedBatchItem) { entry in
            BatchItemEditorSheet(
                entry: entry,
                batchName: batch.name,
                onChanged: { touchUpdatedAt() }
            )
        }
        .sheet(item: $selectedBatchSet) { entry in
            BatchSetEditorSheet(
                entry: entry,
                batchName: batch.name,
                onChanged: { touchUpdatedAt() }
            )
        }
    }

    private func touchUpdatedAt() {
        batch.updatedAt = .now
    }

    private func deleteBatchItems(at offsets: IndexSet) {
        for index in offsets {
            let entry = batch.items[index]
            batch.items.remove(at: index)
            modelContext.delete(entry)
        }
        touchUpdatedAt()
    }

    private func deleteBatchSets(at offsets: IndexSet) {
        for index in offsets {
            let entry = batch.sets[index]
            batch.sets.remove(at: index)
            modelContext.delete(entry)
        }
        touchUpdatedAt()
    }
}

private struct AddItemsToBatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \LTCItem.createdAt, order: .reverse) private var items: [LTCItem]

    @Bindable var batch: LiquidationBatch

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Items Yet",
                        systemImage: "shippingbox",
                        description: Text("Add items to your catalog first, then come back to include them in this batch.")
                    )
                } else {
                    ForEach(items) { item in
                        Button {
                            addItemToBatch(item)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.body)

                                    if !item.category.isEmpty {
                                        Text(item.category)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if isAlreadyInBatch(item) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isAlreadyInBatch(item))
                    }
                }
            }
            .navigationTitle(batch.name.isEmpty ? "Add Items" : "Add Items to \(batch.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func isAlreadyInBatch(_ item: LTCItem) -> Bool {
        batch.items.contains(where: { $0.item?.itemId == item.itemId })
    }

    private func addItemToBatch(_ item: LTCItem) {
        guard !isAlreadyInBatch(item) else { return }

        let entry = BatchItem(disposition: .include)
        entry.batch = batch
        entry.item = item

        modelContext.insert(entry)
        batch.items.append(entry)

        batch.updatedAt = .now
    }
}

private struct AddSetsToBatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \LTCItemSet.createdAt, order: .reverse) private var sets: [LTCItemSet]

    @Bindable var batch: LiquidationBatch

    var body: some View {
        NavigationStack {
            List {
                if sets.isEmpty {
                    ContentUnavailableView(
                        "No Sets Yet",
                        systemImage: "shippingbox",
                        description: Text("Create sets in your catalog first, then come back to include them in this batch.")
                    )
                } else {
                    ForEach(sets) { set in
                        Button {
                            addSetToBatch(set)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(set.name)
                                        .font(.body)

                                    Text(set.setTypeRaw.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if isAlreadyInBatch(set) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isAlreadyInBatch(set))
                    }
                }
            }
            .navigationTitle(batch.name.isEmpty ? "Add Sets" : "Add Sets to \(batch.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func isAlreadyInBatch(_ set: LTCItemSet) -> Bool {
        batch.sets.contains(where: { $0.itemSet?.itemSetId == set.itemSetId })
    }

    private func addSetToBatch(_ set: LTCItemSet) {
        guard !isAlreadyInBatch(set) else { return }

        let entry = BatchSet(disposition: .include)
        entry.batch = batch
        entry.itemSet = set

        modelContext.insert(entry)
        batch.sets.append(entry)

        batch.updatedAt = .now
    }
}

// MARK: - Entry Editors

private struct BatchItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: BatchItem

    let batchName: String
    let onChanged: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    LabeledContent("Name", value: entry.item?.name ?? "Unnamed Item")
                    if let category = entry.item?.category, !category.isEmpty {
                        LabeledContent("Category", value: category)
                    }
                }

                Section("Batch Overrides") {
                    Picker("Disposition", selection: Binding<BatchItemDisposition>(
                        get: { entry.disposition },
                        set: { newValue in
                            entry.disposition = newValue
                            onChanged()
                        }
                    )) {
                        ForEach(BatchItemDisposition.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }

                    TextField("Lot Number", text: optionalTextBinding(
                        get: { entry.lotNumber },
                        set: { entry.lotNumber = $0; onChanged() }
                    ))

                    TextField("Room Group", text: optionalTextBinding(
                        get: { entry.roomGroup },
                        set: { entry.roomGroup = $0; onChanged() }
                    ))

                    let handlingBinding = optionalTextBinding(
                        get: { entry.handlingNotes },
                        set: { entry.handlingNotes = $0; onChanged() }
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Handling Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: handlingBinding)
                            .frame(minHeight: 80)
                    }

                    let sellerBinding = optionalTextBinding(
                        get: { entry.sellerNotes },
                        set: { entry.sellerNotes = $0; onChanged() }
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seller Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: sellerBinding)
                            .frame(minHeight: 80)
                    }
                }
            }
            .navigationTitle(batchName.isEmpty ? "Edit Item" : "Edit Item (\(batchName))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func optionalTextBinding(get: @escaping () -> String?, set: @escaping (String?) -> Void) -> Binding<String> {
        Binding<String>(
            get: { get() ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                set(trimmed.isEmpty ? nil : trimmed)
            }
        )
    }
}

private struct BatchSetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: BatchSet

    let batchName: String
    let onChanged: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Set") {
                    LabeledContent("Name", value: entry.itemSet?.name ?? "Unnamed Set")
                    if let typeRaw = entry.itemSet?.setTypeRaw, !typeRaw.isEmpty {
                        LabeledContent("Type", value: typeRaw)
                    }
                }

                Section("Batch Overrides") {
                    // Assumes BatchSet uses the same batch override enum (as your current build does).
                    Picker("Disposition", selection: Binding<BatchItemDisposition>(
                        get: { BatchItemDisposition(rawValue: entry.dispositionRaw) ?? .undecided },
                        set: { newValue in
                            entry.dispositionRaw = newValue.rawValue
                            onChanged()
                        }
                    )) {
                        ForEach(BatchItemDisposition.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }

                    TextField("Lot Number", text: optionalTextBinding(
                        get: { entry.lotNumber },
                        set: { entry.lotNumber = $0; onChanged() }
                    ))

                    TextField("Room Group", text: optionalTextBinding(
                        get: { entry.roomGroup },
                        set: { entry.roomGroup = $0; onChanged() }
                    ))

                    let handlingBinding = optionalTextBinding(
                        get: { entry.handlingNotes },
                        set: { entry.handlingNotes = $0; onChanged() }
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Handling Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: handlingBinding)
                            .frame(minHeight: 80)
                    }

                    let sellerBinding = optionalTextBinding(
                        get: { entry.sellerNotes },
                        set: { entry.sellerNotes = $0; onChanged() }
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seller Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: sellerBinding)
                            .frame(minHeight: 80)
                    }
                }
            }
            .navigationTitle(batchName.isEmpty ? "Edit Set" : "Edit Set (\(batchName))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func optionalTextBinding(get: @escaping () -> String?, set: @escaping (String?) -> Void) -> Binding<String> {
        Binding<String>(
            get: { get() ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                set(trimmed.isEmpty ? nil : trimmed)
            }
        )
    }
}

