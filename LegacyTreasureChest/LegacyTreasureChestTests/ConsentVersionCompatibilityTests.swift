//
//  ConsentVersionCompatibilityTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 5A: owners who accepted the 1.2 disclosure (stored status
//  "granted" with no disclosure version) are not interrupted unless they send
//  additional photos or a document. No network: requests go to a stub.
//

import Foundation
import Testing
@testable import LegacyTreasureChest

@MainActor
@Suite(.serialized)
struct ConsentVersionCompatibilityTests {

    /// Defaults exactly as 1.2 left them after the owner granted consent.
    private func version1Consent() -> (AICloudConsentManager, UserDefaults) {
        let suite = "consent-compat-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(AICloudConsentStatus.granted.rawValue, forKey: AppConstants.StorageKeys.aiCloudConsentStatus)
        return (AICloudConsentManager(defaults: defaults), defaults)
    }

    @Test func version1ConsentIsReadAsGrantedForStandardAnalysis() {
        let (consent, _) = version1Consent()
        #expect(consent.isOnlineProcessingAllowed)
        #expect(consent.acceptedDisclosureVersion == 1)
        #expect(!consent.isEvidenceDisclosureAccepted)
    }

    @Test func gateRunsStandardAnalysisWithoutPrompting() async {
        let (consent, _) = version1Consent()
        let gate = AIConsentGate(consent: consent)
        var ran = false
        await gate.perform(requiresEvidenceDisclosure: false) { ran = true }
        #expect(ran)
        #expect(!gate.isPresentingConsent)
    }

    @Test func gateShowsTheExpandedDisclosureOnlyForEvidence() async {
        let (consent, defaults) = version1Consent()
        let gate = AIConsentGate(consent: consent)
        var ran = false
        await gate.perform(requiresEvidenceDisclosure: true) { ran = true }
        #expect(!ran)
        #expect(gate.isPresentingConsent && gate.presentationMode == .evidenceUpdate)

        // Dismissing keeps the earlier consent; standard analysis still runs.
        gate.isPresentingConsent = false
        gate.handlePresentationEnded()
        #expect(consent.isOnlineProcessingAllowed && consent.acceptedDisclosureVersion == 1)
        await gate.perform(requiresEvidenceDisclosure: false) { ran = true }
        #expect(ran && !gate.isPresentingConsent)
        #expect(defaults.string(forKey: AppConstants.StorageKeys.aiCloudConsentStatus) == AICloudConsentStatus.granted.rawValue)
    }

    // The provider-level check (primary photo only, version 1 consent) lives in
    // EvidenceTransportTests, which owns the shared StubURLProtocol.

    @Test func noConsentStillPromptsTheStandardDisclosure() async {
        let suite = "consent-compat-none-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let gate = AIConsentGate(consent: AICloudConsentManager(defaults: defaults))
        var ran = false
        await gate.perform(requiresEvidenceDisclosure: true) { ran = true }
        #expect(!ran && gate.isPresentingConsent && gate.presentationMode == .standard)
    }
}
