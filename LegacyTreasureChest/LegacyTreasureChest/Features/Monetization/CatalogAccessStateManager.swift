//
//  CatalogAccessStateManager.swift
//  LegacyTreasureChest
//
//  Single authoritative read/write point for the local LTC 1.0 → 1.1
//  migration baseline and the one-time existing-user over-limit message
//  state. Backed by UserDefaults, following the same shape as
//  FeatureFlags / AICloudConsentManager.
//
//  This type is deliberately unaware of StoreKit and never stores a
//  paid/unlimited Boolean — the paid Full Catalog Access entitlement is
//  authoritative only via StoreKit's Transaction.currentEntitlements,
//  wired up separately.
//

import Foundation

final class CatalogAccessStateManager {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Migration Baseline

    /// Whether the migration baseline has already been captured on this
    /// device.
    var isMigrationBaselineCaptured: Bool {
        defaults.bool(forKey: AppConstants.StorageKeys.migrationBaselineCaptured)
    }

    /// The captured migration baseline item count. 0 if never captured.
    var migrationBaselineItemCount: Int {
        defaults.integer(forKey: AppConstants.StorageKeys.migrationBaselineItemCount)
    }

    /// Captures `currentItemCount` as this device's permanent migration
    /// baseline the first time it is called. Idempotent: once a baseline
    /// exists, later calls are no-ops, even if `currentItemCount` has
    /// since changed. The baseline is a reusable capacity ceiling (see
    /// `ItemCreationPolicy`), not a lifetime creation counter.
    func captureMigrationBaseline(currentItemCount: Int) {
        guard !isMigrationBaselineCaptured else { return }
        defaults.set(max(0, currentItemCount), forKey: AppConstants.StorageKeys.migrationBaselineItemCount)
        defaults.set(true, forKey: AppConstants.StorageKeys.migrationBaselineCaptured)
    }

    // MARK: - One-time Explanatory Message

    /// Whether the one-time "you're already at/above your free limit"
    /// message has been shown to an existing (migrated) user.
    var hasShownCatalogAccessLimitMessage: Bool {
        defaults.bool(forKey: AppConstants.StorageKeys.catalogAccessLimitMessageShown)
    }

    /// Marks the one-time explanatory message as shown so it is not
    /// presented again.
    func markCatalogAccessLimitMessageShown() {
        defaults.set(true, forKey: AppConstants.StorageKeys.catalogAccessLimitMessageShown)
    }

    // MARK: - Reset

    /// Clears all locally stored migration/free-tier state. Used by the
    /// full data-reset flow (see `AppDataResetCoordinator`) and available
    /// for testing. Never touches StoreKit — a genuine purchased Full
    /// Catalog Access entitlement is unaffected, since StoreKit remains
    /// authoritative for that state regardless of local resets.
    func reset() {
        defaults.removeObject(forKey: AppConstants.StorageKeys.migrationBaselineCaptured)
        defaults.removeObject(forKey: AppConstants.StorageKeys.migrationBaselineItemCount)
        defaults.removeObject(forKey: AppConstants.StorageKeys.catalogAccessLimitMessageShown)
    }
}
