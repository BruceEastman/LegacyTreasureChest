//
//  ItemAnalysisRequestBuilder.swift
//  LegacyTreasureChest
//
//  Builds the Improve with AI request (LTC 1.3): legacy hints, source-labeled
//  context, the primary photo and any selected evidence.
//
//  Context labels where each piece of text came from (see SavedDescription in
//  ItemAnalysisApplier): the owner's notes, the owner's own description text,
//  and earlier AI text the owner accepted, which is marked as not verified.
//  When provenance cannot be determined (an AI paragraph edited afterwards) the
//  text is sent as "mixed" and is likewise treated as not verified.
//

import Foundation

/// One Improve with AI request, ready for AIService.analyzeItem.
nonisolated struct ItemAnalysisRequest: Sendable {
    /// Legacy hints (title, combined description and notes, category). A 1.3
    /// gateway uses `context` instead of the description; an older gateway
    /// would still receive the same text LTC 1.2 sent.
    var hints: ItemAIHints
    var context: ItemAnalysisContextDTO
    var primaryJPEG: Data?
    var supplementary: [SupplementaryEvidenceDTO]

    /// Additional photos or document pages are attached.
    var carriesEvidence: Bool { !supplementary.isEmpty }

    /// Photo/evidence endpoint when there is any image; text-only otherwise.
    var usesPhotoEndpoint: Bool { primaryJPEG != nil || carriesEvidence }

    var supplementaryPhotoCount: Int { supplementary.filter { $0.kind == .photo }.count }
    var documentPageCount: Int { supplementary.filter { $0.kind == .documentPage }.count }
}

enum ItemAnalysisRequestBuilder {

    /// Maps generated details-line labels to ItemAnalysis field names.
    static let attributeKeys: [String: String] = [
        "Brand": "brand",
        "Model": "modelNumber",
        "Maker": "maker",
        "Materials": "materials",
        "Style": "style",
        "Origin": "origin",
        "Era": "eraOrYear",
        "Dimensions": "dimensions",
        "Condition": "condition",
        "Features": "features",
    ]

    @MainActor
    static func build(for item: LTCItem, prepared: PreparedEvidence) -> ItemAnalysisRequest {
        ItemAnalysisRequest(
            hints: legacyHints(for: item),
            context: context(for: item),
            primaryJPEG: prepared.primaryJPEG,
            supplementary: prepared.supplementary
        )
    }

    /// The hints LTC 1.2 sends (ItemAIAnalysisSheet.runAnalysis): title,
    /// description plus "Additional details from owner", category.
    @MainActor
    static func legacyHints(for item: LTCItem) -> ItemAIHints {
        let base = item.itemDescription.isEmpty ? nil : item.itemDescription
        let extra = item.valuation?.userNotes?.trimmingCharacters(in: .whitespacesAndNewlines)

        let combined: String?
        if let base, let extra, !extra.isEmpty {
            combined = base + "\n\nAdditional details from owner:\n" + extra
        } else if let extra, !extra.isEmpty {
            combined = "Additional details from owner:\n" + extra
        } else {
            combined = base
        }

        return ItemAIHints(
            userWrittenTitle: item.name.isEmpty ? nil : item.name,
            userWrittenDescription: combined,
            knownCategory: item.category.isEmpty ? nil : item.category
        )
    }

    /// Source-labeled context for the item.
    @MainActor
    static func context(for item: LTCItem) -> ItemAnalysisContextDTO {
        let notes = item.valuation?.userNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = SavedDescription.classify(
            description: item.itemDescription,
            llmGeneratedDescription: item.llmGeneratedDescription
        )
        return ItemAnalysisContextDTO(
            quantity: max(item.quantity, 1),
            ownerNotes: (notes?.isEmpty ?? true) ? nil : notes,
            savedDescription: descriptionParts(saved),
            priorAttributes: priorAttributes(saved)
        )
    }

    static func descriptionParts(_ saved: SavedDescription) -> [ItemAnalysisContextDTO.DescriptionPart] {
        typealias Part = ItemAnalysisContextDTO.DescriptionPart
        func nonEmpty(_ text: String?) -> String? {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        switch saved.origin {
        case .empty:
            return []
        case .ownerWritten:
            return nonEmpty(saved.prose).map { [Part(origin: .owner, text: $0)] } ?? []
        case .aiGenerated:
            var parts: [Part] = []
            if let ai = nonEmpty(saved.aiParagraph) { parts.append(Part(origin: .priorAI, text: ai)) }
            if let other = nonEmpty(saved.otherText) { parts.append(Part(origin: .owner, text: other)) }
            return parts
        case .mixed:
            return nonEmpty(saved.prose).map { [Part(origin: .mixed, text: $0)] } ?? []
        }
    }

    static func priorAttributes(_ saved: SavedDescription) -> [String: String]? {
        var result: [String: String] = [:]
        for (label, value) in saved.generatedAttributes {
            if let key = attributeKeys[label] { result[key] = value }
        }
        return result.isEmpty ? nil : result
    }
}
