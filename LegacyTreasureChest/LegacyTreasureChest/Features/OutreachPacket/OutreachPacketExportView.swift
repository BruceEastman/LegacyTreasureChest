//
//  OutreachPacketExportView.swift
//  LegacyTreasureChest
//
//  UI entry point for generating Outreach Packet bundles.
//  v1: choose a Set or Batch, generate bundle folder, share it.
//

import SwiftUI
import SwiftData

struct OutreachPacketExportView: View {
    @Query(sort: \LTCItemSet.createdAt, order: .reverse)
    private var itemSets: [LTCItemSet]

    @Query(sort: \LiquidationBatch.createdAt, order: .reverse)
    private var batches: [LiquidationBatch]

    enum SelectionKind: String, CaseIterable, Identifiable {
        case set = "Set"
        case batch = "Batch"
        var id: String { rawValue }
    }

    @State private var selectionKind: SelectionKind = .set
    @State private var selectedSetID: PersistentIdentifier?
    @State private var selectedBatchID: PersistentIdentifier?

    @State private var isGenerating: Bool = false
    @State private var shareURL: URL?
    @State private var showShareSheet: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {

                headerSection

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.destructive)
                        .padding(.top, Theme.spacing.small)
                }

                selectionSection
                generateSection

                Spacer(minLength: Theme.spacing.xl)
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.top, Theme.spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Outreach Packet")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                FileShareSheet(items: [shareURL])
            }
        }
        .onAppear {
            ensureDefaultSelection()
        }
        .onChange(of: selectionKind) { _, _ in
            // When user switches Set <-> Batch, ensure the newly active selection isn't nil.
            ensureDefaultSelection()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Outreach Packet")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)

            Text("Generate a professional, range-only packet for consignment or evaluation discussions.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)

            Text("Generated on-device. No checklist state. No internal strategy content.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Text("Scope")
                .ltcSectionHeaderStyle()

            Picker("Scope", selection: $selectionKind) {
                ForEach(SelectionKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if selectionKind == .set {
                Picker("Set", selection: $selectedSetID) {
                    // ✅ Explicit nil tag prevents “selection nil invalid” warning.
                    Text("Select a Set").tag(Optional<PersistentIdentifier>(nil))

                    ForEach(itemSets, id: \.persistentModelID) { s in
                        Text(s.name.isEmpty ? "Unnamed Set" : s.name)
                            .tag(Optional(s.persistentModelID))
                    }
                }
            } else {
                Picker("Batch", selection: $selectedBatchID) {
                    Text("Select a Batch").tag(Optional<PersistentIdentifier>(nil))

                    ForEach(batches, id: \.persistentModelID) { b in
                        Text(b.name.isEmpty ? "Unnamed Batch" : b.name)
                            .tag(Optional(b.persistentModelID))
                    }
                }
            }
        }
        .ltcCardBackground()
    }

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Text("Generate Bundle")
                .ltcSectionHeaderStyle()

            Button {
                generate()
            } label: {
                HStack {
                    Image(systemName: "shippingbox")
                    Text(isGenerating ? "Generating…" : "Generate Outreach Packet Bundle")
                        .font(Theme.bodyFont.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isGenerating ? Color.gray : Theme.primary)
                .foregroundStyle(.white)
                .cornerRadius(16)
            }
            .disabled(isGenerating)

            Text("This exports a folder containing Packet.pdf. Audio/Documents bundling will be enabled next once we confirm storage paths.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .ltcCardBackground()
    }

    private func ensureDefaultSelection() {
        switch selectionKind {
        case .set:
            if selectedSetID == nil {
                selectedSetID = itemSets.first?.persistentModelID
            }
        case .batch:
            if selectedBatchID == nil {
                selectedBatchID = batches.first?.persistentModelID
            }
        }
    }

    private func generate() {
        errorMessage = nil
        isGenerating = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let target = try resolveTarget()
                // Use audio-enabled snapshot if you already made that change:
                // let snapshot = OutreachPacketComposer.composeWithAudioIndex(target: target)
                let snapshot = OutreachPacketComposer.composeWithAudioIndex(target: target)
                let pdfData = OutreachPacketPDFRenderer.render(snapshot: snapshot)

                guard !pdfData.isEmpty else {
                    throw NSError(domain: "OutreachPacket", code: 1, userInfo: [NSLocalizedDescriptionKey: "Generated PDF was empty."])
                }

                let result = try OutreachPacketBundleBuilder.buildBundle(snapshot: snapshot, pdfData: pdfData)

                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.shareURL = result.folderURL
                    self.showShareSheet = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func resolveTarget() throws -> OutreachPacketComposer.Target {
        switch selectionKind {
        case .set:
            guard let id = selectedSetID,
                  let set = itemSets.first(where: { $0.persistentModelID == id }) else {
                throw NSError(domain: "OutreachPacket", code: 2, userInfo: [NSLocalizedDescriptionKey: "Please select a Set."])
            }
            return .set(set)

        case .batch:
            guard let id = selectedBatchID,
                  let batch = batches.first(where: { $0.persistentModelID == id }) else {
                throw NSError(domain: "OutreachPacket", code: 3, userInfo: [NSLocalizedDescriptionKey: "Please select a Batch."])
            }
            return .batch(batch)
        }
    }
}

// MARK: - Share Sheet (same pattern as EstateReportsView)

private struct FileShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .openInIBooks
        ]
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        // no-op
    }
}
