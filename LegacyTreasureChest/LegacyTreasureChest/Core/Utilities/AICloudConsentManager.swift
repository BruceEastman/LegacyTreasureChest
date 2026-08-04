//
//  AICloudConsentManager.swift
//  LegacyTreasureChest
//
//  Single authoritative read/write point for AICloudConsentStatus.
//  Backed by UserDefaults, app-only (no App Group, no CloudKit sync).
//  This does not yet gate any network request — see AIService /
//  BackendAIProvider / DispositionAIService call sites for enforcement,
//  which is wired up separately.
//

import Foundation

final class AICloudConsentManager {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Current consent status. Defaults to `.notDetermined` if never set.
    var status: AICloudConsentStatus {
        get {
            guard
                let raw = defaults.string(forKey: AppConstants.StorageKeys.aiCloudConsentStatus),
                let value = AICloudConsentStatus(rawValue: raw)
            else {
                return .notDetermined
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: AppConstants.StorageKeys.aiCloudConsentStatus)
        }
    }

    /// Whether optional AI / Local Help features are currently allowed to
    /// send selected data off-device.
    var isOnlineProcessingAllowed: Bool {
        status == .granted
    }

    func grant() {
        status = .granted
    }

    func decline() {
        status = .declined
    }

    /// Turns off previously granted consent. Future requests must not be
    /// made until the user grants again.
    func revoke() {
        status = .declined
    }
}
