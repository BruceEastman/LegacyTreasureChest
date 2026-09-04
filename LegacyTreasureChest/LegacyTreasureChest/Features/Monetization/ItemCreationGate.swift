//
//  ItemCreationGate.swift
//  LegacyTreasureChest
//
//  The single production entry point views use to ask "can this many new
//  LTCItem records be created right now?" Combines the three inputs
//  ItemCreationPolicy needs -- the canonical persisted LTCItem count, the
//  migration baseline, and the verified StoreKit entitlement -- so no view
//  reproduces `currentCount < 25` or equivalent arithmetic itself.
//
//  This type owns the fetch (via ModelContext.fetchCount) rather than
//  requiring every call site to maintain its own @Query solely for
//  monetization. It stays a thin combinator: all capacity math lives in
//  ItemCreationPolicy, and all entitlement truth lives in PurchaseManager.
//

import Foundation
import SwiftData

@MainActor
enum ItemCreationGate {

    enum Decision: Equatable {
        /// The requested creation may proceed.
        case allowed
        /// Full Catalog Access is required. `remainingFreeCapacity` is how
        /// many items could still be created for free right now (0 if
        /// already at or over the effective limit).
        case requiresFullCatalogAccess(remainingFreeCapacity: Int)
        /// StoreKit hasn't answered whether Full Catalog Access is active
        /// yet (see `PurchaseManager.EntitlementState.resolving`). Never
        /// treated as "not entitled" -- callers should show a brief,
        /// calm "still checking" message rather than a paywall.
        case entitlementResolving
    }

    /// Evaluates whether `requestedItemCount` additional `LTCItem` records
    /// may be created right now. Fetches the canonical persisted count
    /// itself via `modelContext.fetchCount` -- callers should not pass a
    /// screen's filtered/search result count.
    ///
    /// Waits briefly for entitlement resolution first (see
    /// `PurchaseManager.waitForEntitlementResolution()`) so a tap landing
    /// in the short window right after launch doesn't get evaluated
    /// against an unresolved `.resolving` state as though it were
    /// `.notEntitled`. In the ordinary case this wait returns almost
    /// immediately; `.entitlementResolving` is only actually returned in
    /// the rare case resolution still hasn't completed after that wait.
    static func evaluate(
        requestedItemCount: Int,
        modelContext: ModelContext,
        purchaseManager: PurchaseManager,
        stateManager: CatalogAccessStateManager? = nil
    ) async -> Decision {
        await purchaseManager.waitForEntitlementResolution()

        guard purchaseManager.entitlementState != .resolving else {
            return .entitlementResolving
        }

        // Constructed here, inside the function body, rather than as the
        // parameter's default-value expression: default-argument
        // expressions are evaluated outside the function's own actor
        // isolation, so a MainActor-isolated init there (this module
        // defaults every type to @MainActor) would warn even though
        // ItemCreationGate itself is @MainActor.
        let stateManager = stateManager ?? CatalogAccessStateManager()

        let currentCount = (try? modelContext.fetchCount(FetchDescriptor<LTCItem>())) ?? 0
        let baseline = stateManager.migrationBaselineItemCount
        let hasAccess = purchaseManager.hasFullCatalogAccess

        if ItemCreationPolicy.canCreateItems(
            currentItemCount: currentCount,
            requestedItemCount: requestedItemCount,
            migrationBaselineItemCount: baseline,
            hasFullCatalogAccess: hasAccess
        ) {
            return .allowed
        }

        let remaining = ItemCreationPolicy.remainingFreeItemCapacity(
            currentItemCount: currentCount,
            migrationBaselineItemCount: baseline
        )
        return .requiresFullCatalogAccess(remainingFreeCapacity: remaining)
    }
}
