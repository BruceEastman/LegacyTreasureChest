//
//  LiquidationPlanAssembler.swift
//  LegacyTreasureChest
//
//  Plan v2: records the homeowner's choice with a generated checklist so Item
//  and Set Plans save the same context. The context lives inside the existing
//  Plan JSON (no SwiftData change) and stays fixed even if a later Brief
//  recommends something else.
//

import Foundation

enum LiquidationPlanAssembler {

    /// payloadVersion for Plans saved with a context.
    static let payloadVersion = "plan.v2"

    /// The checklist with the chosen approach, the Brief option it came from,
    /// and whether it was produced online or by the basic offline generator.
    static func withContext(
        _ checklist: LiquidationPlanChecklistDTO,
        chosenPath: LiquidationPath,
        brief: LiquidationBriefDTO,
        briefRecordId: UUID?
    ) -> LiquidationPlanChecklistDTO {
        let terms = UserFacingTerms.Liquidation.self
        let path = chosenPath.briefPath
        let option = brief.pathOptions.first(where: { $0.path == path })
        let name = terms.approachName(path)

        let specific: String? = option.map { terms.customerLabel($0.label) }
            .flatMap { $0.isEmpty || $0.caseInsensitiveCompare(name) == .orderedSame ? nil : $0 }

        let isBasic = checklist.aiProvider == LocalLiquidationPlanGenerator.providerName
        let generator: String = isBasic ? LiquidationPlanContextDTO.basicGenerator : LiquidationPlanContextDTO.aiGenerator
        let risks: [String] = (option?.risks ?? []).prefix(3).map { terms.customerText($0) }

        var result = checklist
        result.context = LiquidationPlanContextDTO(
            chosenPath: path,
            approachName: name,
            specificRecommendation: specific,
            wasRecommended: brief.recommendedPath == path,
            recommendedPath: brief.recommendedPath,
            isProvisional: brief.recommendedPath == .needsInfo,
            briefRecordId: briefRecordId,
            briefGeneratedAt: brief.generatedAt,
            estimatedNet: option?.netProceeds,
            effort: option?.effort,
            timeEstimate: option?.timeEstimate,
            keyRisks: risks,
            specialty: brief.specialty,
            generator: generator
        )
        return result
    }
}
