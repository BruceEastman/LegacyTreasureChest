//
//  PurchaseManager.swift
//  LegacyTreasureChest
//
//  StoreKit 2 entitlement service for the "Full Catalog Access"
//  non-consumable in-app purchase. Owns StoreKit behavior only: product
//  loading, purchase initiation, transaction verification, and
//  entitlement derivation from Transaction.currentEntitlements /
//  Transaction.updates.
//
//  Deliberately excluded from this type: migration baseline logic,
//  current item counting, ItemCreationPolicy, SwiftData, and paywall
//  presentation. Those are separate responsibilities that live elsewhere
//  in Features/Monetization/ and consume `entitlementState` /
//  `hasFullCatalogAccess` as an input, never reproduce it.
//
//  Entitlement authority: Full Catalog Access is always derived from
//  verified StoreKit state. This type never persists a permanent local
//  "isPaid" Boolean. Entitlement is exposed as a tri-state
//  `entitlementState` (`.resolving` / `.notEntitled` / `.entitled`) --
//  `.resolving` is the honest starting state at launch, distinct from a
//  confirmed `.notEntitled`, so a tap landing before StoreKit has
//  answered is never mistaken for "definitely not entitled." Set directly
//  from a verified, matching transaction the moment purchase() or the
//  Transaction.updates listener sees one (see the comment on
//  refreshEntitlement() for why a separate Transaction.currentEntitlements
//  re-enumeration is deliberately NOT triggered immediately afterward --
//  physical-device testing showed that enumeration can lag a
//  just-verified transaction, which previously caused a fresh `.entitled`
//  to be overwritten with a temporarily-empty `.notEntitled`). Full
//  re-enumeration still happens at launch and on explicit Restore
//  Purchases. `hasFullCatalogAccess` remains as a derived Bool
//  convenience for callers that only care about the entitled/not-entitled
//  distinction.
//

import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class PurchaseManager {

    // MARK: - State

    enum ProductLoadState: Equatable {
        case idle
        case loading
        case loaded
        case unavailable(String)
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case cancelled
        case pending
        case failed(String)
    }

    /// Tri-state entitlement resolution. `.resolving` is the honest
    /// initial state -- it means "StoreKit hasn't answered yet," which is
    /// distinct from `.notEntitled` ("StoreKit answered: no"). Nothing in
    /// this app should treat `.resolving` as a confirmed "not entitled."
    enum EntitlementState: Equatable {
        case resolving
        case notEntitled
        case entitled
    }

    private(set) var productLoadState: ProductLoadState = .idle
    private(set) var purchaseState: PurchaseState = .idle

    /// The loaded Full Catalog Access product, once available. Exposes
    /// StoreKit's own localized metadata (`displayName`, `displayPrice`,
    /// `description`) directly -- nothing here duplicates or hard-codes
    /// pricing; the eventual paywall reads `product?.displayPrice`.
    private(set) var product: Product?

    /// Full entitlement resolution state, including the "still resolving"
    /// case. Never backed by a persisted Boolean -- StoreKit remains
    /// authoritative. This is the source of truth; `hasFullCatalogAccess`
    /// below is a derived convenience.
    private(set) var entitlementState: EntitlementState = .resolving

    /// Convenience derived from `entitlementState`. `false` here means
    /// either "confirmed not entitled" *or* "still resolving" -- callers
    /// that must not treat those two as the same thing (creation gates)
    /// should read `entitlementState` directly instead.
    var hasFullCatalogAccess: Bool { entitlementState == .entitled }

    var isProductAvailable: Bool { product != nil }

    // MARK: - Init

    // Not cancelled in a `deinit`: PurchaseManager is constructed exactly
    // once at app scope (see LegacyTreasureChestApp) and lives for the
    // life of the process, so there is no meaningful point at which this
    // listener needs to be torn down early.
    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        // Long-lived listener for transaction changes that happen outside
        // an explicit purchase() call on this device -- Ask to Buy
        // approvals, renewals (n/a for this non-consumable, kept generic),
        // and cross-device restores delivered while the app is running.
        transactionUpdatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }

        // Product loading and the initial entitlement refresh are
        // independent of each other -- run them as separate, concurrent
        // Tasks (not one sequential Task) so entitlementState resolves as
        // soon as StoreKit answers, rather than waiting on product
        // catalog loading first. Both remain async and best-effort: a
        // slow or unavailable App Store never blocks app launch, since
        // nothing here is awaited by the caller.
        Task { [weak self] in
            await self?.loadProduct()
        }
        Task { [weak self] in
            await self?.refreshEntitlement()
        }
    }

    /// Suspends until `entitlementState` resolves away from `.resolving`
    /// (or returns immediately if it already has). Used by
    /// `ItemCreationGate` so a tap landing in the brief startup
    /// resolution window waits for the real answer instead of acting on
    /// a false "not entitled." Bounded and simple by design -- a short
    /// poll, not a new async architecture: `entitlementState` normally
    /// resolves within a fraction of a second, so in the overwhelming
    /// majority of calls this returns almost immediately.
    func waitForEntitlementResolution() async {
        guard entitlementState == .resolving else { return }

        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if entitlementState != .resolving { return }
        }

        #if DEBUG
        print("🧪 PurchaseManager[DEBUG]: waitForEntitlementResolution() timed out still resolving")
        #endif
    }

    // MARK: - Product Loading

    /// Loads the Full Catalog Access product from StoreKit. Safe to call
    /// repeatedly (e.g. a "Refresh" action) -- never throws or crashes if
    /// StoreKit or the product is temporarily unavailable; callers read
    /// `productLoadState` for the outcome.
    func loadProduct() async {
        guard productLoadState != .loading else { return }
        productLoadState = .loading

        do {
            let products = try await Product.products(for: [AppConstants.Monetization.fullCatalogAccessProductID])
            guard let loaded = products.first else {
                product = nil
                productLoadState = .unavailable("Full Catalog Access isn't available right now.")
                print("⚠️ PurchaseManager: no product returned for id \(AppConstants.Monetization.fullCatalogAccessProductID)")
                return
            }
            product = loaded
            productLoadState = .loaded
            print("✅ PurchaseManager: loaded product \(loaded.id) — \(loaded.displayName) — \(loaded.displayPrice)")
        } catch {
            product = nil
            productLoadState = .unavailable("Couldn't reach the App Store right now.")
            print("❌ PurchaseManager: product load failed: \(error)")
        }
    }

    // MARK: - Purchase

    /// Initiates the Full Catalog Access purchase. Updates `purchaseState`
    /// to reflect every StoreKit outcome (verified success, cancellation,
    /// pending, unverified, or failure).
    ///
    /// `purchaseState == .purchased` is guaranteed to never be observable
    /// while `hasFullCatalogAccess == false` for this transaction: a
    /// verified, matching, non-revoked transaction is itself sufficient
    /// authoritative evidence of entitlement, so `hasFullCatalogAccess` is
    /// established directly from it -- deliberately without an
    /// intervening `Transaction.currentEntitlements` re-enumeration (see
    /// `refreshEntitlement()`'s doc comment for why that would risk
    /// overwriting this fresh `true` with a stale `false`) -- strictly
    /// before `purchaseState` is ever set to `.purchased`.
    func purchase() async {
        guard let product else {
            #if DEBUG
            print("🧪 PurchaseManager[DEBUG]: purchase() called with no loaded product -- aborting")
            #endif
            return
        }

        #if DEBUG
        print("🧪 PurchaseManager[DEBUG]: purchase() entered for product \(product.id)")
        #endif

        purchaseState = .purchasing

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    #if DEBUG
                    print("🧪 PurchaseManager[DEBUG]: verified success -- transaction productID=\(transaction.productID), revocationDate=\(transaction.revocationDate.map(String.init(describing:)) ?? "nil")")
                    #endif

                    if transaction.productID == AppConstants.Monetization.fullCatalogAccessProductID,
                       transaction.revocationDate == nil {
                        entitlementState = .entitled
                        #if DEBUG
                        print("🧪 PurchaseManager[DEBUG]: entitlementState = .entitled, set directly from verified transaction")
                        #endif
                    }

                    await transaction.finish()
                    #if DEBUG
                    print("🧪 PurchaseManager[DEBUG]: transaction.finish() completed (no immediate currentEntitlements refresh)")
                    #endif

                    // Deliberately no refreshEntitlement() call here -- see
                    // that function's doc comment. The verified transaction
                    // in hand is already sufficient; re-enumerating
                    // Transaction.currentEntitlements immediately after a
                    // purchase was observed, on a physical device, to
                    // sometimes not yet reflect it, which overwrote the
                    // correct `.entitled` state set above with `.notEntitled`.

                    // Set last, strictly after entitlementState above.
                    purchaseState = .purchased
                    #if DEBUG
                    print("🧪 PurchaseManager[DEBUG]: purchaseState = .purchased (entitlementState = \(entitlementState))")
                    #endif
                case .unverified(let unverifiedTransaction, let verificationError):
                    #if DEBUG
                    print("🧪 PurchaseManager[DEBUG]: unverified -- productID=\(unverifiedTransaction.productID), error=\(verificationError)")
                    #endif
                    // Never grant entitlement from a transaction StoreKit
                    // could not cryptographically verify.
                    purchaseState = .failed("Purchase could not be verified.")
                }
            case .userCancelled:
                purchaseState = .cancelled
                print("ℹ️ PurchaseManager: purchase cancelled by user")
            case .pending:
                // e.g. Ask to Buy. No entitlement yet -- resolved later
                // via the Transaction.updates listener when approved.
                purchaseState = .pending
                print("ℹ️ PurchaseManager: purchase pending (e.g. Ask to Buy)")
            @unknown default:
                #if DEBUG
                print("🧪 PurchaseManager[DEBUG]: purchase() hit @unknown default PurchaseResult case")
                #endif
                purchaseState = .failed("Unexpected purchase result.")
            }
        } catch {
            #if DEBUG
            logPurchaseError(error, productID: product.id)
            #endif
            purchaseState = .failed(userFacingMessage(for: error))
            print("❌ PurchaseManager: purchase threw: \(error)")
        }
    }

    /// Maps an error thrown by `product.purchase()` to a safe, plain-language
    /// message. Only narrowly-understood, unambiguous StoreKit cases get a
    /// distinct message -- everything else (including `StoreKitError`'s
    /// generic/system cases and any error type not recognized here) falls
    /// back to the original generic message rather than guessing at a cause.
    private func userFacingMessage(for error: Error) -> String {
        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .notAvailableInStorefront:
                return "This purchase isn't currently available for this App Store region."
            case .networkError:
                return "The App Store couldn't be reached. Please check your connection and try again."
            default:
                return "Purchase failed. Please try again."
            }
        }

        if let purchaseError = error as? Product.PurchaseError, purchaseError == .purchaseNotAllowed {
            return "Purchases aren't allowed on this device."
        }

        return "Purchase failed. Please try again."
    }

    #if DEBUG
    /// Diagnostic-only logging for an error thrown by `product.purchase()`.
    /// Logs only the product id and the error's own type/description/domain/
    /// code (plus the specific StoreKit case, where recognized) -- never
    /// receipts, signed transaction data, Apple ID/account information,
    /// tokens, device identifiers, or payment information.
    private func logPurchaseError(_ error: Error, productID: String) {
        let nsError = error as NSError
        print("🧪 PurchaseManager[DEBUG]: purchase() threw for product \(productID)")
        print("🧪 PurchaseManager[DEBUG]: error type=\(type(of: error)), localizedDescription=\(error.localizedDescription)")
        print("🧪 PurchaseManager[DEBUG]: NSError domain=\(nsError.domain), code=\(nsError.code)")

        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .unknown:
                print("🧪 PurchaseManager[DEBUG]: StoreKitError case = unknown")
            case .userCancelled:
                print("🧪 PurchaseManager[DEBUG]: StoreKitError case = userCancelled")
            case .networkError(let urlError):
                let nested = urlError as NSError
                print("🧪 PurchaseManager[DEBUG]: StoreKitError case = networkError, nested type=\(type(of: urlError)), domain=\(nested.domain), code=\(nested.code)")
            case .systemError(let underlying):
                let nested = underlying as NSError
                print("🧪 PurchaseManager[DEBUG]: StoreKitError case = systemError, nested type=\(type(of: underlying)), domain=\(nested.domain), code=\(nested.code)")
            case .notAvailableInStorefront:
                print("🧪 PurchaseManager[DEBUG]: StoreKitError case = notAvailableInStorefront")
            case .notEntitled:
                print("🧪 PurchaseManager[DEBUG]: StoreKitError case = notEntitled")
            case .unsupported:
                print("🧪 PurchaseManager[DEBUG]: StoreKitError case = unsupported")
            @unknown default:
                print("🧪 PurchaseManager[DEBUG]: StoreKitError case = @unknown default")
            }
            return
        }

        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .invalidQuantity:
                print("🧪 PurchaseManager[DEBUG]: Product.PurchaseError case = invalidQuantity")
            case .productUnavailable:
                print("🧪 PurchaseManager[DEBUG]: Product.PurchaseError case = productUnavailable")
            case .purchaseNotAllowed:
                print("🧪 PurchaseManager[DEBUG]: Product.PurchaseError case = purchaseNotAllowed")
            case .ineligibleForOffer:
                print("🧪 PurchaseManager[DEBUG]: Product.PurchaseError case = ineligibleForOffer")
            case .invalidOfferIdentifier:
                print("🧪 PurchaseManager[DEBUG]: Product.PurchaseError case = invalidOfferIdentifier")
            case .invalidOfferPrice:
                print("🧪 PurchaseManager[DEBUG]: Product.PurchaseError case = invalidOfferPrice")
            case .invalidOfferSignature:
                print("🧪 PurchaseManager[DEBUG]: Product.PurchaseError case = invalidOfferSignature")
            case .missingOfferParameters:
                print("🧪 PurchaseManager[DEBUG]: Product.PurchaseError case = missingOfferParameters")
            case .paymentMethodBindingConfigurationRequired:
                print("🧪 PurchaseManager[DEBUG]: Product.PurchaseError case = paymentMethodBindingConfigurationRequired")
            @unknown default:
                print("🧪 PurchaseManager[DEBUG]: Product.PurchaseError case = @unknown default")
            }
        }
    }
    #endif

    // MARK: - Restore

    /// Explicit "Restore Purchases" entry point. Asks StoreKit to
    /// re-sync with the App Store, then re-derives entitlement from
    /// verified current entitlements. `AppStore.sync()` failing (offline,
    /// a dismissed sign-in prompt) is not itself an entitlement error --
    /// this still falls through and re-checks whatever StoreKit already
    /// knows locally.
    ///
    /// Passes `entitlementState` through `.resolving` while the sync/
    /// refresh is in flight -- a genuine re-check is happening, so
    /// callers (e.g. the creation gate) should treat this the same as
    /// any other resolution window, not as a false "not entitled."
    func restorePurchases() async {
        entitlementState = .resolving

        do {
            try await AppStore.sync()
        } catch {
            // Intentionally not surfaced as a purchaseState failure --
            // see comment above.
        }
        await refreshEntitlement()
    }

    // MARK: - Entitlement

    /// Incremented at the start of every `refreshEntitlement()` call.
    /// `restorePurchases()` and launch both trigger a refresh, and their
    /// underlying `Transaction.currentEntitlements` enumerations (each an
    /// async, XPC-backed round trip whose duration is not guaranteed) are
    /// not guaranteed to complete in the order they started -- e.g. a
    /// slow startup refresh finishing after a user-triggered Restore
    /// Purchases refresh could otherwise overwrite its result. Without
    /// this guard, an older refresh that happens to finish last could
    /// silently overwrite a newer, correct result with stale data. Kept
    /// even though `purchase()` and the `Transaction.updates` handler no
    /// longer call `refreshEntitlement()` (see below) -- it's still real
    /// protection for the callers that remain.
    private var entitlementRefreshGeneration = 0

    /// Re-derives `hasFullCatalogAccess` from a full
    /// `Transaction.currentEntitlements` enumeration. StoreKit already
    /// excludes revoked/refunded/expired transactions from that
    /// sequence, and the `revocationDate == nil` check below is a
    /// defensive second guard -- this never treats the historical
    /// existence of a purchase as permanent access on its own.
    ///
    /// Only ever sets `false` after completing the full enumeration and
    /// finding no valid matching transaction -- never as a side effect of
    /// being superseded by a newer call (see the generation guard above).
    ///
    /// Used for launch and explicit Restore Purchases only -- deliberately
    /// **not** called immediately after `purchase()` sees a verified
    /// transaction, nor from the `Transaction.updates` handler for one.
    /// Physical-device testing showed `Transaction.currentEntitlements`
    /// can briefly lag a transaction that was *just* verified/finished in
    /// this same process: calling this function right after would
    /// sometimes enumerate a snapshot that didn't include it yet and
    /// overwrite the correct, freshly-set `true` with `false`. A directly
    /// verified (and, for updates, non-revoked) matching transaction is
    /// itself sufficient authoritative evidence, so those two call sites
    /// set `hasFullCatalogAccess` straight from the transaction in hand
    /// instead of re-deriving it here.
    func refreshEntitlement() async {
        entitlementRefreshGeneration += 1
        let generation = entitlementRefreshGeneration

        #if DEBUG
        print("🧪 PurchaseManager[DEBUG]: refreshEntitlement() starting generation \(generation)")
        #endif

        var entitled = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == AppConstants.Monetization.fullCatalogAccessProductID else { continue }
            guard transaction.revocationDate == nil else { continue }
            entitled = true
            #if DEBUG
            print("🧪 PurchaseManager[DEBUG]: refreshEntitlement() generation \(generation) found matching verified entitlement (productID=\(transaction.productID))")
            #endif
        }

        // A newer refresh started (and, in this generation scheme, may
        // already have completed) while this enumeration was in flight --
        // discard this now-stale result rather than risk overwriting a
        // more current one.
        guard generation == entitlementRefreshGeneration else {
            print("ℹ️ PurchaseManager: discarding stale entitlement refresh (generation \(generation), current \(entitlementRefreshGeneration))")
            return
        }

        entitlementState = entitled ? .entitled : .notEntitled
        print("ℹ️ PurchaseManager: entitlement refreshed — entitlementState = \(entitlementState)")
    }

    // MARK: - Transaction Updates

    /// Handles a transaction delivered outside an explicit `purchase()`
    /// call (Ask to Buy approvals, cross-device/App-Store-driven changes,
    /// and revocations). A verified, matching transaction is itself
    /// sufficient evidence to set `hasFullCatalogAccess` directly --
    /// `true` for a non-revoked transaction, `false` for a revoked one
    /// (safe because LTC has exactly one entitlement product; a verified
    /// revocation of *that* transaction unambiguously means "not
    /// entitled," nothing else to check). No `refreshEntitlement()` call
    /// here either, for the same reason as in `purchase()` -- see that
    /// function's doc comment.
    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            #if DEBUG
            print("🧪 PurchaseManager[DEBUG]: Transaction.updates delivered an unverified update -- ignored")
            #endif
            // An unverified update is never applied to entitlement state.
            return
        }

        guard transaction.productID == AppConstants.Monetization.fullCatalogAccessProductID else {
            await transaction.finish()
            return
        }

        if transaction.revocationDate == nil {
            entitlementState = .entitled
            #if DEBUG
            print("🧪 PurchaseManager[DEBUG]: Transaction.updates verified matching transaction -- entitlementState = .entitled, set directly")
            #endif
        } else {
            entitlementState = .notEntitled
            #if DEBUG
            print("🧪 PurchaseManager[DEBUG]: Transaction.updates verified matching transaction is revoked -- entitlementState = .notEntitled, set directly")
            #endif
        }

        await transaction.finish()
        #if DEBUG
        print("🧪 PurchaseManager[DEBUG]: Transaction.updates transaction.finish() completed (no immediate currentEntitlements refresh)")
        #endif
    }
}
