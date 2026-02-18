//
//  ModelContainer+Setup.swift
//  LegacyTreasureChest
//
//  SwiftData ModelContainer configuration.
//

import Foundation
import SwiftData

extension ModelContainer {

    static func makeContainer() throws -> ModelContainer {

        let schema = Schema([

            // MARK: - Core User & Inventory
            LTCUser.self,
            LTCItem.self,
            ItemImage.self,
            AudioRecording.self,
            Document.self,
            ItemValuation.self,

            // MARK: - Beneficiaries
            Beneficiary.self,
            ItemBeneficiary.self,

            // MARK: - Sets v1 (NEW, primary path)
            LTCItemSet.self,
            LTCItemSetMembership.self,

            // MARK: - Liquidation (Pattern A – unified state)
            LiquidationState.self,
            LiquidationBriefRecord.self,
            LiquidationPlanRecord.self,

            // MARK: - Liquidation Batches (future, referenced by models)
            LiquidationBatch.self,
            BatchItem.self,
            BatchSet.self,              // ✅ ADD THIS (matches LiquidationBatch.sets)

            // MARK: - LEGACY Liquidation (kept for transition)
            LTCSet.self,
            LiquidationBrief.self,
            LiquidationPlan.self,
            TriageEntry.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )

        print("✅ ModelContainer created successfully (entities: \(schema.entities.count))")
        return container
    }
}

