//
//  LiquidationAIService.swift
//  LegacyTreasureChest
//
//  Liquidate brief generation.
//  v1: Local heuristic generator (photo-optional).
//  Backend is NOT used in v1.
//

import Foundation

enum LiquidationAIError: Error {
    case missingBackend
}

// MARK: - Service

struct LiquidationAIService {

    private let local = LocalLiquidationBriefGenerator()

    init() {}

    /// Generate a liquidation brief for an item (photo-optional).
    /// - Parameter imageData: Optional JPEG data. Pass nil for text-only.
    func generateBriefDTO(
        for item: LTCItem,
        goal: LiquidationGoalDTO = .balanced,
        constraints: LiquidationConstraintsDTO? = nil,
        locationHint: String? = nil,
        imageData: Data? = nil
    ) async throws -> LiquidationBriefDTO {

        let req = LiquidationRequestBuilder.buildRequest(
            for: item,
            goal: goal,
            constraints: constraints,
            locationHint: locationHint,
            imageData: imageData
        )

        return local.generate(from: req)
    }

    /// Generate a liquidation brief for a set (text-only v1).
    func generateBriefDTO(
        for set: LTCSet,
        goal: LiquidationGoalDTO = .balanced,
        constraints: LiquidationConstraintsDTO? = nil,
        locationHint: String? = nil
    ) async throws -> LiquidationBriefDTO {

        let req = LiquidationRequestBuilder.buildRequest(
            for: set,
            goal: goal,
            constraints: constraints,
            locationHint: locationHint
        )

        return local.generate(from: req)
    }
}

// MARK: - Request Builder

enum LiquidationRequestBuilder {

    static func buildRequest(
        for item: LTCItem,
        goal: LiquidationGoalDTO,
        constraints: LiquidationConstraintsDTO?,
        locationHint: String?,
        imageData: Data?
    ) -> LiquidationBriefRequest {

        let valuation = item.valuation
        let photoBase64: String? = imageData?.base64EncodedString()

        return LiquidationBriefRequest(
            schemaVersion: 1,
            scope: .item,
            title: item.name,
            description: item.itemDescription,
            category: item.category,
            quantity: item.quantity,
            unitValue: item.value,
            currencyCode: valuation?.currencyCode ?? "USD",
            valuationLow: valuation?.valueLow,
            valuationLikely: valuation?.estimatedValue,
            valuationHigh: valuation?.valueHigh,
            photoJpegBase64: photoBase64,
            setContext: item.set.map { set in
                LiquidationSetContext(
                    setName: set.name,
                    setType: set.setTypeRaw,
                    story: set.story,
                    sellTogetherPreference: set.sellTogetherPreferenceRaw,
                    completeness: set.completenessRaw,
                    memberSummaries: set.items.map {
                        LiquidationMemberSummary(
                            title: $0.name,
                            category: $0.category,
                            quantity: $0.quantity,
                            unitValue: $0.value
                        )
                    }
                )
            },
            inputs: LiquidationInputsDTO(goal: goal, constraints: constraints, locationHint: locationHint)
        )
    }

    static func buildRequest(
        for set: LTCSet,
        goal: LiquidationGoalDTO,
        constraints: LiquidationConstraintsDTO?,
        locationHint: String?
    ) -> LiquidationBriefRequest {

        return LiquidationBriefRequest(
            schemaVersion: 1,
            scope: .set,
            title: set.name,
            description: set.story ?? set.notes,
            category: set.setTypeRaw,
            quantity: set.items.count,
            unitValue: nil,
            currencyCode: "USD",
            valuationLow: nil,
            valuationLikely: nil,
            valuationHigh: nil,
            photoJpegBase64: nil,
            setContext: LiquidationSetContext(
                setName: set.name,
                setType: set.setTypeRaw,
                story: set.story,
                sellTogetherPreference: set.sellTogetherPreferenceRaw,
                completeness: set.completenessRaw,
                memberSummaries: set.items.map {
                    LiquidationMemberSummary(
                        title: $0.name,
                        category: $0.category,
                        quantity: $0.quantity,
                        unitValue: $0.value
                    )
                }
            ),
            inputs: LiquidationInputsDTO(goal: goal, constraints: constraints, locationHint: locationHint)
        )
    }
}

// MARK: - Local Heuristic Generator (v2: item-specific)

struct LocalLiquidationBriefGenerator {

    func generate(from req: LiquidationBriefRequest) -> LiquidationBriefDTO {

        // Normalize optionals.
        let currency = (req.currencyCode ?? "USD").trimmingCharacters(in: .whitespacesAndNewlines)

        let title = (req.title ?? "Untitled Item")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let categoryRaw = (req.category ?? "Uncategorized")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let category = categoryRaw.isEmpty ? "Uncategorized" : categoryRaw
        let description = (req.description ?? "")
        let qty = max(1, req.quantity ?? 1)

        let inputs = req.inputs ?? LiquidationInputsDTO(goal: .balanced, constraints: nil, locationHint: nil)
        let goal = inputs.goal ?? .balanced
        let locationHint = inputs.locationHint

        // Valuation math
        let likelyUnit = req.valuationLikely ?? req.unitValue ?? 0
        let likelyTotal = max(0, likelyUnit) * Double(qty)

        // If low/high missing, create conservative bounds around likely.
        let lowTotal = req.valuationLow ?? (likelyTotal * 0.75)
        let highTotal = req.valuationHigh ?? (likelyTotal * 1.25)

        // Category profile
        let profile = classifyCategory(category, description: description)

        // Bulky / shipping risk / local-only leaning
        let bulky = profile.isBulky || looksBulkyFromText(description) || qty >= profile.bulkyQtyThreshold
        let shipRisk = bulky || profile.shippingRiskHigh
        let localFriendly = profile.localFriendly || bulky

        // Set context effects
        let setCtx = req.setContext
        let inSet = (setCtx != nil)
        let setPreference = (setCtx?.sellTogetherPreference ?? "").lowercased()
        let setCompleteness = (setCtx?.completeness ?? "").lowercased()
        let keepTogetherStrong = inSet && (setPreference.contains("togetheronly") || setPreference.contains("togetherpreferred"))
        let setIncomplete = inSet && setCompleteness.contains("partial")

        // Value tiers (for strategy changes)
        let tier = valueTier(likelyTotal: likelyTotal, profile: profile)

        // Donation / bundle heuristics
        let constraints = inputs.constraints
        let localPickupOnly = constraints?.localPickupOnly ?? false
        let canShip = constraints?.canShip ?? true

        let donateLikely = isDonateLikely(
            likelyTotal: likelyTotal,
            tier: tier,
            profile: profile,
            qty: qty,
            description: description
        )

        // Recommended path logic (goal-aware)
        let recommendedPath = chooseRecommendedPath(
            goal: goal,
            donateLikely: donateLikely,
            tier: tier,
            shipRisk: shipRisk,
            localFriendly: localFriendly,
            localPickupOnly: localPickupOnly,
            canShip: canShip,
            keepTogetherStrong: keepTogetherStrong,
            setIncomplete: setIncomplete
        )

        let reasoning = buildReasoning(
            title: title,
            category: category,
            qty: qty,
            likelyTotal: likelyTotal,
            lowTotal: lowTotal,
            highTotal: highTotal,
            goal: goal,
            tier: tier,
            profile: profile,
            shipRisk: shipRisk,
            localFriendly: localFriendly,
            inSet: inSet,
            keepTogetherStrong: keepTogetherStrong,
            setIncomplete: setIncomplete,
            locationHint: locationHint
        )

        let pathOptions = buildPathOptions(
            currency: currency,
            lowTotal: lowTotal,
            likelyTotal: likelyTotal,
            highTotal: highTotal,
            profile: profile,
            shipRisk: shipRisk,
            tier: tier,
            qty: qty,
            inSet: inSet,
            keepTogetherStrong: keepTogetherStrong
        )

        let steps = buildActionSteps(
            title: title,
            category: category,
            description: description,
            qty: qty,
            recommended: recommendedPath,
            profile: profile,
            shipRisk: shipRisk,
            tier: tier,
            inSet: inSet,
            keepTogetherStrong: keepTogetherStrong
        )

        let missing = buildMissingDetails(
            category: category,
            scope: req.scope,
            profile: profile,
            shipRisk: shipRisk,
            inSet: inSet
        )

        let assumptions = buildAssumptions(
            shipRisk: shipRisk,
            scope: req.scope,
            inSet: inSet,
            keepTogetherStrong: keepTogetherStrong
        )

        return LiquidationBriefDTO(
            schemaVersion: req.schemaVersion ?? 1,
            scope: req.scope,
            generatedAt: .now,
            aiProvider: "local",
            aiModel: "heuristic-v2",
            recommendedPath: recommendedPath,
            reasoning: reasoning,
            pathOptions: pathOptions,
            actionSteps: steps,
            missingDetails: missing,
            assumptions: assumptions,
            confidence: confidenceEstimate(tier: tier, profile: profile, inSet: inSet),
            inputs: inputs
        )
    }

    // MARK: - Category classification

    private struct CategoryProfile {
        let kind: String
        let localFriendly: Bool
        let shippingRiskHigh: Bool
        let isBulky: Bool
        let bulkyQtyThreshold: Int
        let notes: String
    }

    private enum ValueTier {
        case micro      // < $50
        case low        // $50–$200
        case mid        // $200–$1000
        case high       // $1000–$5000
        case ultra      // > $5000
    }

    private func classifyCategory(_ category: String, description: String) -> CategoryProfile {
        let c = category.lowercased()
        let d = description.lowercased()

        // Jewelry / luxury personal items
        if c.contains("jewelry") || c.contains("luxury personal") || d.contains("14k") || d.contains("18k") || d.contains("diamond") {
            return .init(
                kind: "jewelry",
                localFriendly: false,
                shippingRiskHigh: false,
                isBulky: false,
                bulkyQtyThreshold: 50,
                notes: "Small, ship-friendly; value depends on materials and details."
            )
        }

        // Rugs
        if c.contains("rug") || d.contains("kpsi") || d.contains("hand-knotted") {
            return .init(
                kind: "rug",
                localFriendly: true,
                shippingRiskHigh: true,
                isBulky: true,
                bulkyQtyThreshold: 2,
                notes: "Bulky and shipping-heavy; local pickup or specialty channels often best."
            )
        }

        // Furniture / appliances
        if c.contains("furniture") || c.contains("appliance") || d.contains("dresser") || d.contains("sofa") || d.contains("table") {
            return .init(
                kind: "bulky",
                localFriendly: true,
                shippingRiskHigh: true,
                isBulky: true,
                bulkyQtyThreshold: 2,
                notes: "Bulky item; local pickup / estate sale style channels tend to win."
            )
        }

        // Electronics
        if c.contains("electronics") || c.contains("computer") || d.contains("serial") || d.contains("model") {
            return .init(
                kind: "electronics",
                localFriendly: true,
                shippingRiskHigh: false,
                isBulky: false,
                bulkyQtyThreshold: 20,
                notes: "Often liquid online or locally; model/condition critical."
            )
        }

        // Art / collectibles
        if c.contains("art") || c.contains("collectible") || d.contains("signed") || d.contains("limited edition") {
            return .init(
                kind: "collectible",
                localFriendly: false,
                shippingRiskHigh: false,
                isBulky: false,
                bulkyQtyThreshold: 20,
                notes: "Value depends on maker/provenance; best channel depends on niche."
            )
        }

        // China & crystal
        if c.contains("china") || c.contains("crystal") || c.contains("stemware") || d.contains("waterford") {
            return .init(
                kind: "fragileSet",
                localFriendly: true,
                shippingRiskHigh: true,
                isBulky: false,
                bulkyQtyThreshold: 24,
                notes: "Fragile; sets matter; shipping is risky and time-consuming."
            )
        }

        // Default
        return .init(
            kind: "general",
            localFriendly: true,
            shippingRiskHigh: false,
            isBulky: false,
            bulkyQtyThreshold: 25,
            notes: "General household item."
        )
    }

    private func valueTier(likelyTotal: Double, profile: CategoryProfile) -> ValueTier {
        // Slight bump for jewelry because small/high-value tends to warrant effort.
        let adjusted = (profile.kind == "jewelry") ? (likelyTotal * 1.05) : likelyTotal

        if adjusted < 50 { return .micro }
        if adjusted < 200 { return .low }
        if adjusted < 1_000 { return .mid }
        if adjusted < 5_000 { return .high }
        return .ultra
    }

    // MARK: - Recommendation logic

    private func isDonateLikely(
        likelyTotal: Double,
        tier: ValueTier,
        profile: CategoryProfile,
        qty: Int,
        description: String
    ) -> Bool {
        if tier == .micro { return true }

        // Low-value + hard-to-sell categories
        if tier == .low && (profile.kind == "general") {
            let c = description.lowercased()
            if c.contains("used") && c.contains("worn") { return true }
        }

        // Clothing / books / misc markers
        let d = description.lowercased()
        let hard = d.contains("fast fashion") || d.contains("old dvd") || d.contains("vhs") || d.contains("magazine")
        if hard && likelyTotal < 100 { return true }

        // Big quantity of low-ish value “lots” often best as donate/bundle
        if qty >= 10 && likelyTotal < 200 && profile.kind == "general" {
            return true
        }

        return false
    }

    private func chooseRecommendedPath(
        goal: LiquidationGoalDTO,
        donateLikely: Bool,
        tier: ValueTier,
        shipRisk: Bool,
        localFriendly: Bool,
        localPickupOnly: Bool,
        canShip: Bool,
        keepTogetherStrong: Bool,
        setIncomplete: Bool
    ) -> LiquidationPathDTO {
        if donateLikely { return .donate }
        if setIncomplete && keepTogetherStrong { return .needsInfo }

        // Constraints override a lot.
        if localPickupOnly { return .pathC_quickExit }
        if !canShip && shipRisk { return .pathC_quickExit }

        switch goal {
        case .minimizeEffort:
            return .pathB_delegateConsign

        case .fastestExit:
            return .pathC_quickExit

        case .maximizeValue:
            // High value: effort usually worth it unless shipping is a nightmare.
            if tier == .high || tier == .ultra { return shipRisk ? .pathB_delegateConsign : .pathA_maximizePrice }
            return localFriendly ? .pathC_quickExit : .pathA_maximizePrice

        case .balanced:
            // Bulky or local-friendly: quick exit tends to be best.
            if shipRisk || localFriendly { return .pathC_quickExit }
            // Mid+ value: maximize tends to win if not bulky.
            if tier == .mid || tier == .high || tier == .ultra { return .pathA_maximizePrice }
            return .pathC_quickExit
        }
    }

    // MARK: - Reasoning

    private func buildReasoning(
        title: String,
        category: String,
        qty: Int,
        likelyTotal: Double,
        lowTotal: Double,
        highTotal: Double,
        goal: LiquidationGoalDTO,
        tier: ValueTier,
        profile: CategoryProfile,
        shipRisk: Bool,
        localFriendly: Bool,
        inSet: Bool,
        keepTogetherStrong: Bool,
        setIncomplete: Bool,
        locationHint: String?
    ) -> String {
        let whereText = locationHint.map { " in \($0)" } ?? ""
        let goalText: String = {
            switch goal {
            case .maximizeValue: return "maximize value"
            case .minimizeEffort: return "minimize effort"
            case .balanced: return "balance value and effort"
            case .fastestExit: return "exit quickly"
            }
        }()

        let tierText: String = {
            switch tier {
            case .micro: return "very low value"
            case .low: return "lower value"
            case .mid: return "mid value"
            case .high: return "high value"
            case .ultra: return "very high value"
            }
        }()

        var parts: [String] = []
        parts.append("“\(title)” (\(category)) — qty \(qty). Based on current inputs, likely total value is ~\(formatMoney(likelyTotal)) (range \(formatMoney(lowTotal))–\(formatMoney(highTotal))).")
        parts.append("Given your goal to \(goalText), this recommendation considers net proceeds vs time/fees/risks\(whereText).")

        if inSet {
            if keepTogetherStrong {
                parts.append("This item is part of a set where selling together is preferred; that can improve sale appeal and net proceeds.")
            } else {
                parts.append("This item is part of a set; consider whether selling together or parting out is better for your situation.")
            }
            if setIncomplete {
                parts.append("Set completeness appears partial/unknown — adding piece counts and condition notes can materially change the recommendation.")
            }
        }

        if profile.kind == "jewelry" {
            parts.append("Jewelry is typically ship-friendly; value accuracy depends heavily on metal purity, gemstone details, and maker/marks.")
        } else if shipRisk {
            parts.append("This item is likely high-friction to ship (bulky or fragile), so local channels often outperform after factoring shipping/returns.")
        } else if localFriendly {
            parts.append("Local demand is commonly strong for this category; speed and simplicity can produce solid net proceeds.")
        } else {
            parts.append("Channel selection matters most here; better listings and comps tend to increase net proceeds.")
        }

        parts.append("Category profile: \(tierText) • \(profile.notes)")
        return parts.joined(separator: " ")
    }

    // MARK: - Path options (net proceeds differ by category, tier, shipping risk)

    private func buildPathOptions(
        currency: String,
        lowTotal: Double,
        likelyTotal: Double,
        highTotal: Double,
        profile: CategoryProfile,
        shipRisk: Bool,
        tier: ValueTier,
        qty: Int,
        inSet: Bool,
        keepTogetherStrong: Bool
    ) -> [LiquidationPathOptionDTO] {

        // Base fee/friction estimates by path
        // A: marketplace fees + shipping/returns (variable)
        // B: consignment/dealer commission (higher)
        // C: local price concession (lower but fast)
        func clamp(_ x: Double) -> Double { max(0, x) }

        let aFee: Double = (profile.kind == "jewelry" || tier == .high || tier == .ultra) ? 0.20 : 0.25
        let aShipPenalty: Double = shipRisk ? 0.08 : 0.02
        let a = (1.0 - aFee - aShipPenalty)

        let b = 0.62 // consignment/auction typical net
        let c = shipRisk ? 0.70 : 0.75

        // Set bonus: if strongly keep together, quick/local can improve
        let setBonus: Double = (inSet && keepTogetherStrong) ? 0.03 : 0.0

        let aLow = clamp(lowTotal * a)
        let aLikely = clamp(likelyTotal * a)
        let aHigh = clamp(highTotal * (a + 0.02))

        let bLow = clamp(lowTotal * b)
        let bLikely = clamp(likelyTotal * b)
        let bHigh = clamp(highTotal * (b + 0.03))

        let cLow = clamp(lowTotal * (c + setBonus))
        let cLikely = clamp(likelyTotal * (c + setBonus))
        let cHigh = clamp(highTotal * (c + setBonus + 0.02))

        let timeA = (tier == .high || tier == .ultra) ? "1–6 weeks" : "1–4 weeks"
        let timeB = "2–12 weeks"
        let timeC = shipRisk ? "1–10 days" : "1–7 days"

        let risksA: [String] = shipRisk
        ? ["Shipping damage", "Returns", "Buyer disputes", "High packing effort"]
        : ["Returns", "Buyer disputes"]

        let risksB: [String] = ["High commission", "Less pricing control", "Payout delays"]
        let risksC: [String] = ["No-shows", "Lowball offers", "Scheduling friction"]

        let logisticsA = shipRisk
        ? "Best if you can tolerate packing/shipping or use freight / local pickup listing."
        : "Best for items where better comps, photos, and copy can lift the outcome."

        let logisticsB = (profile.kind == "jewelry")
        ? "Consider reputable jewelry consignors / dealers; verify terms and insurance."
        : "Best if your time/energy is the scarce resource."

        let logisticsC = shipRisk
        ? "Best for bulky/fragile items where local pickup avoids shipping risk."
        : "Best for fast turnaround with fewer platform steps."

        return [
            LiquidationPathOptionDTO(
                path: .pathA_maximizePrice,
                label: "Path A — Maximize Price",
                netProceeds: MoneyRangeDTO(currencyCode: currency, low: aLow, likely: aLikely, high: aHigh),
                effort: (tier == .micro || tier == .low) ? .medium : .high,
                timeEstimate: timeA,
                risks: risksA,
                logisticsNotes: logisticsA
            ),
            LiquidationPathOptionDTO(
                path: .pathB_delegateConsign,
                label: "Path B — Delegate / Consign",
                netProceeds: MoneyRangeDTO(currencyCode: currency, low: bLow, likely: bLikely, high: bHigh),
                effort: .low,
                timeEstimate: timeB,
                risks: risksB,
                logisticsNotes: logisticsB
            ),
            LiquidationPathOptionDTO(
                path: .pathC_quickExit,
                label: "Path C — Quick Exit",
                netProceeds: MoneyRangeDTO(currencyCode: currency, low: cLow, likely: cLikely, high: cHigh),
                effort: shipRisk ? .medium : .medium,
                timeEstimate: timeC,
                risks: risksC,
                logisticsNotes: logisticsC
            )
        ]
    }

    // MARK: - Steps (vary by path + category profile)

    private func buildActionSteps(
        title: String,
        category: String,
        description: String,
        qty: Int,
        recommended: LiquidationPathDTO,
        profile: CategoryProfile,
        shipRisk: Bool,
        tier: ValueTier,
        inSet: Bool,
        keepTogetherStrong: Bool
    ) -> [String] {

        let setLine: String? = {
            guard inSet else { return nil }
            if keepTogetherStrong {
                return "Because this is in a set, keep pieces together unless you have a strong reason to split."
            } else {
                return "Because this is in a set, decide: sell together (often better story) vs part out (sometimes higher total)."
            }
        }()

        func baseDetails() -> [String] {
            var s: [String] = []
            s.append("Confirm facts for “\(title)” — condition, measurements, and any maker marks/labels.")
            if qty > 1 { s.append("Confirm quantity (\(qty)) and whether items are truly identical (minor differences change pricing).") }
            if let setLine { s.append(setLine) }
            return s
        }

        switch recommended {
        case .donate:
            var s = baseDetails()
            s += [
                "If donating, take 1–2 photos for your records (optional).",
                "Choose donation destination (Goodwill, Habitat Restore, specialty charity).",
                "Drop off and request receipt if useful for taxes.",
                "Record where/when donated and mark complete."
            ]
            return s

        case .pathB_delegateConsign:
            var s = baseDetails()
            if profile.kind == "jewelry" {
                s += [
                    "Photograph hallmarks (14K/18K), stamps, and any maker’s marks; include clasp/closures.",
                    "If gemstones: note carat (if known), clarity/color notes, and whether you have paperwork.",
                    "Identify 1–3 reputable jewelry buyers/consignors; ask about commission, payout timing, and insurance.",
                    "Get at least one written quote/term sheet; store it in notes.",
                    "Hand off item safely; record who has it and expected follow-up date."
                ]
            } else if shipRisk {
                s += [
                    "Identify 1–3 local consignors / dealers who can handle pickup or bulky logistics.",
                    "Prepare an intake summary (dimensions, weight estimate, condition, key photos).",
                    "Ask about commission and whether they stage/transport items.",
                    "Confirm liability for damage during transport.",
                    "Schedule pickup and record agreement details."
                ]
            } else {
                s += [
                    "Identify 1–3 consignors / specialty buyers for \(category).",
                    "Prepare intake packet (photos + measurements + condition notes).",
                    "Ask about commission %, payout timing, and pricing control.",
                    "Confirm drop-off logistics and damage liability.",
                    "Hand off item and store agreement details in notes."
                ]
            }
            return s

        case .pathA_maximizePrice:
            var s = baseDetails()
            if profile.kind == "jewelry" {
                s += [
                    "Take crisp photos: front/back, clasp, hallmarks, and close-ups of stones/setting.",
                    "Weigh if possible (grams) and record metal purity; note length for bracelets/necklaces.",
                    "Check 3–5 SOLD comps that match metal/stone brand (not asking prices).",
                    "Choose venue: eBay for liquidity; specialty jewelry platforms/dealers for higher-end pieces.",
                    "If shipping: use insured shipping; decide returns policy and document serial/unique marks.",
                    "List with a realistic price + negotiation buffer; review after 7–10 days."
                ]
            } else if shipRisk {
                s += [
                    "Take 10–14 photos including scale (tape measure) and flaws.",
                    "Measure all key dimensions; note weight/sections/disassembly needs.",
                    "Research SOLD comps; focus on local pickup comps when possible.",
                    "Choose venue: Facebook Marketplace / Craigslist / Chairish (local pickup) / specialty local groups.",
                    "Decide pickup logistics (stairs, truck, helpers) and state them clearly in listing.",
                    "List at a realistic price + buffer; refresh posting after 5–7 days if no traction."
                ]
            } else if profile.kind == "electronics" {
                s += [
                    "Record model number, specs, and condition; include serial if safe.",
                    "Factory reset / wipe (if applicable) and photograph powered-on screen.",
                    "Check SOLD comps by exact model + storage/spec variant.",
                    "Choose venue: eBay for broader market; local sale for fast turnover.",
                    "Package safely with anti-static / padding; estimate shipping and include it in pricing.",
                    "List and revisit after 7–10 days; adjust pricing if necessary."
                ]
            } else {
                s += [
                    "Take 10–14 high-quality photos (front/back/detail/maker marks/flaws).",
                    "Measure key dimensions and note condition issues precisely.",
                    "Research 3–5 SOLD comps (not asking prices).",
                    "Draft listing copy (materials, maker, condition, provenance, measurements).",
                    "Choose venue (eBay/Etsy/Chairish/FB) based on category/value.",
                    "Prepare safe shipping materials and estimate shipping cost.",
                    "List with a realistic price + negotiation buffer; revisit after 7–10 days."
                ]
            }
            return s

        case .pathC_quickExit:
            var s = baseDetails()
            if shipRisk {
                s += [
                    "Take 6–10 clear photos in place; include measurements and any flaws.",
                    "Write a short description that emphasizes pickup logistics and condition.",
                    "Set a fast-sale price (expect negotiation; decide your floor).",
                    "Post locally (Facebook Marketplace / Nextdoor / Craigslist).",
                    "Use safe pickup practices: daytime, confirm payment method, no holds.",
                    "Close sale, record final price, mark completed."
                ]
            } else {
                s += [
                    "Take 6–10 clear photos (include flaws).",
                    "Write one-paragraph honest description (facts only).",
                    "Set a fast-sale price (expect negotiation; decide your floor).",
                    "Post locally (Facebook Marketplace / Nextdoor / Craigslist).",
                    "Use safe pickup practices (daytime, confirm payment method, no holds).",
                    "Close sale, record final price, mark completed."
                ]
            }
            return s

        case .needsInfo:
            var s = baseDetails()
            s += [
                "Add missing details (maker marks, measurements, condition notes).",
                "If this is a set, list the pieces and their condition (completeness matters).",
                "Re-run liquidation brief once details are updated."
            ]
            return s
        }
    }

    // MARK: - Missing details / assumptions

    private func buildMissingDetails(
        category: String,
        scope: LiquidationScopeDTO,
        profile: CategoryProfile,
        shipRisk: Bool,
        inSet: Bool
    ) -> [String] {
        if scope == .set {
            return [
                "List of all set members (pieces, counts)",
                "Condition notes per piece",
                "Any maker marks / brand info",
                "Whether you prefer selling together or parting out",
                "Any missing pieces or replacements"
            ]
        }

        var base = [
            "Exact measurements (and weight if meaningful)",
            "Condition notes (chips, cracks, missing parts, scratches)",
            "Maker/brand/model (if any)",
            "Any provenance (receipt, box, story)"
        ]

        if profile.kind == "jewelry" {
            base = [
                "Metal purity (10K/14K/18K/platinum) and stamps/hallmarks",
                "Stone details (type, carat if known, clarity/color notes)",
                "Length/fit (bracelet/necklace) and clasp condition",
                "Maker/brand (if any) and any paperwork"
            ]
        }

        if shipRisk {
            base.append("Pickup/shipping logistics (stairs, weight, disassembly, packaging needs)")
        }

        if inSet {
            base.append("Whether you want this sold with the set or separated")
        }

        return base
    }

    private func buildAssumptions(
        shipRisk: Bool,
        scope: LiquidationScopeDTO,
        inSet: Bool,
        keepTogetherStrong: Bool
    ) -> [String] {
        var a = [
            "Local demand is average",
            "Condition is typical used unless noted"
        ]
        if shipRisk { a.append("Shipping is undesirable or risky for this item") }
        if scope == .set { a.append("Set value may be higher when sold together if cohesive and complete") }
        if inSet && keepTogetherStrong { a.append("Selling together is preferred for this set unless market feedback suggests otherwise") }
        return a
    }

    private func confidenceEstimate(tier: ValueTier, profile: CategoryProfile, inSet: Bool) -> Double {
        // Conservative, but slightly higher when category is well-understood.
        var c: Double = 0.70
        if profile.kind == "jewelry" { c += 0.05 }
        if profile.kind == "bulky" || profile.kind == "rug" { c -= 0.03 } // market variance higher locally
        if inSet { c -= 0.02 } // set interactions add uncertainty
        switch tier {
        case .micro: c -= 0.05
        case .low: break
        case .mid: c += 0.02
        case .high: c += 0.03
        case .ultra: c -= 0.03 // ultra often needs expert specifics
        }
        return min(0.90, max(0.45, c))
    }

    // MARK: - Helpers

    private func looksBulkyFromText(_ description: String) -> Bool {
        let d = description.lowercased()
        return d.contains("dresser")
        || d.contains("sofa")
        || d.contains("table")
        || d.contains("cabinet")
        || d.contains("wardrobe")
        || d.contains("sideboard")
        || d.contains("armoire")
        || d.contains("sectional")
        || d.contains("mattress")
    }

    private func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
