//
//  FeatureFlags.swift
//  LegacyTreasureChest
//
//  Centralized feature toggles backed by UserDefaults.
//  Updated so Market AI defaults to ON on first launch.
//

import Foundation

/// Central storage for feature toggles used throughout the app.
/// Values are persisted in UserDefaults using keys from `AppConstants.StorageKeys`.
final class FeatureFlags {
    
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaultValues()
        logCurrentValues()
    }
    
    /// Register default values **only for keys that are not already set**.
    /// This ensures first-launch behavior works correctly while preserving overrides.
    private func registerDefaultValues() {
        let defaultsToRegister: [String: Any] = [
            AppConstants.StorageKeys.enableMarketAI: true,   // 🔥 AI ON by default
            AppConstants.StorageKeys.enableCloudKit: false,
            AppConstants.StorageKeys.enableHouseholds: false,
            AppConstants.StorageKeys.showDebugInfo: false
        ]
        
        defaults.register(defaults: defaultsToRegister)
    }
    
    // MARK: - Market / AI
    
    /// Enables Gemini-powered valuation & market intelligence.
    /// Default = TRUE on fresh installs.
    var enableMarketAI: Bool {
        get { defaults.bool(forKey: AppConstants.StorageKeys.enableMarketAI) }
        set { defaults.set(newValue, forKey: AppConstants.StorageKeys.enableMarketAI) }
    }
    
    // MARK: - Cloud & Sync
    
    /// Enables iCloud / CloudKit sync (Phase 1E).
    var enableCloudKit: Bool {
        get { defaults.bool(forKey: AppConstants.StorageKeys.enableCloudKit) }
        set { defaults.set(newValue, forKey: AppConstants.StorageKeys.enableCloudKit) }
    }
    
    // MARK: - Household Sharing
    
    /// Enables multi-user shared inventories (Phase 2).
    var enableHouseholds: Bool {
        get { defaults.bool(forKey: AppConstants.StorageKeys.enableHouseholds) }
        set { defaults.set(newValue, forKey: AppConstants.StorageKeys.enableHouseholds) }
    }
    
    // MARK: - Developer Features
    
    /// Shows debug information in the UI (local-only).
    var showDebugInfo: Bool {
        get { defaults.bool(forKey: AppConstants.StorageKeys.showDebugInfo) }
        set { defaults.set(newValue, forKey: AppConstants.StorageKeys.showDebugInfo) }
    }
    
    // MARK: - Logging
    
    private func logCurrentValues() {
        print("🚩 FeatureFlags initialized:")
        print("   • MarketAI      = \(enableMarketAI)")
        print("   • CloudKit      = \(enableCloudKit)")
        print("   • Households    = \(enableHouseholds)")
        print("   • Debug         = \(showDebugInfo)")
    }
}
