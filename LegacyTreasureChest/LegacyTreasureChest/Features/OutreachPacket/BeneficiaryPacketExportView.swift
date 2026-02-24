//
//  BeneficiaryPacketExportView.swift
//  LegacyTreasureChest
//
//  UI entry point for generating Beneficiary Packet exports.
//  v1: supports Set / Batch / explicit Items list.
//  When launched with a preset (e.g., from BeneficiaryDetailView), it locks to Items.
//

import SwiftUI
import SwiftData

struct BeneficiaryPacketExportView: View {

    // MARK: - Preset mode

    enum Preset {
        case beneficiary(name: String, items: [LTCItem])
    }

    private let preset: Preset?

    init(preset: Preset? = nil) {
        self.preset = preset
        // Seed state via _State in onAppear (safe); see applyPresetIfNeeded().
    }

    // MARK: - Data sources for dashboard mode

    @Query(sort: \LTCItemSet.createdAt, order: .reverse)
    private var itemSets: [LTCItemSet]

    @Query(sort: \LiquidationBatch.createdAt, order: .reverse)
    private var batches: [LiquidationBatch]

    enum SelectionKind: String, CaseIterable, Identifiable {
        case set = "Set"
        case batch = "Batch"
        case items = "Items"
        var id: String { rawValue }
    }

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

    @Environment(\.openURL) private var openURL

    @State private var selectionKind: SelectionKind = .set
    @State private var selectedSetID: PersistentIdentifier?
    @State private var selectedBatchID: PersistentIdentifier?

    // Items-mode selection (used when preset != nil)
    @State private var selectedItems: [LTCItem] = []
    @State private var isPresetLockedToItems: Bool = false

    @State private var beneficiaryName: String = ""

    // Inclusions (PDF is always included)
    @State private var includeAudio: Bool = false
    @State private var includeDocuments: Bool = false
    @State private var includeFullResolutionImages: Bool = false

    @State private var shareIntent: ShareIntent = .mail

    @State private var preflight: BeneficiaryPacketBundleBuilder.Preflight?

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

                selectionSection
                beneficiarySection
                inclusionSection
                preflightSection
                generateSection

                Spacer(minLength: Theme.spacing.xl)
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.top, Theme.spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Beneficiary Packet")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                FileShareSheet(items: [shareURL])
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("Beneficiary Packet Export", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error.")
        }
        .onAppear {
            applyPresetIfNeeded()
            ensureDefaultSelection()
            refreshPreflight()
        }
        .onChange(of: selectionKind) { _, _ in
            ensureDefaultSelection()
            refreshPreflight()
        }
        .onChange(of: selectedSetID) { _, _ in refreshPreflight() }
        .onChange(of: selectedBatchID) { _, _ in refreshPreflight() }
        .onChange(of: beneficiaryName) { _, _ in refreshPreflight() }
        .onChange(of: includeAudio) { _, _ in refreshPreflight() }
        .onChange(of: includeDocuments) { _, _ in refreshPreflight() }
        .onChange(of: includeFullResolutionImages) { _, _ in refreshPreflight() }
        .onChange(of: shareIntent) { _, _ in refreshPreflight() }
    }

    // MARK: - Preset application

    private func applyPresetIfNeeded() {
        guard let preset else { return }

        switch preset {
        case .beneficiary(let name, let items):
            beneficiaryName = name
            selectedItems = items
            selectionKind = .items
            isPresetLockedToItems = true
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Beneficiary Packet")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)

            Text("A personal, legacy-forward bundle for family members and heirs.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)

            Text("Generated on-device. Shared as a ZIP bundle (PDF + optional media).")
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
            .disabled(isPresetLockedToItems)

            switch selectionKind {
            case .set:
                Picker("Set", selection: $selectedSetID) {
                    Text("Select a Set").tag(Optional<PersistentIdentifier>(nil))
                    ForEach(itemSets, id: \.persistentModelID) { s in
                        Text(s.name.isEmpty ? "Unnamed Set" : s.name)
                            .tag(Optional(s.persistentModelID))
                    }
                }

            case .batch:
                Picker("Batch", selection: $selectedBatchID) {
                    Text("Select a Batch").tag(Optional<PersistentIdentifier>(nil))
                    ForEach(batches, id: \.persistentModelID) { b in
                        Text(b.name.isEmpty ? "Unnamed Batch" : b.name)
                            .tag(Optional(b.persistentModelID))
                    }
                }

            case .items:
                // In v1, Items mode is currently preset-driven (from Beneficiary detail).
                // If we later want manual multi-select, we can add it here.
                Text("\(selectedItems.count) item(s) selected")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .ltcCardBackground()
    }

    private var beneficiarySection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Text("Recipient")
                .ltcSectionHeaderStyle()

            TextField("Beneficiary name (e.g., Emma)", text: $beneficiaryName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .textFieldStyle(.roundedBorder)

            Text("Used for naming the ZIP: BeneficiaryPacket_<Name>_<Date>.zip")
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
                Text("PDF (always)")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }

            Toggle("Audio recordings", isOn: $includeAudio)
            Toggle("Documents", isOn: $includeDocuments)
            Toggle("Full-resolution images", isOn: $includeFullResolutionImages)

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

                    Text("PDF: \(ExportSizeEstimator.formatBytes(est.pdfBytes))")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)

                    if includeAudio {
                        Text("Audio: \(ExportSizeEstimator.formatBytes(est.audioBytes))")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if includeDocuments {
                        Text("Documents: \(ExportSizeEstimator.formatBytes(est.documentBytes))")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Text("Images: \(ExportSizeEstimator.formatBytes(est.imageBytes))")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
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
                Text("Select a scope and recipient to estimate.")
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
                    Image(systemName: "shippingbox.and.arrow.backward")
                    Text(isGenerating ? "Generating…" : "Generate Beneficiary Packet ZIP")
                        .font(Theme.bodyFont.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isGenerating ? Color.gray : Theme.primary)
                .foregroundStyle(.white)
                .cornerRadius(16)
            }
            .disabled(isGenerating || isGenerateDisabled)

            Text("Creates Packet.pdf + optional assets in a folder, then zips and opens Share.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .ltcCardBackground()
    }

    // MARK: - Computed

    private var options: BeneficiaryPacketComposer.InclusionOptions {
        BeneficiaryPacketComposer.InclusionOptions(
            includeAudio: includeAudio,
            includeDocuments: includeDocuments,
            includeFullResolutionImages: includeFullResolutionImages
        )
    }

    private var isGenerateDisabled: Bool {
        let hasRecipient = !beneficiaryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let hasTarget: Bool = {
            switch selectionKind {
            case .set: return selectedSetID != nil
            case .batch: return selectedBatchID != nil
            case .items: return !selectedItems.isEmpty
            }
        }()

        let hardBlocked: Bool = {
            guard let preflight else { return false }
            return preflight.guardrail == .hardBlock && !shareIntent.allowsHardBlockOverride
        }()

        return !hasRecipient || !hasTarget || hardBlocked
    }

    // MARK: - Selection

    private func ensureDefaultSelection() {
        // In preset items mode, don't override selections.
        if selectionKind == .items { return }

        switch selectionKind {
        case .set:
            if selectedSetID == nil { selectedSetID = itemSets.first?.persistentModelID }
        case .batch:
            if selectedBatchID == nil { selectedBatchID = batches.first?.persistentModelID }
        case .items:
            break
        }
    }

    private func resolveTarget() throws -> BeneficiaryPacketComposer.Target {
        switch selectionKind {
        case .set:
            guard let id = selectedSetID,
                  let set = itemSets.first(where: { $0.persistentModelID == id }) else {
                throw NSError(domain: "BeneficiaryPacket", code: 2, userInfo: [NSLocalizedDescriptionKey: "Please select a Set."])
            }
            return .set(set)

        case .batch:
            guard let id = selectedBatchID,
                  let batch = batches.first(where: { $0.persistentModelID == id }) else {
                throw NSError(domain: "BeneficiaryPacket", code: 3, userInfo: [NSLocalizedDescriptionKey: "Please select a Batch."])
            }
            return .batch(batch)

        case .items:
            guard !selectedItems.isEmpty else {
                throw NSError(domain: "BeneficiaryPacket", code: 5, userInfo: [NSLocalizedDescriptionKey: "No items selected."])
            }
            return .items(selectedItems)
        }
    }

    // MARK: - Preflight

    private func refreshPreflight() {
        do {
            let target = try resolveTarget()
            let name = beneficiaryName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { self.preflight = nil; return }

            let snapshot = BeneficiaryPacketComposer.composeWithAssetIndexes(
                target: target,
                beneficiaryDisplayName: name,
                options: options
            )

            let pf = BeneficiaryPacketBundleBuilder.preflight(
                snapshot: snapshot,
                pdfBytes: 0,
                options: options
            )

            self.preflight = pf
        } catch {
            self.preflight = nil
        }
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
                let target = try resolveTarget()
                let name = beneficiaryName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    throw NSError(domain: "BeneficiaryPacket", code: 1, userInfo: [NSLocalizedDescriptionKey: "Please enter a beneficiary name."])
                }

                let snapshot = BeneficiaryPacketComposer.composeWithAssetIndexes(
                    target: target,
                    beneficiaryDisplayName: name,
                    options: options
                )

                let pdfData = BeneficiaryPacketPDFRenderer.render(snapshot: snapshot)
                guard !pdfData.isEmpty else {
                    throw NSError(domain: "BeneficiaryPacket", code: 4, userInfo: [NSLocalizedDescriptionKey: "Generated PDF was empty."])
                }

                let result = try BeneficiaryPacketBundleBuilder.buildBundle(
                    snapshot: snapshot,
                    pdfData: pdfData,
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
