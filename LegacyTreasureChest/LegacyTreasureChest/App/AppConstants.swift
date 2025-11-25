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
        static let developerName: String = "Bruce Eastman"
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
    }
    
    /// URLs related to the app. These are placeholders for now.
    enum URLs {
        static let supportSite: URL? = nil
        static let privacyPolicy: URL? = nil
        static let termsOfUse: URL? = nil
    }
}
