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

    @State private var lotAssignTarget: LotAssignTarget?

    var body: some View {
        Form {
            Section("Batch") {
                TextField("Name", text: $batch.name)
                    .onChange(of: batch.name) { _, _ in touchUpdatedAt() }

                Picker("Status", selection: Binding<LiquidationBatchStatus>(
                    get: { batch.status },
                    set: { newValue in
                        batch.status = newValue
                        touchUpdatedAt()
                    }
                )) {
                    ForEach(LiquidationBatchStatus.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }

                Picker("Sale Type", selection: Binding<LiquidationSaleType>(
                    get: { batch.saleType },
                    set: { newValue in
                        batch.saleType = newValue
                        touchUpdatedAt()
                    }
                )) {
                    ForEach(LiquidationSaleType.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }

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

                Picker("Venue", selection: Binding<VenueType?>(
                    get: { batch.venue },
                    set: { newValue in
                        batch.venue = newValue
                        touchUpdatedAt()
                    }
                )) {
                    Text("None").tag(Optional<VenueType>.none)

                    ForEach(VenueType.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(Optional(option))
                    }
                }

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

                Text("Status, Sale Type, and Venue are now constrained to safe pickers to prevent typos and keep downstream logic reliable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Contents") {
                LabeledContent("Items", value: "\(batch.items.count)")
                LabeledContent("Sets", value: "\(batch.sets.count)")
            }
            
            Section("Batch Readiness") {
                LabeledContent("Lots", value: "\(assignedLotCount) assigned (\(totalLotCount) total)")
                LabeledContent("Entries", value: "\(totalEntries) (Items \(batch.items.count), Sets \(batch.sets.count))")

                let percent = Int((decisionCompletion * 100).rounded())
                LabeledContent("Decisions", value: "\(decidedEntries)/\(totalEntries) (\(percent)%)")

                if undecidedEntries > 0 {
                    Text("You still have \(undecidedEntries) undecided entr\(undecidedEntries == 1 ? "y" : "ies"). For execution, try to resolve dispositions so every entry is Include/Exclude/Donate/Trash/Holdback.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if allEntriesUnassigned && totalEntries > 0 {
                    Text("All entries are still Unassigned. Assign lot numbers to create execution units (labels, staging areas, listing groups).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }


            // B11: Lots are navigable
            Section("Lots") {
                if lotGroups.isEmpty {
                    Text("No batch entries yet. Add items and sets, then assign lot numbers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(lotGroups) { group in
                        NavigationLink {
                            LotDetailView(batch: batch, lotKey: group.key)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(group.displayName)
                                        .font(.body.weight(.semibold))

                                    Spacer()

                                    let itemCount = group.items.count
                                    let setCount = group.sets.count
                                    Text("\(itemCount) item\(itemCount == 1 ? "" : "s"), \(setCount) set\(setCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                let value = lotItemValue(group.key)
                                let readiness = lotReadinessCounts(group.key)

                                HStack(spacing: 12) {
                                    Text(value, format: .currency(code: currencyCode))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text("Decisions: \(readiness.decided)/\(readiness.total)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Text("Tip: Use lots as your execution units for tagging, staging, and listing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
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

                                lotAndDispositionLine(lotNumber: entry.lotNumber, dispositionRaw: entry.dispositionRaw)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                presentLotAssignForItem(entry)
                            } label: {
                                Label("Assign Lot", systemImage: "tag")
                            }
                            Button(role: .destructive) {
                                clearLotForItem(entry)
                            } label: {
                                Label("Clear Lot", systemImage: "xmark.circle")
                            }
                        }
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

                                lotAndDispositionLine(lotNumber: entry.lotNumber, dispositionRaw: entry.dispositionRaw)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                presentLotAssignForSet(entry)
                            } label: {
                                Label("Assign Lot", systemImage: "tag")
                            }
                            Button(role: .destructive) {
                                clearLotForSet(entry)
                            } label: {
                                Label("Clear Lot", systemImage: "xmark.circle")
                            }
                        }
                    }
                    .onDelete(perform: deleteBatchSets)
                }
            }

            Section("Scope Builder") {
                Text("Coming next: bulk tools for lot assignment (multi-select, recent lots, and staging checklists).")
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
        .sheet(item: $lotAssignTarget) { target in
            LotAssignSheet(
                title: target.title,
                currentLot: target.currentLot,
                onSave: { newLot in
                    target.apply(newLot)
                    touchUpdatedAt()
                }
            )
        }
    }

    // MARK: - Lots

    private var lotGroups: [LotGroup] {
        var map: [String: LotGroup] = [:]

        for entry in batch.items {
            let key = normalizeLotKey(entry.lotNumber)
            map[key, default: LotGroup(key: key, items: [], sets: [])].items.append(entry)
        }

        for entry in batch.sets {
            let key = normalizeLotKey(entry.lotNumber)
            map[key, default: LotGroup(key: key, items: [], sets: [])].sets.append(entry)
        }

        let groups = Array(map.values).map { g in
            LotGroup(
                key: g.key,
                items: g.items.sorted(by: { ($0.item?.name ?? "") < ($1.item?.name ?? "") }),
                sets: g.sets.sorted(by: { ($0.itemSet?.name ?? "") < ($1.itemSet?.name ?? "") })
            )
        }

        return groups.sorted(by: lotGroupSort)
    }

    private func normalizeLotKey(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unassigned" : trimmed
    }

    private func lotGroupSort(_ a: LotGroup, _ b: LotGroup) -> Bool {
        if a.key == "Unassigned", b.key != "Unassigned" { return true }
        if b.key == "Unassigned", a.key != "Unassigned" { return false }

        let aNum = firstInt(in: a.key)
        let bNum = firstInt(in: b.key)

        if let aNum, let bNum, aNum != bNum {
            return aNum < bNum
        }

        return a.key.localizedCaseInsensitiveCompare(b.key) == .orderedAscending
    }

    private func firstInt(in text: String) -> Int? {
        let digits = text.compactMap { $0.isNumber ? $0 : nil }
        guard !digits.isEmpty else { return nil }
        return Int(String(digits))
    }

    private func lotAndDispositionLine(lotNumber: String?, dispositionRaw: String) -> some View {
        let lotKey = normalizeLotKey(lotNumber)
        let lotText = (lotKey == "Unassigned") ? "Lot: Unassigned" : "Lot: \(lotKey)"

        return Text("\(lotText) • \(dispositionRaw.capitalized)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Quick Lot Assign

    private func presentLotAssignForItem(_ entry: BatchItem) {
        let title = entry.item?.name ?? "Item"
        lotAssignTarget = LotAssignTarget(
            title: "Assign Lot — \(title)",
            currentLot: entry.lotNumber,
            apply: { newLot in entry.lotNumber = newLot }
        )
    }

    private func clearLotForItem(_ entry: BatchItem) {
        entry.lotNumber = nil
        touchUpdatedAt()
    }

    private func presentLotAssignForSet(_ entry: BatchSet) {
        let title = entry.itemSet?.name ?? "Set"
        lotAssignTarget = LotAssignTarget(
            title: "Assign Lot — \(title)",
            currentLot: entry.lotNumber,
            apply: { newLot in entry.lotNumber = newLot }
        )
    }

    private func clearLotForSet(_ entry: BatchSet) {
        entry.lotNumber = nil
        touchUpdatedAt()
    }

    // MARK: - Updates / Deletes

    private var totalEntries: Int {
        batch.items.count + batch.sets.count
    }

    private var decidedEntries: Int {
        let itemDecided = batch.items.filter {
            $0.dispositionRaw.localizedCaseInsensitiveCompare("Undecided") != .orderedSame
        }.count

        let setDecided = batch.sets.filter {
            $0.dispositionRaw.localizedCaseInsensitiveCompare("Undecided") != .orderedSame
        }.count

        return itemDecided + setDecided
    }

    private var undecidedEntries: Int {
        max(totalEntries - decidedEntries, 0)
    }

    private var decisionCompletion: Double {
        guard totalEntries > 0 else { return 0 }
        return Double(decidedEntries) / Double(totalEntries)
    }

    private var totalLotCount: Int {
        lotGroups.count
    }

    private var assignedLotCount: Int {
        lotGroups.filter { $0.key != "Unassigned" }.count
    }

    private var allEntriesUnassigned: Bool {
        guard totalEntries > 0 else { return false }
        return assignedLotCount == 0
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
    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private func effectiveUnitValue(for item: LTCItem) -> Double {
        if let estimated = item.valuation?.estimatedValue, estimated > 0 {
            return estimated
        }
        return max(item.value, 0)
    }

    private func effectiveTotalValue(for item: LTCItem) -> Double {
        let qty = max(item.quantity, 1)
        return effectiveUnitValue(for: item) * Double(qty)
    }

    private func lotItemValue(_ lotKey: String) -> Double {
        batch.items
            .filter { normalizeLotKey($0.lotNumber) == lotKey }
            .reduce(0) { partial, entry in
                guard let item = entry.item else { return partial }
                return partial + effectiveTotalValue(for: item)
            }
    }

    private func lotReadinessCounts(_ lotKey: String) -> (decided: Int, total: Int) {
        let items = batch.items.filter { normalizeLotKey($0.lotNumber) == lotKey }
        let sets  = batch.sets.filter  { normalizeLotKey($0.lotNumber) == lotKey }

        let itemDecided = items.filter {
            $0.dispositionRaw.localizedCaseInsensitiveCompare("Undecided") != .orderedSame
        }.count

        let setDecided = sets.filter {
            $0.dispositionRaw.localizedCaseInsensitiveCompare("Undecided") != .orderedSame
        }.count

        return (decided: itemDecided + setDecided,
                total: items.count + sets.count)
    }

}

private struct LotDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var batch: LiquidationBatch
    let lotKey: String

    @State private var selectedBatchItem: BatchItem?
    @State private var selectedBatchSet: BatchSet?

    @State private var showingRenameSheet = false

    var body: some View {
        Form {
            Section("Lot") {
                LabeledContent("Lot", value: displayName)
                LabeledContent("Items", value: "\(itemsInLot.count)")
                LabeledContent("Sets", value: "\(setsInLot.count)")

                LabeledContent("Estimated Value (items)") {
                    Text(lotItemValue, format: .currency(code: currencyCode))
                }

                LabeledContent("Decisions") {
                    Text("\(readiness.decided)/\(readiness.total)")
                }

                if lotKey == "Unassigned" {
                    Text("Unassigned entries have no lot number yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Use Rename Lot to change the lot number for everything in this lot.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !itemsInLot.isEmpty {
                Section("Items") {
                    ForEach(itemsInLot) { entry in
                        Button {
                            selectedBatchItem = entry
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.item?.name ?? "Unnamed Item")
                                    .foregroundStyle(.primary)
                                Text(entry.dispositionRaw.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !setsInLot.isEmpty {
                Section("Sets") {
                    ForEach(setsInLot) { entry in
                        Button {
                            selectedBatchSet = entry
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.itemSet?.name ?? "Unnamed Set")
                                    .foregroundStyle(.primary)
                                Text(entry.dispositionRaw.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if itemsInLot.isEmpty && setsInLot.isEmpty {
                Section {
                    Text("This lot is empty.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(lotKey == "Unassigned" ? "Assign Lot" : "Rename") {
                    showingRenameSheet = true
                }

                if lotKey != "Unassigned" {
                    Button("Clear Lot", role: .destructive) {
                        renameLot(to: nil)   // moves everything in this lot back to Unassigned
                    }
                }
            }
        }
        .sheet(isPresented: $showingRenameSheet) {
            LotRenameSheet(
                currentLot: lotKey,
                onSave: { newLot in
                    renameLot(to: newLot)
                }
            )
        }
        .sheet(item: $selectedBatchItem) { entry in
            BatchItemEditorSheet(
                entry: entry,
                batchName: batch.name,
                onChanged: { batch.updatedAt = .now }
            )
        }
        .sheet(item: $selectedBatchSet) { entry in
            BatchSetEditorSheet(
                entry: entry,
                batchName: batch.name,
                onChanged: { batch.updatedAt = .now }
            )
        }
    }

    private var displayName: String {
        lotKey == "Unassigned" ? "Unassigned" : "Lot \(lotKey)"
    }

    private var itemsInLot: [BatchItem] {
        batch.items
            .filter { normalizeLotKey($0.lotNumber) == lotKey }
            .sorted { ($0.item?.name ?? "") < ($1.item?.name ?? "") }
    }

    private var setsInLot: [BatchSet] {
        batch.sets
            .filter { normalizeLotKey($0.lotNumber) == lotKey }
            .sorted { ($0.itemSet?.name ?? "") < ($1.itemSet?.name ?? "") }
    }
    
    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var lotItemValue: Double {
        itemsInLot.reduce(0) { partial, entry in
            guard let item = entry.item else { return partial }

            let unit: Double = {
                if let estimated = item.valuation?.estimatedValue, estimated > 0 { return estimated }
                return max(item.value, 0)
            }()

            let qty = max(item.quantity, 1)
            return partial + (unit * Double(qty))
        }
    }

    private var readiness: (decided: Int, total: Int) {
        let itemDecided = itemsInLot.filter {
            $0.dispositionRaw.localizedCaseInsensitiveCompare("Undecided") != .orderedSame
        }.count

        let setDecided = setsInLot.filter {
            $0.dispositionRaw.localizedCaseInsensitiveCompare("Undecided") != .orderedSame
        }.count

        return (decided: itemDecided + setDecided,
                total: itemsInLot.count + setsInLot.count)
    }


    private func normalizeLotKey(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unassigned" : trimmed
    }

    private func renameLot(to newLot: String?) {
        let normalized = normalizeLotKey(newLot) // returns "Unassigned" if nil/empty

        // Rename in-place: any entry in this lot gets newLot (nil if unassigned)
        for entry in batch.items where normalizeLotKey(entry.lotNumber) == lotKey {
            entry.lotNumber = (normalized == "Unassigned") ? nil : normalized
        }
        for entry in batch.sets where normalizeLotKey(entry.lotNumber) == lotKey {
            entry.lotNumber = (normalized == "Unassigned") ? nil : normalized
        }

        batch.updatedAt = .now
        // modelContext autosaves; no explicit save required
    }
}

private struct LotRenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currentLot: String
    let onSave: (String?) -> Void

    @State private var lotText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("New Lot Number") {
                    TextField("e.g., 12", text: $lotText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("Leaving this blank will clear the lot number (move entries to Unassigned).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rename Lot \(currentLot)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = lotText.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                }
            }
            .onAppear {
                lotText = (currentLot == "Unassigned") ? "" : currentLot
            }
        }
    }
}

private struct LotGroup: Identifiable {
    var id: String { key }
    let key: String
    var items: [BatchItem]
    var sets: [BatchSet]

    var displayName: String {
        key == "Unassigned" ? "Unassigned" : "Lot \(key)"
    }
}

private struct LotAssignTarget: Identifiable {
    let id = UUID()
    let title: String
    let currentLot: String?
    let apply: (String?) -> Void
}

private struct LotAssignSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let currentLot: String?
    let onSave: (String?) -> Void

    @State private var lotText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Lot Number") {
                    TextField("e.g., 12", text: $lotText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("Tip: Keep lot numbers simple (1, 2, 3…) so labels and signage stay consistent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = lotText.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                }
            }
            .onAppear {
                lotText = currentLot ?? ""
            }
        }
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

