//
//  LiquidationPlanContextHeader.swift
//  LegacyTreasureChest
//
//  Plan heading shared by the Item and Set Liquidate screens: the chosen
//  approach, its specific recommendation, and how the Plan was made.
//  Plans saved before Plan v2 have no context and show the title only.
//

import SwiftUI

struct LiquidationPlanContextHeader: View {
    let chosenPath: LiquidationPath
    let status: PlanStatus
    let checklist: LiquidationPlanChecklistDTO

    var body: some View {
        let context = checklist.context

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(UserFacingTerms.Liquidation.planTitle(chosenPath))
                    .font(.headline)
                Spacer()
                Text(UserFacingTerms.Liquidation.statusName(status))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let specific = context?.specificRecommendation {
                Text(specific)
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
            }

            if let note = Self.choiceNote(context) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let focus = checklist.focus, !focus.isEmpty {
                Text(focus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if checklist.isBasicPlan {
                Text(UserFacingTerms.Liquidation.basicPlanNotice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Provisional: …" or "Your choice (the Brief recommended …)", when either applies.
    static func choiceNote(_ context: LiquidationPlanContextDTO?) -> String? {
        guard let context else { return nil }
        if context.isProvisional {
            return UserFacingTerms.Liquidation.provisionalPlanNotice
        }
        if !context.wasRecommended, let rec = context.recommendedPath {
            return "Your choice (the Brief recommended \(rec.displayName))."
        }
        return nil
    }
}

/// One checklist step's wording: the step, plus its short detail line when present.
struct LiquidationChecklistStepLabel: View {
    let item: LiquidationChecklistItemDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(item.order). \(item.text)")
                .font(.subheadline)
            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
