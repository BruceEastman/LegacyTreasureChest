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

private struct BatchDetailView: View {
    let batch: LiquidationBatch

    var body: some View {
        Form {
            Section("Batch") {
                LabeledContent("Name", value: batch.name)
                LabeledContent("Status", value: batch.status.rawValue.capitalized)
                LabeledContent("Sale Type", value: batch.saleType.rawValue.capitalized)

                if let target = batch.targetDate {
                    LabeledContent("Target Date") {
                        Text(target, style: .date)
                    }
                } else {
                    LabeledContent("Target Date", value: "Not set")
                }

                if let venue = batch.venue?.rawValue, !venue.isEmpty {
                    LabeledContent("Venue", value: venue)
                }

                if let provider = batch.provider, !provider.isEmpty {
                    LabeledContent("Provider", value: provider)
                }

                LabeledContent("Created") {
                    Text(batch.createdAt, style: .date)
                }

                LabeledContent("Updated") {
                    Text(batch.updatedAt, style: .date)
                }
            }

            Section("Contents") {
                LabeledContent("Items", value: "\(batch.items.count)")
                LabeledContent("Sets", value: "\(batch.sets.count)")
            }

            Section("Scope Builder") {
                Text("Coming next: choose which items and sets belong in this batch, then generate lot numbers and handling notes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(batch.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

