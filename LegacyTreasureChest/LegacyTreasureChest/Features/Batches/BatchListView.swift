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
                        // B1: Detail view not implemented yet
                        BatchStubDetailView(batch: batch)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(batch.name)
                                .font(.headline)

                            HStack(spacing: 12) {
                                Text(batch.status.rawValue.capitalized)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text(batch.saleType.rawValue.capitalized)
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

private struct BatchStubDetailView: View {
    let batch: LiquidationBatch

    var body: some View {
        Form {
            Section("Batch") {
                LabeledContent("Name", value: batch.name)
                LabeledContent("Status", value: batch.status.rawValue)
                LabeledContent("Sale Type", value: batch.saleType.rawValue)
            }

            Section("Contents") {
                LabeledContent("Items", value: "\(batch.items.count)")
                LabeledContent("Sets", value: "\(batch.sets.count)")
            }

            Section {
                Text("Batch detail, scope builder, and execution tools will be added in later steps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(batch.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

