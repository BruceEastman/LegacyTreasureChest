//
//  LiquidationPlanFactory.swift
//  LegacyTreasureChest
//
//  Creates a LiquidationPlan from a LiquidationBrief.
//
//  Key change:
//  - Plans are PATH-SPECIFIC (A/B/C/Donate) instead of always using brief.actionSteps.
//  - We still keep brief data as context, but the checklist is now operational.
//

import Foundation
import SwiftData

public enum LiquidationPlanFactory {

    // MARK: - Public

    public static func makePlan(
        for item: LTCItem,
        from brief: LiquidationBrief,
        chosenPath: LiquidationPath
    ) throws -> LiquidationPlan {

        let dto = try decodeBriefDTO(from: brief)

        let steps = buildChecklistSteps(
            scope: .item,
            chosenPath: chosenPath,
            title: item.name,
            category: item.category,
            briefDTO: dto
        )

        let checklist = LiquidationPlanChecklistDTO(
            schemaVersion: 1,
            createdAt: .now,
            items: steps.enumerated().map { index, step in
                LiquidationChecklistItemDTO(order: index + 1, text: step)
            }
        )

        let checklistData = try LiquidationJSONCoding.encode(checklist)

        let plan = LiquidationPlan(
            scope: .item,
            chosenPath: chosenPath,
            status: .notStarted,
            checklistJSON: checklistData,
            userNotes: nil,
            createdAt: .now,
            updatedAt: .now
        )

        plan.item = item
        item.liquidationPlan = plan

        item.selectedLiquidationPath = chosenPath
        item.liquidationStatus = .inProgress
        item.disposition = .liquidate

        return plan
    }

    public static func makePlan(
        for set: LTCSet,
        from brief: LiquidationBrief,
        chosenPath: LiquidationPath
    ) throws -> LiquidationPlan {

        let dto = try decodeBriefDTO(from: brief)

        let steps = buildChecklistSteps(
            scope: .set,
            chosenPath: chosenPath,
            title: set.name,
            category: set.setTypeRaw,
            briefDTO: dto
        )

        let checklist = LiquidationPlanChecklistDTO(
            schemaVersion: 1,
            createdAt: .now,
            items: steps.enumerated().map { index, step in
                LiquidationChecklistItemDTO(order: index + 1, text: step)
            }
        )

        let checklistData = try LiquidationJSONCoding.encode(checklist)

        let plan = LiquidationPlan(
            scope: .set,
            chosenPath: chosenPath,
            status: .notStarted,
            checklistJSON: checklistData,
            userNotes: nil,
            createdAt: .now,
            updatedAt: .now
        )

        plan.set = set
        set.liquidationPlan = plan

        return plan
    }

    // MARK: - Helpers

    private static func decodeBriefDTO(from brief: LiquidationBrief) throws -> LiquidationBriefDTO {
        guard !brief.payloadJSON.isEmpty else {
            throw NSError(
                domain: "LiquidationPlanFactory",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "LiquidationBrief.payloadJSON is empty. Generate or seed a brief before creating a plan."]
            )
        }

        guard let dto = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: brief.payloadJSON) else {
            throw NSError(
                domain: "LiquidationPlanFactory",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode LiquidationBriefDTO from payloadJSON. Schema mismatch or invalid JSON."]
            )
        }
        return dto
    }

    private static func buildChecklistSteps(
        scope: LiquidationScope,
        chosenPath: LiquidationPath,
        title: String,
        category: String,
        briefDTO: LiquidationBriefDTO
    ) -> [String] {

        // A little shared grounding at the top makes plans feel cohesive.
        var steps: [String] = [
            "Confirm item details for “\(title)” (\(category)) — photos, condition, measurements.",
            "Review the latest brief and note any missing details to improve outcome."
        ]

        // Then path-specific operational steps.
        switch chosenPath {
        case .pathA:
            steps += [
                "Take 10–14 high-quality photos (front/back/detail/maker marks/flaws).",
                "Measure key dimensions; capture maker marks/labels if present.",
                "Check 3–5 SOLD comps (not asking prices). Record typical range.",
                "Draft listing copy (materials, condition, provenance, measurements).",
                "Choose venue best fit for category (eBay/Etsy/Chairish/FB/etc.).",
                "Decide shipping vs local pickup; estimate shipping cost if shipping.",
                "List at a realistic price + small negotiation buffer; revisit after 7–10 days.",
                "Record offers and final sale; update actual net proceeds."
            ]

        case .pathB:
            steps += [
                "Identify 1–3 consignors / dealers that handle \(category).",
                "Prepare intake packet (photos + measurements + condition notes).",
                "Ask about commission %, payout timing, and pricing control.",
                "Confirm pickup/drop-off logistics and damage liability.",
                "Hand off item and store agreement details in notes.",
                "Follow up after 2–4 weeks; adjust strategy if stagnant."
            ]

        case .pathC:
            steps += [
                "Take 6–10 clear photos (include flaws).",
                "Write one-paragraph honest description (facts only).",
                "Set a fast-sale price (expect negotiation; decide your floor).",
                "Post locally (Facebook Marketplace / Nextdoor / Craigslist).",
                "Use safe pickup rules: daytime, no holds, confirm payment method.",
                "Close sale, record final price, mark completed."
            ]

        case .donate:
            steps += [
                "Pick donation destination (Goodwill, Habitat Restore, library, specialty charity).",
                "Take 1–2 photos for your records (optional).",
                "Drop off and request a receipt if useful for taxes.",
                "Record donation location + date in notes, mark completed."
            ]

        case .needsInfo:
            steps += [
                "Add missing details from the brief (measurements, maker marks, condition).",
                "Regenerate brief, then choose a path."
            ]
        }

        // Optional: append a tiny “brief summary” step so user remembers what AI suggested.
        steps.append("AI recommended: \(briefDTO.recommendedPath.rawValue). (Adjust if your situation differs.)")

        // For sets, add one extra operational reminder.
        if scope == .set {
            steps.insert("Confirm set completeness and decide together vs part-out approach.", at: 1)
        }

        return steps
    }
}
