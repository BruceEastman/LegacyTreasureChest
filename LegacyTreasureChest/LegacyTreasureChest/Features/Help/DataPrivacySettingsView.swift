//
//  DataPrivacySettingsView.swift
//  LegacyTreasureChest
//
//  Release-reachable hub for data & privacy: review AI/online assistance,
//  read the privacy policy, or permanently delete all Legacy Treasure
//  Chest data from this iPhone. Reached from Guide > Data & Privacy.
//
//  The actual deletion work happens in AppDataResetCoordinator — this view
//  only drives the confirmation UX and reflects deletion progress/result.
//

import SwiftUI
import SwiftData

/// Local UI state for the destructive confirmation flow. Not persisted.
private enum DeletionPhase: Equatable {
    case idle
    case inProgress
    case succeeded
    case failed(String)
}

/// Local, non-persisted feedback state for the Restore Purchases action.
private enum RestoreResult: Equatable {
    case entitled
    case notFound
}

struct DataPrivacySettingsView: View {
    /// Called once a full data reset has been verified successful and the
    /// user has dismissed the result. The caller is responsible for
    /// returning to a safe root screen and re-presenting onboarding.
    let onDataResetCompleted: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var isShowingDeleteConfirmation = false
    @State private var deletionPhase: DeletionPhase = .idle

    @State private var isRestoring = false
    @State private var restoreResult: RestoreResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {

                header

                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Review")
                        .ltcSectionHeaderStyle()

                    NavigationLink {
                        AIPrivacySettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.spacing.small) {
                            Text("AI & Online Assistance")
                                .font(Theme.bodyFont.weight(.semibold))
                                .foregroundStyle(Theme.text)

                            Text("Review what's sent when you use AI features or Local Help, and turn AI features on or off.")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ltcCardBackground()
                    }

                    if let url = AppConstants.URLs.privacyPolicy {
                        Link("Privacy Policy", destination: url)
                            .font(Theme.secondaryFont.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .padding(.top, Theme.spacing.xs)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Full Catalog Access")
                        .ltcSectionHeaderStyle()

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        if purchaseManager.hasFullCatalogAccess {
                            Label("Full Catalog Access: Active", systemImage: "checkmark.circle.fill")
                                .font(Theme.bodyFont.weight(.semibold))
                                .foregroundStyle(Theme.text)
                        } else {
                            Text("Full Catalog Access removes the free catalog item limit. It's offered as a one-time purchase when you reach your catalog allowance.")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            restorePurchases()
                        } label: {
                            HStack {
                                if isRestoring {
                                    ProgressView()
                                }
                                Text("Restore Purchases")
                                    .font(Theme.bodyFont.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacing.medium)
                            .background(Color(.systemGray6))
                            .foregroundStyle(Theme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isRestoring)

                        Text("Restore Purchases recovers a Full Catalog Access purchase already made with this Apple Account on this device. It does not restore deleted catalog data.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .ltcCardBackground()
                }

                VStack(alignment: .leading, spacing: Theme.spacing.small) {
                    Text("Delete All Data")
                        .ltcSectionHeaderStyle()

                    VStack(alignment: .leading, spacing: Theme.spacing.small) {
                        Text("Permanently erase all inventory, beneficiaries, sets, batches, plans, photos, documents, audio, and app preferences stored on this iPhone.")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(role: .destructive) {
                            deletionPhase = .idle
                            isShowingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete All Data")
                                    .font(Theme.bodyFont.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacing.medium)
                            .background(Color(.systemGray6))
                            .foregroundStyle(Theme.destructive)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .ltcCardBackground()
                }

                Spacer(minLength: Theme.spacing.large)
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.vertical, Theme.spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingDeleteConfirmation) {
            DeleteAllDataConfirmationView(
                phase: $deletionPhase,
                onConfirm: performDeletion,
                onDismissAfterSuccess: {
                    isShowingDeleteConfirmation = false
                    deletionPhase = .idle
                    onDataResetCompleted()
                }
            )
            .interactiveDismissDisabled(deletionPhase == .inProgress)
        }
        .alert(
            restoreResult == .entitled ? "Full Catalog Access Restored" : "No Purchase Found",
            isPresented: Binding(
                get: { restoreResult != nil },
                set: { newValue in
                    if !newValue { restoreResult = nil }
                }
            ),
            actions: {
                Button("OK", role: .cancel) { restoreResult = nil }
            },
            message: {
                Text(
                    restoreResult == .entitled
                        ? "Full Catalog Access is now active on this device."
                        : "We didn't find a previous Full Catalog Access purchase for this Apple Account."
                )
            }
        )
    }

    // MARK: - Restore Purchases

    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true

        Task {
            await purchaseManager.restorePurchases()
            isRestoring = false
            restoreResult = purchaseManager.hasFullCatalogAccess ? .entitled : .notFound
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Data & Privacy")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.text)

            Text("Review what Legacy Treasure Chest stores on this iPhone, and permanently delete it if you no longer need it.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.spacing.small)
    }

    // MARK: - Deletion

    /// Runs the reset on the main queue, one tick after `deletionPhase` is
    /// set to `.inProgress` so SwiftUI has a chance to render the progress
    /// state first. Matches the existing generate-then-update pattern used
    /// elsewhere in the app (see `EstateReportsView`) rather than
    /// introducing async/await for a single synchronous operation.
    private func performDeletion() {
        guard deletionPhase != .inProgress else { return }
        deletionPhase = .inProgress

        DispatchQueue.main.async {
            do {
                try AppDataResetCoordinator.resetAllData(modelContext: modelContext)
                deletionPhase = .succeeded
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? "Some Legacy Treasure Chest data could not be deleted. Your remaining data is still stored only on this iPhone. Please try again."
                deletionPhase = .failed(message)
            }
        }
    }
}

// MARK: - Confirmation Sheet

private struct DeleteAllDataConfirmationView: View {
    @Binding var phase: DeletionPhase
    var onConfirm: () -> Void
    var onDismissAfterSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing.large) {

                    explanationSection

                    if case .failed(let message) = phase {
                        Text(message)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.destructive)
                    }

                    if phase == .succeeded {
                        successSection
                    } else {
                        confirmButton
                    }
                }
                .padding(Theme.spacing.xl)
            }
            .navigationTitle("Delete All Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(phase == .inProgress)
                }
            }
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("This will permanently delete:")
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)

            bullet("All inventory, beneficiaries, sets, batches, plans, photos, documents, and audio stored on this iPhone.")
            bullet("All app preferences and settings on this iPhone.")
            bullet("Copies you've already exported to Files, Mail, Messages, AirDrop, or another app cannot be deleted from here.")
            bullet("This action cannot be undone.")
        }
    }

    private var confirmButton: some View {
        Button(role: .destructive) {
            onConfirm()
        } label: {
            HStack {
                if phase == .inProgress {
                    ProgressView()
                        .tint(.white)
                }
                Text(phase == .inProgress ? "Deleting…" : "Delete Everything on This iPhone")
                    .font(Theme.bodyFont.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spacing.medium)
            .background(Theme.destructive)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(phase == .inProgress)
    }

    private var successSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Label(
                "All Legacy Treasure Chest data on this iPhone has been deleted.",
                systemImage: "checkmark.circle.fill"
            )
            .font(Theme.bodyFont.weight(.semibold))
            .foregroundStyle(Theme.text)

            Button("Done") {
                onDismissAfterSuccess()
            }
            .font(Theme.bodyFont.weight(.semibold))
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spacing.medium)
            .background(Theme.text)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing.small) {
            Text("•")
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 12, alignment: .leading)

            Text(text)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        DataPrivacySettingsView(onDataResetCompleted: {})
            .environment(PurchaseManager())
    }
}
