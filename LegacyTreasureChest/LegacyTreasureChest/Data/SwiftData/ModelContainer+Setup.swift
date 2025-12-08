//
//  ModelContainer+Setup.swift
//  LegacyTreasureChest
//
//  SwiftData ModelContainer configuration.
//

import Foundation
import SwiftData

extension ModelContainer {
    /// Create and configure the SwiftData ModelContainer for the app.
    /// Used by LegacyTreasureChestApp as the primary container.
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            LTCUser.self,
            LTCItem.self,
            ItemImage.self,
            AudioRecording.self,
            Document.self,
            Beneficiary.self,
            ItemBeneficiary.self,
            ItemValuation.self        // ← NEW model added to schema
        ])
        
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            
            print("✅ ModelContainer created successfully (entities: \(schema.entities.count))")
            return container
        } catch {
            print("❌ Failed to create ModelContainer: \(error)")
            throw error
        }
    }
}
