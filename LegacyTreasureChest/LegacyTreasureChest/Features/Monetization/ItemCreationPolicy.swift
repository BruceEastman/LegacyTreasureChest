//
//  ItemCreationPolicy.swift
//  LegacyTreasureChest
//
//  Pure, deterministic catalog-capacity policy for LTC item creation.
//  Consumes inputs supplied by its caller (current item count, migration
//  baseline, paid-entitlement state) rather than reading UserDefaults,
//  SwiftData, or StoreKit itself, so the same rules can be evaluated
//  anywhere without duplicating monetization logic in views.
//
//  The monetization unit is strictly the number of persisted LTCItem
//  records. Existing records are never locked — this policy only ever
//  gates the creation of additional items.
//

import Foundation

enum ItemCreationPolicy {

    /// The effective free-tier ceiling for a given migration baseline.
    /// New (non-migrated) users get the standard free limit; an existing
    /// 1.0 user keeps at least their captured migration baseline as a
    /// reusable capacity ceiling, even if it exceeds the standard limit.
    static func effectiveFreeLimit(migrationBaselineItemCount: Int) -> Int {
        max(AppConstants.Monetization.standardFreeItemLimit, max(0, migrationBaselineItemCount))
    }

    /// How many more items may be created for free right now, given the
    /// current item count and migration baseline. Never negative.
    static func remainingFreeItemCapacity(
        currentItemCount: Int,
        migrationBaselineItemCount: Int
    ) -> Int {
        let limit = effectiveFreeLimit(migrationBaselineItemCount: migrationBaselineItemCount)
        return max(0, limit - max(0, currentItemCount))
    }

    /// Whether `requestedItemCount` additional items may be created right
    /// now.
    ///
    /// A non-positive `requestedItemCount` is always allowed — there is
    /// nothing to gate — so callers can pass a raw, unvalidated count
    /// (e.g. a photo-picker selection) without a separate guard.
    ///
    /// `hasFullCatalogAccess` short-circuits to always-allowed; nothing in
    /// this type supplies that value itself, it is passed in by a caller
    /// backed by StoreKit's verified entitlement state.
    static func canCreateItems(
        currentItemCount: Int,
        requestedItemCount: Int,
        migrationBaselineItemCount: Int,
        hasFullCatalogAccess: Bool
    ) -> Bool {
        guard requestedItemCount > 0 else { return true }
        if hasFullCatalogAccess { return true }

        let remaining = remainingFreeItemCapacity(
            currentItemCount: currentItemCount,
            migrationBaselineItemCount: migrationBaselineItemCount
        )
        return requestedItemCount <= remaining
    }
}
