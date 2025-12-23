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
            LTCUser.self,
            LTCItem.self,
            ItemImage.self,
            AudioRecording.self,
            Document.self,
            Beneficiary.self,
            ItemBeneficiary.self,
            ItemValuation.self,

            // Liquidate module models
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
