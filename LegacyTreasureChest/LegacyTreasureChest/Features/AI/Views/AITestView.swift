//
//  AITestView.swift
//  LegacyTreasureChest
//
//  Internal-use view for testing Gemini AI item analysis.
//

import SwiftUI
import PhotosUI

struct AITestView: View {

    // MARK: - State

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    @State private var isAnalyzing = false
    @State private var analysisResult: ItemAnalysis?
    @State private var errorMessage: String?

    @State private var hints = ItemAIHints()

    /// Local mirror of the Market AI feature flag (for dev only).
    @State private var isAIEnabled: Bool

    // MARK: - Init

    init() {
        _isAIEnabled = State(initialValue: FeatureFlags().enableMarketAI)
    }

    // MARK: - View

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {

                Text("AI Item Analysis Test")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.text)
                    .padding(.top, Theme.spacing.large)

                // MARK: - Dev Feature Toggle

                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("AI Feature (Dev)")
                        .ltcSectionHeaderStyle()

                    Toggle(isOn: $isAIEnabled) {
                        Text("Enable AI (Gemini)")
                            .font(Theme.bodyFont)
                            .foregroundStyle(Theme.text)
                    }
                    .tint(Theme.accent)
                }
                .padding(.trailing, Theme.spacing.medium)

                // MARK: - Image Picker

                VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                    Text("Select or Capture Photo")
                        .ltcSectionHeaderStyle()

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title)
                            Text("Choose Photo")
                                .font(Theme.bodyFont)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.accent.opacity(0.15))
                        .foregroundStyle(Theme.accent)
                        .cornerRadius(12)
                    }
                }

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 2)
                        .padding(.bottom, Theme.spacing.medium)
                }

                // MARK: - Hint Inputs

                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Optional Hints")
                        .ltcSectionHeaderStyle()

                    TextField("Your Title (optional)", text: Binding(
                        get: { hints.userWrittenTitle ?? "" },
                        set: { hints.userWrittenTitle = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.bodyFont)

                    TextField("Your Description (optional)", text: Binding(
                        get: { hints.userWrittenDescription ?? "" },
                        set: { hints.userWrittenDescription = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.bodyFont)

                    TextField("Known Category (optional)", text: Binding(
                        get: { hints.knownCategory ?? "" },
                        set: { hints.knownCategory = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.bodyFont)
                }

                // MARK: - Analyze Button

                Button {
                    Task { await runAnalysis() }
                } label: {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                        }
                        Text("Run Analysis")
                            .font(Theme.bodyFont.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.primary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(selectedImage == nil || isAnalyzing)

                // MARK: - Error Display

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.destructive)
                        .padding()
                        .ltcCardBackground()
                }

                // MARK: - Results Display

                if let result = analysisResult {
                    VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                        Text("Analysis Result")
                            .ltcSectionHeaderStyle()

                        analysisCard(result)
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, Theme.spacing.large)
        }
        .navigationTitle("AI Test")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhoto) { _, newValue in
            Task { await loadSelectedImage(from: newValue) }
        }
        .onChange(of: isAIEnabled) { _, newValue in
            let flags = FeatureFlags()
            flags.enableMarketAI = newValue
        }
    }

    // MARK: - Analysis Card

    @ViewBuilder
    private func analysisCard(_ result: ItemAnalysis) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {

            // Core summary
            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                Text(result.title)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)

                Text(result.summary)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)

                Text("Category: \(result.category)")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.text)
            }

            Divider()

            // Tags / confidence
            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                let tagsText = (result.tags ?? []).joined(separator: ", ")
                if !tagsText.isEmpty {
                    Text("Tags: \(tagsText)")
                        .font(Theme.secondaryFont)
                }

                if let c = result.confidence {
                    Text(String(format: "Confidence: %.2f", c))
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // Value hints
            if let value = result.valueHints {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Value Estimate (\(value.currencyCode))")
                        .font(Theme.bodyFont.weight(.semibold))

                    Text("Range: \(Int(value.low)) – \(Int(value.high))")
                    if let c = value.confidence {
                        Text(String(format: "Confidence: %.2f", c))
                    }
                    if !value.sources.isEmpty {
                        Text("Sources: \(value.sources.joined(separator: ", "))")
                    }
                    if let updated = value.lastUpdated, !updated.isEmpty {
                        Text("Last Updated: \(updated)")
                    }
                }
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.text)
            }

            // Detailed attributes
            VStack(alignment: .leading, spacing: Theme.spacing.small) {
                detailRow(label: "Brand", value: result.brand)
                detailRow(label: "Model", value: result.modelNumber)
                detailRow(label: "Maker", value: result.maker)

                let materials = (result.materials ?? []).joined(separator: ", ")
                if !materials.isEmpty {
                    detailRow(label: "Materials", value: materials)
                }

                detailRow(label: "Style", value: result.style)
                detailRow(label: "Origin", value: result.origin)
                detailRow(label: "Condition", value: result.condition)
                detailRow(label: "Dimensions", value: result.dimensions)
                detailRow(label: "Era / Year", value: result.eraOrYear)

                let features = (result.features ?? []).joined(separator: ", ")
                if !features.isEmpty {
                    detailRow(label: "Features", value: features)
                }
            }

            // Extracted text block
            if let text = result.extractedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Extracted Text")
                        .font(Theme.bodyFont.weight(.semibold))
                    Text(text)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .ltcCardBackground()
    }

    @ViewBuilder
    private func detailRow(label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: Theme.spacing.small) {
                Text("\(label):")
                    .font(Theme.secondaryFont.weight(.semibold))
                Text(value)
                    .font(Theme.secondaryFont)
            }
            .foregroundStyle(Theme.text)
        }
    }

    // MARK: - Helpers

    private func loadSelectedImage(from item: PhotosPickerItem?) async {
        guard let item else { return }

        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {

            self.selectedImage = image
        }
    }

    private func runAnalysis() async {
        guard let selectedImage else { return }

        isAnalyzing = true
        errorMessage = nil
        analysisResult = nil

        do {
            let result = try await AIService.shared.analyzeItemPhoto(selectedImage, hints: hints)
            analysisResult = result
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }
}
