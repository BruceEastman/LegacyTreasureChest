//
//  AppConstants.swift
//  LegacyTreasureChest
//
//  Created by Bruce Eastman on 11/19/25.
//

import Foundation

/// Global, app-wide constants for Legacy Treasure Chest.
///
/// Keep this focused on simple static values. Anything that depends on
/// runtime state belongs in a different type.
enum AppConstants {
    
    /// Human-readable app name used in UI.
    static let appDisplayName: String = "Legacy Treasure Chest"
    
    /// Minimum iOS version we actively support (matches deployment target).
    static let minimumSupportedIOS: String = "18.0"
    
    /// Organization / vendor information.
    enum Organization {
        static let developerName: String = "Legacy Treasure Chest"
        static let companyName: String = "Eastmancro LLC"
    }
    
    /// Keys used for UserDefaults / AppStorage.
    /// Centralizing them avoids typos and makes changes safer.
    enum StorageKeys {
        // Feature flags (to be wired up later)
        static let enableMarketAI = "enableMarketAI"
        static let enableCloudKit = "enableCloudKit"
        static let enableHouseholds = "enableHouseholds"
        static let showDebugInfo = "showDebugInfo"

        /// Raw value of AICloudConsentStatus — the user's choice about
        /// sending selected item data off-device for AI / Local Help.
        static let aiCloudConsentStatus = "aiCloudConsentStatus"

        // MARK: - Catalog Access (Monetization / Migration)

        /// Whether the LTC 1.0 → 1.1 migration baseline has already been
        /// captured on this device. See `CatalogAccessStateManager`.
        static let migrationBaselineCaptured = "ltc_migrationBaselineCaptured"

        /// The persisted LTCItem count captured once as this device's
        /// migration baseline capacity ceiling.
        static let migrationBaselineItemCount = "ltc_migrationBaselineItemCount"

        /// Whether the one-time "you're already at/above your limit"
        /// explanatory message has been shown to an existing user.
        static let catalogAccessLimitMessageShown = "ltc_catalogAccessLimitMessageShown"
    }

    /// Monetization values that are not UserDefaults keys.
    enum Monetization {
        /// Free allowance for new (non-migrated) users: current `LTCItem`
        /// count, not lifetime items ever created. See `ItemCreationPolicy`.
        static let standardFreeItemLimit = 25

        /// App Store Connect In-App Purchase Product ID for the
        /// "Full Catalog Access" non-consumable. Permanent once created in
        /// App Store Connect -- do not change after the product exists
        /// there. Centralized here so no view/service duplicates the
        /// literal string. See `PurchaseManager`.
        static let fullCatalogAccessProductID = "com.bruceeastman.LegacyTreasureChest.fullCatalogAccess"
    }

    /// URLs related to the app.
    enum URLs {
        static let supportSite: URL? = nil
        static let privacyPolicy: URL? = URL(string: "https://legacytreasurechest.com/privacy")
        static let termsOfUse: URL? = nil
    }
}
