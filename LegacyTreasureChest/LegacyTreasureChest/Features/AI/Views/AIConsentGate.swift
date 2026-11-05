//
//  AIConsentGate.swift
//  LegacyTreasureChest
//
//  Shared "check consent, else show the disclosure sheet and resume once
//  granted" coordinator, so every AI / Local Help entry point doesn't have
//  to duplicate this flow. This is the view-level convenience layer; the
//  actual enforcement backstop lives in BackendAIProvider.postJSON, which
//  refuses to make a request regardless of whether a call site remembered
//  to use this gate.
//

import SwiftUI
import Combine

@MainActor
final class AIConsentGate: ObservableObject {

    @Published var isPresentingConsent: Bool = false

    /// Which disclosure the sheet shows: first-time consent, or the expanded
    /// (version 2) disclosure for owners who consented earlier.
    @Published var presentationMode: AICloudConsentView.Mode = .standard

    private let consent: AICloudConsentManager
    private var pendingAction: (() async -> Void)?

    init(consent: AICloudConsentManager? = nil) {
        self.consent = consent ?? AICloudConsentManager()
    }

    /// Runs `action` immediately if consent is already granted. Otherwise
    /// stores it and presents the disclosure sheet; the action resumes
    /// automatically, exactly once, only if the user grants consent there.
    /// No part of `action` runs if the user declines or dismisses.
    ///
    /// Pass `requiresEvidenceDisclosure: true` when the action sends
    /// additional photos or a document: owners who consented under the
    /// earlier disclosure then see the expanded disclosure once first.
    func perform(requiresEvidenceDisclosure: Bool = false, _ action: @escaping () async -> Void) async {
        let allowed = requiresEvidenceDisclosure
            ? consent.isEvidenceDisclosureAccepted
            : consent.isOnlineProcessingAllowed
        if allowed {
            await action()
            return
        }
        pendingAction = action
        presentationMode = (requiresEvidenceDisclosure && consent.isOnlineProcessingAllowed)
            ? .evidenceUpdate
            : .standard
        isPresentingConsent = true
    }

    /// Wired to AICloudConsentView's onDecision callback.
    func handleDecision(_ status: AICloudConsentStatus) {
        guard status == .granted else {
            pendingAction = nil
            return
        }
        guard let action = pendingAction else { return }
        pendingAction = nil
        Task { await action() }
    }

    /// Wired to the sheet's onDismiss, which also covers swipe-to-dismiss
    /// (no button tapped, so handleDecision never ran). Treated as
    /// cancellation: no action, no consent change.
    func handlePresentationEnded() {
        pendingAction = nil
    }
}

extension View {
    /// Presents the shared AI / Local Help consent sheet, driven by an
    /// AIConsentGate. Attach once per screen that has AI entry points.
    func aiConsentSheet(_ gate: AIConsentGate) -> some View {
        sheet(
            isPresented: Binding(
                get: { gate.isPresentingConsent },
                set: { gate.isPresentingConsent = $0 }
            ),
            onDismiss: {
                gate.handlePresentationEnded()
            }
        ) {
            AICloudConsentView(mode: gate.presentationMode) { status in
                gate.handleDecision(status)
            }
        }
    }
}
