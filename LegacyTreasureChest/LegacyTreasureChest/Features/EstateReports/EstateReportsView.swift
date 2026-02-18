//
//  EstateReportsView.swift
//  LegacyTreasureChest
//
//  v1 Estate Reports UI:
//  - Lets user generate Snapshot or Detailed Inventory PDF
//  - Writes PDF Data to a temporary .pdf file and shares the file URL
//
//  Quantity Support (v1):
//  - Reports now reflect total values (unit × quantity) where applicable.
//  - The Detailed Inventory PDF includes quantity, unit value, and total value.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EstateReportsView: View {
    @Query(sort: \LTCItem.createdAt, order: .forward)
    private var items: [LTCItem]

    @Query(sort: \Beneficiary.createdAt, order: .forward)
    private var beneficiaries: [Beneficiary]

    // NEW: include Sets + Batches for Disposition Snapshot v2
    @Query(sort: \LTCItemSet.createdAt, order: .forward)
    private var itemSets: [LTCItemSet]

    @Query(sort: \LiquidationBatch.createdAt, order: .forward)
    private var batches: [LiquidationBatch]

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

                if items.isEmpty {
                    emptyStateSection
                } else {
                    snapshotReportSection
                    detailedInventorySection
                }

                Spacer(minLength: Theme.spacing.xl)
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.top, Theme.spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Estate Reports")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                FileShareSheet(items: [shareURL])
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Estate Reports")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)

            Text("Generate PDF reports for estate planning, beneficiaries, or your executor.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)

            Text("Values are conservative resale estimates. Totals reflect quantity (unit value × quantity) where applicable.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("No items yet")
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)

            Text("Add items and valuations first. Reports will summarize your Legacy and Liquidate items.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .ltcCardBackground()
    }

    private var snapshotReportSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Estate Snapshot Report")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                Text("A high-level summary of your estate value and disposition readiness. Includes rollups for Items, Sets, and Batches where available.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)

                Button {
                    generateSnapshotPDF()
                } label: {
                    HStack {
                        Image(systemName: "doc.richtext")
                        Text(isGenerating ? "Generating…" : "Generate Snapshot Report PDF")
                            .font(Theme.bodyFont.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isGenerating ? Color.gray : Theme.primary)
                    .foregroundStyle(.white)
                    .cornerRadius(16)
                }
                .disabled(isGenerating)
            }
            .ltcCardBackground()
        }
    }

    private var detailedInventorySection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Detailed Inventory Report")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                Text("A complete list of all items including category, estate path (Legacy or Liquidate), beneficiary (if any), quantity, unit value, and total value.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)

                Button {
                    generateInventoryPDF()
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text(isGenerating ? "Generating…" : "Generate Inventory Report PDF")
                            .font(Theme.bodyFont.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isGenerating ? Color.gray : Theme.primary)
                    .foregroundStyle(.white)
                    .cornerRadius(16)
                }
                .disabled(isGenerating)
            }
            .ltcCardBackground()
        }
    }

    // MARK: - PDF Generation + Share

    private func generateSnapshotPDF() {
        guard !items.isEmpty else { return }
        errorMessage = nil
        isGenerating = true

        DispatchQueue.global(qos: .userInitiated).async {
            let data = EstateReportGenerator.generateSnapshotReport(
                items: items,
                itemSets: itemSets,
                batches: batches,
                beneficiaries: beneficiaries
            )
            DispatchQueue.main.async {
                self.finishAndShare(pdfData: data, filename: "Estate-Snapshot-Report.pdf")
            }
        }
    }

    private func generateInventoryPDF() {
        guard !items.isEmpty else { return }
        errorMessage = nil
        isGenerating = true

        DispatchQueue.global(qos: .userInitiated).async {
            let data = EstateReportGenerator.generateInventoryReport(items: items)
            DispatchQueue.main.async {
                self.finishAndShare(pdfData: data, filename: "Detailed-Inventory-Report.pdf")
            }
        }
    }

    private func finishAndShare(pdfData: Data, filename: String) {
        defer { isGenerating = false }

        guard !pdfData.isEmpty else {
            errorMessage = "Generated PDF was empty."
            return
        }

        do {
            let url = try writePDFToTemporaryFile(data: pdfData, filename: filename)
            self.shareURL = url
            self.showShareSheet = true
        } catch {
            errorMessage = "Could not create PDF file: \(error.localizedDescription)"
        }
    }

    private func writePDFToTemporaryFile(data: Data, filename: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        // Overwrite any existing file
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }
}

// MARK: - Share Sheet

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

