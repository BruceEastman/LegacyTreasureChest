//
//  ExecutorMasterPacketExportView.swift
//  LegacyTreasureChest
//
//  UI entry point for generating Executor Master Packet exports.
//  v1: ZIP bundle (ExecutorSnapshot.pdf + DetailedInventory.pdf + optional media).
//

import SwiftUI
import SwiftData

struct ExecutorMasterPacketExportView: View {

    enum ShareIntent: String, CaseIterable, Identifiable {
        case mail = "Mail / Messages"
        case filesOrAirDrop = "Files / AirDrop"

        var id: String { rawValue }

        var allowsHardBlockOverride: Bool {
            switch self {
            case .mail: return false
            case .filesOrAirDrop: return true
            }
        }
    }

    // Estate dataset
    @Query(sort: \LTCItem.createdAt, order: .reverse)
    private var items: [LTCItem]

    @Query(sort: \LTCItemSet.createdAt, order: .reverse)
    private var itemSets: [LTCItemSet]

    @Query(sort: \LiquidationBatch.createdAt, order: .reverse)
    private var batches: [LiquidationBatch]

    @Query(sort: \Beneficiary.createdAt, order: .reverse)
    private var beneficiaries: [Beneficiary]

    @Environment(\.openURL) private var openURL

    @State private var estateName: String = "Estate"

    // Inclusions (PDFs are always included)
    @State private var includeAudio: Bool = false
    @State private var includeSupportingDocs: Bool = false

    @State private var includeImages: Bool = false
    @State private var includeFullResolutionImages: Bool = false

    @State private var shareIntent: ShareIntent = .mail
    @State private var preflight: ExecutorMasterPacketBundleBuilder.Preflight?

    @State private var isGenerating: Bool = false

    @State private var exportZIPURL: URL?
    @State private var showShareSheet: Bool = false
    @State private var shareURL: URL?

    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {

                headerSection

                if let exportZIPURL {
                    exportStatusSection(zipURL: exportZIPURL)
                }

                recipientSection
                inclusionSection
                preflightSection
                generateSection

                Spacer(minLength: Theme.spacing.xl)
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.top, Theme.spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Executor Master Packet")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                FileShareSheet(items: [shareURL])
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("Executor Master Packet Export", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error.")
        }
        .onAppear {
            refreshPreflight()
        }
        .onChange(of: estateName) { _, _ in refreshPreflight() }
        .onChange(of: includeAudio) { _, _ in refreshPreflight() }
        .onChange(of: includeSupportingDocs) { _, _ in refreshPreflight() }
        .onChange(of: includeImages) { _, _ in refreshPreflight() }
        .onChange(of: includeFullResolutionImages) { _, _ in refreshPreflight() }
        .onChange(of: shareIntent) { _, _ in refreshPreflight() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Executor Master Packet")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)

            Text("A formal, operational export for executor/attorney/CPA use.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)

            Text("Generated on-device. Shared as a ZIP bundle (2 PDFs + optional media).")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func exportStatusSection(zipURL: URL) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Text("Last Export")
                .ltcSectionHeaderStyle()

            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                Text(zipURL.lastPathComponent)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)

                if let bytes = safeFileSizeBytes(url: zipURL) {
                    Text("ZIP size: \(ExportSizeEstimator.formatBytes(bytes))")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: Theme.spacing.medium) {
                    Button { shareZIP() } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share ZIP")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)

                    Button { openURL(zipURL) } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text("Open ZIP")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .ltcCardBackground()
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Text("Packet Name")
                .ltcSectionHeaderStyle()

            TextField("Estate/Household name (for filename)", text: $estateName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .textFieldStyle(.roundedBorder)

            Text("Used for naming the ZIP: ExecutorMasterPacket_<Name>_<Date>.zip")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .ltcCardBackground()
    }

    private var inclusionSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Text("Include")
                .ltcSectionHeaderStyle()

            HStack {
                Image(systemName: "checkmark.square.fill")
                    .foregroundStyle(Theme.primary)
                Text("ExecutorSnapshot.pdf + DetailedInventory.pdf (always)")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }

            Toggle("Audio recordings", isOn: $includeAudio)
            Toggle("Supporting documents", isOn: $includeSupportingDocs)

            Toggle("Images", isOn: $includeImages)

            if includeImages {
                Toggle("Full-resolution images", isOn: $includeFullResolutionImages)
            }

            Divider().padding(.vertical, Theme.spacing.small)

            Text("Sharing preference")
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)

            Picker("Share", selection: $shareIntent) {
                ForEach(ShareIntent.allCases) { intent in
                    Text(intent.rawValue).tag(intent)
                }
            }
            .pickerStyle(.segmented)

            Text("Files/AirDrop enables an explicit override for the 250MB hard block.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .ltcCardBackground()
    }

    private var preflightSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Text("Estimated Size")
                .ltcSectionHeaderStyle()

            if let preflight {
                let est = preflight.estimate

                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Total: \(ExportSizeEstimator.formatBytes(est.totalBytes))")
                        .font(Theme.bodyFont.weight(.semibold))
                        .foregroundStyle(Theme.text)

                    Text("PDFs: \(ExportSizeEstimator.formatBytes(est.pdfBytes))")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)

                    if includeAudio {
                        Text("Audio: \(ExportSizeEstimator.formatBytes(est.audioBytes))")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if includeSupportingDocs {
                        Text("Docs: \(ExportSizeEstimator.formatBytes(est.documentBytes))")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if includeImages {
                        Text("Images: \(ExportSizeEstimator.formatBytes(est.imageBytes))")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                guardrailBanner(preflight.guardrail)

                Text(recommendationText(preflight.shareRecommendation))
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)

                if preflight.guardrail == .hardBlock && !shareIntent.allowsHardBlockOverride {
                    Text("Hard block: choose Files/AirDrop or reduce inclusions to generate.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.destructive)
                }
            } else {
                Text("Enter a packet name to estimate.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .ltcCardBackground()
    }

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Text("Generate ZIP")
                .ltcSectionHeaderStyle()

            Button { generate() } label: {
                HStack {
                    Image(systemName: "tray.full")
                    Text(isGenerating ? "Generating…" : "Generate Executor Master Packet ZIP")
                        .font(Theme.bodyFont.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isGenerating ? Color.gray : Theme.primary)
                .foregroundStyle(.white)
                .cornerRadius(16)
            }
            .disabled(isGenerating || isGenerateDisabled)

            Text("Creates two PDFs + optional assets in a folder, then zips and opens Share.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .ltcCardBackground()
    }

    // MARK: - Computed

    private var options: ExecutorMasterPacketComposer.InclusionOptions {
        ExecutorMasterPacketComposer.InclusionOptions(
            includeAudio: includeAudio,
            includeSupportingDocs: includeSupportingDocs,
            includeImages: includeImages,
            includeFullResolutionImages: includeFullResolutionImages
        )
    }

    private var isGenerateDisabled: Bool {
        let hasName = !estateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let hardBlocked: Bool = {
            guard let preflight else { return false }
            return preflight.guardrail == .hardBlock && !shareIntent.allowsHardBlockOverride
        }()

        return !hasName || hardBlocked || items.isEmpty
    }

    // MARK: - Preflight

    private func refreshPreflight() {
        let name = estateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { self.preflight = nil; return }

        let snapshot = ExecutorMasterPacketComposer.composeWithAssetIndexes(
            estateDisplayName: name,
            items: items,
            itemSets: itemSets,
            batches: batches,
            options: options
        )

        // For preflight we don’t generate PDFs; estimate PDFs as 0 to keep UI responsive.
        // The final preflight in the builder uses real PDF byte sizes.
        let pf = ExecutorMasterPacketBundleBuilder.preflight(
            snapshot: snapshot,
            pdfBytes: 0,
            options: options
        )

        self.preflight = pf
    }

    // MARK: - Generate

    private func generate() {
        errorMessage = nil
        showErrorAlert = false
        isGenerating = true

        exportZIPURL = nil
        shareURL = nil
        showShareSheet = false

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let name = estateName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    throw NSError(domain: "ExecutorMasterPacket", code: 1, userInfo: [NSLocalizedDescriptionKey: "Please enter an estate name."])
                }

                let snapshot = ExecutorMasterPacketComposer.composeWithAssetIndexes(
                    estateDisplayName: name,
                    items: items,
                    itemSets: itemSets,
                    batches: batches,
                    options: options
                )

                // Required PDFs (reuse existing generators; no rewrite)
                let snapshotPDF = EstateReportGenerator.generateSnapshotReport(
                    items: items,
                    itemSets: itemSets,
                    batches: batches,
                    beneficiaries: beneficiaries
                )

                let inventoryPDF = EstateReportGenerator.generateInventoryReport(items: items)

                guard !snapshotPDF.isEmpty, !inventoryPDF.isEmpty else {
                    throw NSError(domain: "ExecutorMasterPacket", code: 2, userInfo: [NSLocalizedDescriptionKey: "Generated PDFs were empty."])
                }

                let result = try ExecutorMasterPacketBundleBuilder.buildBundle(
                    snapshot: snapshot,
                    snapshotPDFData: snapshotPDF,
                    inventoryPDFData: inventoryPDF,
                    options: options,
                    allowHardBlockOverride: shareIntent.allowsHardBlockOverride
                )

                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.exportZIPURL = result.zipURL
                    self.preflight = result.preflight
                    self.shareURL = result.zipURL
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

    private func shareZIP() {
        guard let exportZIPURL else { return }
        shareURL = exportZIPURL
        showShareSheet = true
    }

    // MARK: - Guardrail UI

    @ViewBuilder
    private func guardrailBanner(_ guardrail: ExportSizeEstimator.Guardrail) -> some View {
        switch guardrail {
        case .ok:
            EmptyView()
        case .softWarning:
            Text("Soft warning: ≥ 50MB. Sharing may be slower.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.destructive)
        case .strongWarning:
            Text("Strong warning: ≥ 100MB. Prefer Files/AirDrop.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.destructive)
        case .hardBlock:
            Text("Hard block: ≥ 250MB. Reduce inclusions or choose Files/AirDrop (explicit override).")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.destructive)
        }
    }

    private func recommendationText(_ rec: ExportSizeEstimator.ShareRecommendation) -> String {
        switch rec {
        case .mailOkay:
            return "Recommended: Mail/Messages should work."
        case .preferFilesOrAirDrop:
            return "Recommended: Prefer Files or AirDrop for reliability."
        case .requireFilesOrAirDrop:
            return "Recommended: Use Files or AirDrop (Mail/Messages likely to fail)."
        }
    }

    // MARK: - Helpers

    private func safeFileSizeBytes(url: URL) -> Int64? {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize { return Int64(size) }
            return nil
        } catch {
            return nil
        }
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
