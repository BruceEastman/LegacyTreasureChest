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

    // MARK: - Disclosure versions

    /// Version of the AI disclosure text the app currently shows.
    /// 1: original disclosure (a photo, item text, audio, valuation details).
    /// 2: LTC 1.3, adds additional photos and documents the owner selects for
    ///    Improve with AI.
    static let currentDisclosureVersion = 2

    /// The disclosure version the owner accepted. Owners who granted consent
    /// before versioning existed accepted version 1.
    var acceptedDisclosureVersion: Int {
        guard status == .granted else { return 0 }
        let stored = defaults.integer(forKey: AppConstants.StorageKeys.aiCloudConsentDisclosureVersion)
        return stored > 0 ? stored : 1
    }

    /// Whether additional photos and documents may be sent: consent is
    /// granted and the expanded (version 2) disclosure was accepted.
    var isEvidenceDisclosureAccepted: Bool {
        isOnlineProcessingAllowed && acceptedDisclosureVersion >= 2
    }

    func grant() {
        status = .granted
        defaults.set(Self.currentDisclosureVersion, forKey: AppConstants.StorageKeys.aiCloudConsentDisclosureVersion)
    }

    func decline() {
        status = .declined
        defaults.removeObject(forKey: AppConstants.StorageKeys.aiCloudConsentDisclosureVersion)
    }

    /// Turns off previously granted consent. Future requests must not be
    /// made until the user grants again.
    func revoke() {
        decline()
    }

    /// Resets consent back to `.notDetermined` by removing the persisted
    /// key, so the next check falls through to the default (see `status`
    /// getter). Used only by the full data-reset flow. This is a local
    /// UserDefaults write only — it makes no network request.
    func reset() {
        defaults.removeObject(forKey: AppConstants.StorageKeys.aiCloudConsentStatus)
        defaults.removeObject(forKey: AppConstants.StorageKeys.aiCloudConsentDisclosureVersion)
    }
}
