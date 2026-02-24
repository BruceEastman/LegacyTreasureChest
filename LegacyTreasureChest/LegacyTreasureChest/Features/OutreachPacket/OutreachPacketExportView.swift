//
//  OutreachPacketExportView.swift
//  LegacyTreasureChest
//
//  UI entry point for generating Outreach Packet exports.
//  v1: choose a Set or Batch, generate Packet.pdf, share PDF.
//  (ZIP bundling is reserved for Beneficiary Packet.)
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

    @Environment(\.openURL) private var openURL

    @State private var selectionKind: SelectionKind = .set
    @State private var selectedSetID: PersistentIdentifier?
    @State private var selectedBatchID: PersistentIdentifier?

    @State private var isGenerating: Bool = false

    // Last export + sharing
    @State private var exportPDFURL: URL?
    @State private var pdfSizeBytes: Int64?
    @State private var showLargePDFWarning: Bool = false

    @State private var shareURL: URL?
    @State private var showShareSheet: Bool = false

    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String?

    /// Guardrail: warning threshold for large PDFs (tune later).
    private let largePDFThresholdBytes: Int64 = 50 * 1024 * 1024 // 50 MB

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {

                headerSection

                if let exportPDFURL {
                    exportStatusSection(pdfURL: exportPDFURL)
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
                    // ✅ Fix: ensure the system compose UI (Mail/Messages) has enough
                    // vertical space when the keyboard appears.
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("Outreach Packet Export", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error.")
        }
        .onAppear {
            ensureDefaultSelection()
        }
        .onChange(of: selectionKind) { _, _ in
            ensureDefaultSelection()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Outreach Packet")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)

            Text("Generate a professional, range-only packet for consignment or evaluation discussions.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)

            Text("Generated on-device. Shareable PDF only.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func exportStatusSection(pdfURL: URL) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Text("Last Export")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                Text(pdfURL.lastPathComponent)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)

                if let pdfSizeBytes {
                    Text("PDF size: \(formatBytes(pdfSizeBytes))")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                if showLargePDFWarning {
                    Text("Note: This PDF is large. Apple Mail may use Mail Drop (iCloud link) for delivery.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.destructive)
                }

                HStack(spacing: Theme.spacing.medium) {
                    Button {
                        sharePDF()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share PDF")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)

                    Button {
                        openURL(pdfURL)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("Open PDF")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .ltcCardBackground()
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
            Text("Generate PDF")
                .ltcSectionHeaderStyle()

            Button {
                generate()
            } label: {
                HStack {
                    Image(systemName: "shippingbox")
                    Text(isGenerating ? "Generating…" : "Generate Outreach Packet PDF")
                        .font(Theme.bodyFont.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isGenerating ? Color.gray : Theme.primary)
                .foregroundStyle(.white)
                .cornerRadius(16)
            }
            .disabled(isGenerating)

            Text("Creates Packet.pdf on-device and opens Share.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .ltcCardBackground()
    }

    // MARK: - Selection

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

    // MARK: - Generate

    private func generate() {
        errorMessage = nil
        showErrorAlert = false
        isGenerating = true

        exportPDFURL = nil
        pdfSizeBytes = nil
        showLargePDFWarning = false

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let target = try resolveTarget()
                let snapshot = OutreachPacketComposer.composeWithAudioIndex(target: target)
                let pdfData = OutreachPacketPDFRenderer.render(snapshot: snapshot)

                guard !pdfData.isEmpty else {
                    throw NSError(domain: "OutreachPacket", code: 1, userInfo: [NSLocalizedDescriptionKey: "Generated PDF was empty."])
                }

                let result = try OutreachPacketBundleBuilder.buildBundle(snapshot: snapshot, pdfData: pdfData)

                // Stable name per spec.
                let pdfURL = result.folderURL.appendingPathComponent("Packet.pdf")
                let pdfBytes = safeFileSizeBytes(url: pdfURL)

                DispatchQueue.main.async {
                    self.isGenerating = false

                    self.exportPDFURL = pdfURL
                    self.pdfSizeBytes = pdfBytes

                    let total = pdfBytes ?? 0
                    self.showLargePDFWarning = total >= self.largePDFThresholdBytes

                    // Share PDF immediately after generation.
                    self.shareURL = pdfURL
                    self.showShareSheet = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.errorMessage = error.localizedDescription
                    self.showErrorAlert = true
                }
            }
        }
    }

    // MARK: - Share

    private func sharePDF() {
        guard let exportPDFURL else { return }
        shareURL = exportPDFURL
        showShareSheet = true
    }

    // MARK: - Helpers

    private func safeFileSizeBytes(url: URL) -> Int64? {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize {
                return Int64(size)
            }
            return nil
        } catch {
            return nil
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Share Sheet (UIKit wrapper)

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
