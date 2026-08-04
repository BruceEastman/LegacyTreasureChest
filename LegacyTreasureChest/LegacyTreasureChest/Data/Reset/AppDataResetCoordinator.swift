//
//  AppDataResetCoordinator.swift
//  LegacyTreasureChest
//
//  Orchestrates a full local "Delete All Data" reset: every SwiftData
//  record, all app-managed media, known LTC-generated temporary export
//  artifacts, user preferences / feature overrides, AI consent, and the
//  diagnostic Keychain device identifier.
//
//  This app is account-free and the backend (LTC_AI_Gateway) is a stateless
//  service with no database and no user accounts, so this coordinator never
//  makes a network request — there is nothing on the server to delete.
//
//  Every stage either fully succeeds or throws `AppDataResetError` naming
//  the stage that failed. Nothing here silently swallows a failure.
//

import Foundation
import SwiftData

// MARK: - Error Model

enum AppDataResetStage: String {
    case swiftDataDeletion
    case swiftDataSave
    case swiftDataVerification
    case mediaRoot
    case mediaVerification
    case temporaryExports
    case deviceIdentity
}

/// Thrown when any stage of a full data reset fails. The stage and
/// underlying error are for debug logging only — `errorDescription` is the
/// calm, user-facing message and never includes filesystem paths, Security
/// framework status codes, or estate content.
struct AppDataResetError: Error, LocalizedError {
    let stage: AppDataResetStage
    let underlying: Error

    var errorDescription: String? {
        "Some Legacy Treasure Chest data could not be deleted. Your remaining data is still stored only on this iPhone. Please try again."
    }
}

// MARK: - Coordinator

enum AppDataResetCoordinator {

    /// Deletes every local record, file, preference, consent choice, and
    /// diagnostic identifier this app has stored on this device.
    ///
    /// Does not touch files the user has already exported to Files, Mail,
    /// Messages, AirDrop, or another app — those left the app's sandbox
    /// when exported and are never visible to this code. Makes no backend
    /// request.
    static func resetAllData(modelContext: ModelContext) throws {

        // MARK: 1–2. SwiftData: explicit delete of all 22 registered model
        // types, in relationship-safe order, then an explicit save.

        do {
            try deleteAllRecords(in: modelContext)
        } catch {
            logFailure(.swiftDataDeletion, error)
            throw AppDataResetError(stage: .swiftDataDeletion, underlying: error)
        }

        do {
            try modelContext.save()
        } catch {
            logFailure(.swiftDataSave, error)
            throw AppDataResetError(stage: .swiftDataSave, underlying: error)
        }

        // MARK: 3. Verify every registered model type has zero records.

        do {
            try verifyNoRecordsRemain(in: modelContext)
        } catch {
            logFailure(.swiftDataVerification, error)
            throw AppDataResetError(stage: .swiftDataVerification, underlying: error)
        }

        // MARK: 4. Delete and recreate the app-owned media root.

        do {
            try MediaStorage.deleteAndRecreateRoot()
        } catch {
            logFailure(.mediaRoot, error)
            throw AppDataResetError(stage: .mediaRoot, underlying: error)
        }

        do {
            let isEmpty = try MediaStorage.rootContainsNoFiles()
            guard isEmpty else {
                throw AppError.dataError("Media root still contains files after reset.")
            }
        } catch {
            logFailure(.mediaVerification, error)
            throw AppDataResetError(stage: .mediaVerification, underlying: error)
        }

        // MARK: 5. Remove known LTC-generated temporary export/report artifacts.

        do {
            try removeKnownTemporaryExports()
        } catch {
            logFailure(.temporaryExports, error)
            throw AppDataResetError(stage: .temporaryExports, underlying: error)
        }

        // MARK: 6. Reset user preferences / feature overrides to production defaults.

        resetUserDefaults()

        // MARK: 7. Reset AI consent to notDetermined (no network request).

        AICloudConsentManager().reset()

        // MARK: 8. Delete the diagnostic Keychain device identity.

        do {
            try LTCDeviceIdentity.deleteStoredIdentity()
        } catch {
            logFailure(.deviceIdentity, error)
            throw AppDataResetError(stage: .deviceIdentity, underlying: error)
        }

        print("✅ AppDataResetCoordinator: full data reset verified complete.")
    }

    // MARK: - SwiftData Deletion (relationship-safe order)

    /// Explicitly deletes every one of the 22 model types registered in
    /// `ModelContainer.makeContainer()`. Leaf / join / history records are
    /// deleted first, then mid-level containers, then root objects
    /// (`LTCItem`, `LTCUser`) last — this does not rely on cascade rules
    /// alone, since some legacy relationships (e.g. `LiquidationPlan`) have
    /// no cascade parent and some mid-level containers have an optional,
    /// sometimes-nil `user` back-reference.
    private static func deleteAllRecords(in modelContext: ModelContext) throws {
        try deleteAll(ItemBeneficiary.self, in: modelContext)
        try deleteAll(LTCItemSetMembership.self, in: modelContext)
        try deleteAll(LiquidationBriefRecord.self, in: modelContext)
        try deleteAll(LiquidationPlanRecord.self, in: modelContext)
        try deleteAll(LotChecklistItemState.self, in: modelContext)
        try deleteAll(BatchItem.self, in: modelContext)
        try deleteAll(BatchSet.self, in: modelContext)
        try deleteAll(LotExecutionState.self, in: modelContext)
        try deleteAll(ItemImage.self, in: modelContext)
        try deleteAll(AudioRecording.self, in: modelContext)
        try deleteAll(Document.self, in: modelContext)
        try deleteAll(ItemValuation.self, in: modelContext)
        try deleteAll(LiquidationState.self, in: modelContext)
        try deleteAll(LiquidationBrief.self, in: modelContext)
        try deleteAll(LiquidationPlan.self, in: modelContext)
        try deleteAll(Beneficiary.self, in: modelContext)
        try deleteAll(LTCItemSet.self, in: modelContext)
        try deleteAll(LiquidationBatch.self, in: modelContext)
        try deleteAll(LTCItem.self, in: modelContext)
        try deleteAll(LTCSet.self, in: modelContext)
        try deleteAll(TriageEntry.self, in: modelContext)
        try deleteAll(LTCUser.self, in: modelContext)
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) throws {
        let objects = try modelContext.fetch(FetchDescriptor<T>())
        for object in objects {
            modelContext.delete(object)
        }
    }

    // MARK: - SwiftData Verification

    /// Confirms all 22 registered model types have zero remaining records.
    /// Reports which type names (not record content) still have data, for
    /// debug logging only.
    private static func verifyNoRecordsRemain(in modelContext: ModelContext) throws {
        var remainingCounts: [String: Int] = [:]

        func check<T: PersistentModel>(_ type: T.Type, name: String) throws {
            let count = try modelContext.fetchCount(FetchDescriptor<T>())
            if count > 0 {
                remainingCounts[name] = count
            }
        }

        try check(ItemBeneficiary.self, name: "ItemBeneficiary")
        try check(LTCItemSetMembership.self, name: "LTCItemSetMembership")
        try check(LiquidationBriefRecord.self, name: "LiquidationBriefRecord")
        try check(LiquidationPlanRecord.self, name: "LiquidationPlanRecord")
        try check(LotChecklistItemState.self, name: "LotChecklistItemState")
        try check(BatchItem.self, name: "BatchItem")
        try check(BatchSet.self, name: "BatchSet")
        try check(LotExecutionState.self, name: "LotExecutionState")
        try check(ItemImage.self, name: "ItemImage")
        try check(AudioRecording.self, name: "AudioRecording")
        try check(Document.self, name: "Document")
        try check(ItemValuation.self, name: "ItemValuation")
        try check(LiquidationState.self, name: "LiquidationState")
        try check(LiquidationBrief.self, name: "LiquidationBrief")
        try check(LiquidationPlan.self, name: "LiquidationPlan")
        try check(Beneficiary.self, name: "Beneficiary")
        try check(LTCItemSet.self, name: "LTCItemSet")
        try check(LiquidationBatch.self, name: "LiquidationBatch")
        try check(LTCItem.self, name: "LTCItem")
        try check(LTCSet.self, name: "LTCSet")
        try check(TriageEntry.self, name: "TriageEntry")
        try check(LTCUser.self, name: "LTCUser")

        guard remainingCounts.isEmpty else {
            throw AppError.dataError(
                "Records remained after reset: \(remainingCounts.keys.sorted().joined(separator: ", "))"
            )
        }
    }

    // MARK: - Temporary Export Cleanup

    /// Removes only the temporary files/folders this app is known to
    /// create (report PDFs, Outreach/Beneficiary/Executor packet folders
    /// and ZIPs). Never clears `NSTemporaryDirectory()` wholesale, and
    /// tolerates any of these paths already being absent.
    private static func removeKnownTemporaryExports() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory

        let knownFilenames: Set<String> = [
            "Estate-Snapshot-Report.pdf",
            "Detailed-Inventory-Report.pdf"
        ]
        let knownPrefixes = [
            "OutreachPacket_",
            "BeneficiaryPacket_",
            "ExecutorMasterPacket_"
        ]

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        }

        for url in contents {
            let name = url.lastPathComponent
            let isKnownArtifact = knownFilenames.contains(name)
                || knownPrefixes.contains { name.hasPrefix($0) }
            guard isKnownArtifact else { continue }
            guard fm.fileExists(atPath: url.path) else { continue }
            try fm.removeItem(at: url)
        }
    }

    // MARK: - UserDefaults Cleanup

    /// Removes exactly the LTC-owned UserDefaults keys identified in the
    /// audit (onboarding, feature overrides, UI collapse/override state,
    /// last-used disposition search location, and the dynamic per-plan
    /// partner-selection keys). Never touches unrelated Apple/framework
    /// preferences. AI consent is reset separately via
    /// `AICloudConsentManager.reset()`.
    private static func resetUserDefaults() {
        let defaults = UserDefaults.standard

        let staticKeysToRemove: [String] = [
            "hasSeenStartHere",
            AppConstants.StorageKeys.enableMarketAI,
            AppConstants.StorageKeys.enableCloudKit,
            AppConstants.StorageKeys.enableHouseholds,
            AppConstants.StorageKeys.showDebugInfo,
            "ltc_feature_dispositionEngineUI",
            "ltc_fieldGuidanceCollapsed",
            "ltc_fieldGuidanceUserOverride",
            "ltc_aiGuidanceCollapsed",
            "ltc_aiGuidanceUserOverride",
            "ltc_itemCreationCount",
            "ltc.lastDisposition.city",
            "ltc.lastDisposition.region"
        ]

        for key in staticKeysToRemove {
            defaults.removeObject(forKey: key)
        }

        // Dynamic per-plan/block disposition partner selection keys, e.g.
        // "ltc.set.execute.partner.<planID>.<blockID>" (SetDetailView).
        let partnerSelectionPrefix = "ltc.set.execute.partner."
        let dynamicKeysToRemove = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(partnerSelectionPrefix)
        }
        for key in dynamicKeysToRemove {
            defaults.removeObject(forKey: key)
        }

        // Re-register compiled production defaults so the just-removed
        // feature override keys resolve back to their shipped values
        // immediately, without waiting for the next app launch.
        _ = FeatureFlags(defaults: defaults)
    }

    // MARK: - Logging

    /// Console-only diagnostic logging. Includes the failing stage and the
    /// underlying system error (which may include filesystem paths or
    /// Security status codes) but never estate content — this never
    /// reaches the user-facing error message.
    private static func logFailure(_ stage: AppDataResetStage, _ error: Error) {
        print("❌ AppDataResetCoordinator: stage '\(stage.rawValue)' failed: \(error)")
    }
}
