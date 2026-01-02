//
//  SetsListView.swift
//  LegacyTreasureChest
//
//  Sets v1: List + create sets.
//

import SwiftUI
import SwiftData

struct SetsListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \LTCItemSet.updatedAt, order: .reverse)
    private var sets: [LTCItemSet]

    @State private var searchText: String = ""
    @State private var isPresentingCreate: Bool = false

    private var filteredSets: [LTCItemSet] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sets }
        return sets.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List {
            if filteredSets.isEmpty {
                ContentUnavailableView(
                    "No Sets Yet",
                    systemImage: "square.stack.3d.up",
                    description: Text("Create a set to group items you may want to sell together.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredSets) { set in
                    NavigationLink {
                        SetDetailView(itemSet: set)
                    } label: {
                        HStack(spacing: Theme.spacing.medium) {
                            Image(systemName: "square.stack.3d.up")
                                .foregroundStyle(Theme.accent)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(set.name)
                                    .font(Theme.bodyFont.weight(.semibold))
                                    .foregroundStyle(Theme.text)

                                Text("\(set.memberships.count) item(s) • \(set.setType.rawValue)")
                                    .font(Theme.secondaryFont)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, Theme.spacing.xs)
                    }
                }
                .onDelete(perform: deleteSets)
            }
        }
        .navigationTitle("Sets")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search sets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Set")
            }
        }
        .sheet(isPresented: $isPresentingCreate) {
            NavigationStack {
                SetEditorSheet(mode: .create)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func deleteSets(at offsets: IndexSet) {
        let targets = offsets.map { filteredSets[$0] }
        for set in targets {
            modelContext.delete(set)
        }
    }
}
