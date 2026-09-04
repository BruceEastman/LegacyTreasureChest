Monetization Rules v1 — decisions to lock
I would record these now:
* Free item allowance: 25 catalog items
* Paid product: one-time non-consumable Household/Unlimited Access purchase
* No subscription
* Existing records are never locked
* Users can always view, edit, enrich, export, and work with existing items
* The gate applies only to creating additional possession records beyond 25
* Sets do not count separately; only their member LTCItem records count
* Beneficiaries do not count
* Batches/lots do not count
* Photos, documents, and audio attached to an existing item do not count
* AI analysis of an existing item remains available
* Liquidation briefs/plans and Local Help for an existing item remain available
* Exports remain available
* Users already above 25 when 1.1 arrives keep everything and can continue using it, but cannot create another item without purchasing
* A one-time explanatory upgrade message appears for those existing above-threshold users
* Batch Add must preflight against remaining capacity before analysis/import
* No partial batch import caused solely by the paywall
* If a free user has room for 3 items and selects 10, tell them they may reduce the selection to 3 or purchase Unlimited Access
* Purchasing removes the item-count restriction permanently for that Apple ID / StoreKit entitlement
* Manual item creation checks capacity before opening the creation workflow
* AI-assisted single-item creation checks capacity before analysis begins
* Batch Add checks capacity before AI analysis begins
* Duplicating an item, if supported now or later, counts as creating a new item
* The 25-item limit is based on current item count, not lifetime items ever created
* Deleting items frees capacity
* A visible Restore Purchases action must be available
* Restore restores entitlement only; it does not restore deleted local inventory data
* Purchased entitlement should also be refreshed automatically when appropriate, but manual Restore remains available
Family Sharing
* Disabled for Full Catalog Access in v1.1.
* LTC is intentionally a single-user, local-first catalog.
* Purchase sharing across family members would imply a shared-data experience that LTC does not provide.
* Reconsider only if LTC later introduces true multi-user/shared-catalog functionality.
Multiple personal devices
* Not part of monetization v1 scope.
* A Full Catalog Access entitlement may be restorable on another device associated with the same Apple Account.
* LTC does not currently promise that catalog data will synchronize between devices.
* Cross-device catalog synchronization is deferred until there is a demonstrated user need.
I would also add one implementation principle:
The UI should never contain hard-coded monetization rules. Views ask a central access-policy service whether the requested action is permitted.