//
//  CatalogMigrationCoordinator.swift
//  LegacyTreasureChest
//
//  Captures the one-time LTC 1.0 → 1.1 migration baseline: the actual
//  persisted LTCItem count at the moment the new commercial limit first
//  becomes applicable on this device. See CatalogAccessStateManager for
//  the idempotent storage this relies on, and ItemCreationPolicy for how
//  the captured baseline is used afterward.
//

import Foundation
import SwiftData

enum CatalogMigrationCoordinator {

    /// Fetches the actual persisted `LTCItem` count (never a screen's
    /// filtered/search result) and captures it as the migration baseline
    /// if one hasn't been captured yet on this device. Safe to call on
    /// every launch — a no-op once a baseline exists.
    ///
    /// Never throws and never blocks launch: a fetch failure is logged
    /// and simply retried on the next launch, since nothing at startup
    /// depends on the baseline existing yet.
    static func captureBaselineIfNeeded(
        modelContext: ModelContext,
        stateManager: CatalogAccessStateManager = CatalogAccessStateManager()
    ) {
        guard !stateManager.isMigrationBaselineCaptured else { return }

        do {
            let count = try modelContext.fetchCount(FetchDescriptor<LTCItem>())
            stateManager.captureMigrationBaseline(currentItemCount: count)
        } catch {
            print("⚠️ CatalogMigrationCoordinator: failed to fetch LTCItem count for migration baseline: \(error)")
        }
    }
}
