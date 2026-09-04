//
//  PurchaseTestView.swift
//  LegacyTreasureChest
//
//  DEBUG-only StoreKit validation surface for PurchaseManager -- not the
//  production paywall. Exists purely so Full Catalog Access product
//  loading, purchase, restore, and entitlement refresh can be exercised
//  locally against the Xcode StoreKit Configuration before any real
//  paywall or creation gate is built. Follows the same DEBUG-only,
//  Form/Section pattern as DeveloperSettingsView.
//

import SwiftUI
import StoreKit

#if DEBUG
struct PurchaseTestView: View {

    @Environment(PurchaseManager.self) private var purchaseManager

    var body: some View {
        Form {
            Section("Product") {
                LabeledContent("Load State", value: loadStateDescription)

                if let product = purchaseManager.product {
                    LabeledContent("Name", value: product.displayName)
                    LabeledContent("Price", value: product.displayPrice)
                    LabeledContent("Product ID", value: product.id)
                } else {
                    Text("No product loaded.")
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Product") {
                    Task { await purchaseManager.loadProduct() }
                }
            }

            Section("Entitlement") {
                LabeledContent("Full Catalog Access", value: purchaseManager.hasFullCatalogAccess ? "Entitled" : "Not Entitled")

                Button("Refresh Entitlement") {
                    Task { await purchaseManager.refreshEntitlement() }
                }
            }

            Section("Purchase") {
                LabeledContent("State", value: purchaseStateDescription)

                Button("Buy") {
                    Task { await purchaseManager.purchase() }
                }
                .disabled(!purchaseManager.isProductAvailable)

                Button("Restore Purchases") {
                    Task { await purchaseManager.restorePurchases() }
                }
            }

            Section {
                Text("Debug-only StoreKit validation surface. Not the production paywall.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Purchase Test Lab")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var loadStateDescription: String {
        switch purchaseManager.productLoadState {
        case .idle: return "Idle"
        case .loading: return "Loading…"
        case .loaded: return "Loaded"
        case .unavailable(let message): return "Unavailable: \(message)"
        }
    }

    private var purchaseStateDescription: String {
        switch purchaseManager.purchaseState {
        case .idle: return "Idle"
        case .purchasing: return "Purchasing…"
        case .purchased: return "Purchased"
        case .cancelled: return "Cancelled"
        case .pending: return "Pending"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}
#endif
