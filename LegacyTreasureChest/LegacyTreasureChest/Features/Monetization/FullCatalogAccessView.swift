//
//  FullCatalogAccessView.swift
//  LegacyTreasureChest
//
//  Production paywall for the "Full Catalog Access" one-time,
//  non-consumable purchase. Presented from a creation gate (Manual Add,
//  Batch Add) when ItemCreationGate reports Full Catalog Access is
//  required. Audience is older adults -- copy stays calm, plain, and
//  explicitly reassures that nothing already in the catalog is affected.
//
//  Always reads price/name from StoreKit via PurchaseManager.product --
//  never a hard-coded price. Auto-dismisses itself once
//  hasFullCatalogAccess actually becomes true (not merely once
//  purchaseState reports .purchased -- see PurchaseManager.purchase(),
//  which guarantees the former happens no later than the latter). The
//  presenting screen is responsible for letting the user retry their
//  original action (e.g. tapping Add again), which is simpler and more
//  reliable than resuming the original action automatically.
//

import SwiftUI
import StoreKit

struct FullCatalogAccessView: View {
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing.large) {
                    header

                    if let product = purchaseManager.product {
                        purchaseSection(product: product)
                    } else {
                        unavailableSection
                    }

                    if case .failed(let message) = purchaseManager.purchaseState {
                        Text(message)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.destructive)
                    }

                    restoreSection
                }
                .padding(Theme.spacing.xl)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Full Catalog Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .onChange(of: purchaseManager.hasFullCatalogAccess) { _, hasAccess in
                #if DEBUG
                print("🧪 FullCatalogAccessView[DEBUG]: hasFullCatalogAccess changed -> \(hasAccess)")
                #endif
                // Driven by actual entitlement, not purchaseState -- see
                // PurchaseManager.purchase() for why hasFullCatalogAccess
                // is guaranteed to already be true by the time
                // purchaseState becomes .purchased for this transaction.
                if hasAccess {
                    #if DEBUG
                    print("🧪 FullCatalogAccessView[DEBUG]: dismissing paywall (entitled)")
                    #endif
                    dismiss()
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text("Your existing catalog remains fully available.")
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("You've reached the number of items included for free. Upgrade once to continue adding belongings.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("One-time purchase • No subscription")
                .font(Theme.secondaryFont.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private func purchaseSection(product: Product) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Button {
                Task { await purchaseManager.purchase() }
            } label: {
                HStack {
                    if purchaseManager.purchaseState == .purchasing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Unlock Full Catalog Access — \(product.displayPrice)")
                        .font(Theme.bodyFont.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.spacing.medium)
                .background(Theme.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(purchaseManager.purchaseState == .purchasing)

            if purchaseManager.purchaseState == .pending {
                Text("Your purchase is waiting for approval. This screen will update automatically once it's approved.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var unavailableSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.medium) {
            Text("Purchasing is temporarily unavailable. Please try again in a moment.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await purchaseManager.loadProduct() }
            } label: {
                Text("Try Again")
                    .font(Theme.bodyFont.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing.medium)
                    .background(Color(.systemGray6))
                    .foregroundStyle(Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Button {
                Task { await purchaseManager.restorePurchases() }
            } label: {
                Text("Restore Purchases")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.primary)
            }

            Text("Restore Purchases recovers a Full Catalog Access purchase already made with this Apple Account. It does not restore deleted items.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.spacing.small)
    }
}

// MARK: - Preview

#Preview {
    FullCatalogAccessView()
        .environment(PurchaseManager())
}
