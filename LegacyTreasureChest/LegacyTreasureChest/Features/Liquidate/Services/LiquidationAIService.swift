//
//  LiquidationAIService.swift
//  LegacyTreasureChest
//
//  Liquidate generation services.
//
//  - Brief: backend-first (gated by FeatureFlags.enableMarketAI), with local fallback.
//  - Plan:  backend-first (gated by FeatureFlags.enableMarketAI), with local fallback.
//
//  This file is intentionally “pure service”: no SwiftUI, no persistence.
//

import Foundation
import SwiftData

// MARK: - Service

struct LiquidationAIService {

    private let backend: BackendAIProvider
    private let flags: FeatureFlags

    // Local fallbacks (compile-safe + deterministic)
    private let localBrief = LocalLiquidationBriefGenerator()
    private let localPlan = LocalLiquidationPlanGenerator()

    init(
        backend: BackendAIProvider = BackendAIProvider(),
        flags: FeatureFlags = FeatureFlags()
    ) {
        self.backend = backend
        self.flags = flags
    }

    // MARK: - Brief (Item)

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

        return try await generateBriefBackendFirst(from: req)
    }

    // MARK: - Brief (Set) — NEW (LTCItemSet)

    /// Generate a liquidation brief for an Item Set (text-only v1; photos later).
    func generateBriefDTO(
        for itemSet: LTCItemSet,
        goal: LiquidationGoalDTO = .balanced,
        constraints: LiquidationConstraintsDTO? = nil,
        locationHint: String? = nil
    ) async throws -> LiquidationBriefDTO {

        let req = LiquidationRequestBuilder.buildRequest(
            for: itemSet,
            goal: goal,
            constraints: constraints,
            locationHint: locationHint
        )

        return try await generateBriefBackendFirst(from: req)
    }

    // MARK: - Plan (Item) — UI-friendly overload

    /// ✅ This is the method your LiquidationSectionView is calling.
    /// It bridges your app’s LiquidationPath -> DTO expected by the backend.
    func generatePlanChecklistDTO(
        for item: LTCItem,
        chosenPath: LiquidationPath,
        briefDTO: LiquidationBriefDTO
    ) async throws -> LiquidationPlanChecklistDTO {

        let dtoPath = chosenPath.asDTO

        let req = LiquidationPlanRequest(
            schemaVersion: 1,
            scope: .item,
            chosenPath: dtoPath,
            brief: briefDTO,
            title: item.name,
            category: item.category
        )

        return try await generatePlanBackendFirst(from: req)
    }

    // MARK: - Plan (Set) — NEW (LTCItemSet)

    func generatePlanChecklistDTO(
        for itemSet: LTCItemSet,
        chosenPath: LiquidationPath,
        briefDTO: LiquidationBriefDTO
    ) async throws -> LiquidationPlanChecklistDTO {

        let dtoPath = chosenPath.asDTO

        let req = LiquidationPlanRequest(
            schemaVersion: 1,
            scope: .set,
            chosenPath: dtoPath,
            brief: briefDTO,
            title: itemSet.name,
            category: itemSet.setType.rawValue
        )

        return try await generatePlanBackendFirst(from: req)
    }

    // MARK: - Backend-first with smart fallback (Brief)

    private func generateBriefBackendFirst(from req: LiquidationBriefRequest) async throws -> LiquidationBriefDTO {

        let shouldTryBackend = flags.enableMarketAI

        guard shouldTryBackend else {
            debugLog("ℹ️ Backend liquidation brief skipped (FeatureFlags.enableMarketAI == false). Using local.")
            return localBrief.generate(from: req, backendError: nil)
        }

        do {
            let dto = try await backend.generateLiquidationBrief(request: req)

            if dto.schemaVersion != req.schemaVersion {
                debugLog("⚠️ Liquidation brief schemaVersion mismatch. req=\(req.schemaVersion) resp=\(dto.schemaVersion)")
            }

            return dto

        } catch {
            // Transport failures (device can't reach server, timeout, etc.) -> fallback OK
            let isTransportFailure: Bool = {
                if error is URLError { return true }
                let ns = error as NSError
                if ns.domain == NSURLErrorDomain { return true }
                return false
            }()

            if isTransportFailure {
                debugLog("⚠️ Backend liquidation brief transport failure; using local fallback. Error: \(error)")
                return localBrief.generate(from: req, backendError: error)
            } else {
                // Decode/schema/model drift -> do NOT hide it with a misleading local brief
                debugLog("❌ Backend liquidation brief decode/schema failure; NOT falling back. Error: \(error)")
                throw error
            }
        }
    }

    // MARK: - Backend-first with fallback (Plan)

    private func generatePlanBackendFirst(from req: LiquidationPlanRequest) async throws -> LiquidationPlanChecklistDTO {

        let shouldTryBackend = flags.enableMarketAI

        if shouldTryBackend {
            do {
                let dto = try await backend.generateLiquidationPlan(request: req)

                if dto.schemaVersion != req.schemaVersion {
                    debugLog("⚠️ Liquidation plan schemaVersion mismatch. req=\(req.schemaVersion) resp=\(dto.schemaVersion)")
                }

                return dto
            } catch {
                debugLog("⚠️ Backend liquidation plan failed; using local fallback. Error: \(error)")
            }
        } else {
            debugLog("ℹ️ Backend liquidation plan skipped (FeatureFlags.enableMarketAI == false). Using local.")
        }

        return localPlan.generate(from: req)
    }

    private func debugLog(_ message: String) {
        guard flags.showDebugInfo else { return }
        print(message)
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

        // If the item belongs to a Closet Lot set, enrich setContext.story with lot metadata.
        let setContext: LiquidationSetContext? = item.set.map { set in
            let storyWithClosetLotMetadata: String? = {
                guard set.setType == .closetLot else { return set.story }

                var lines: [String] = []
                if let base = set.story?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty {
                    lines.append(base)
                }

                var meta: [String] = []
                if let v = set.closetApproxItemCount?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                    meta.append("Approx item count: \(v)")
                }
                if let v = set.closetSizeBand?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                    meta.append("Size band: \(v)")
                }
                if let v = set.closetConditionBandRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                    meta.append("Condition band: \(v)")
                }
                if let v = set.closetBrandList?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                    meta.append("Brands: \(v)")
                }

                if !meta.isEmpty {
                    if !lines.isEmpty { lines.append("") }
                    lines.append("Closet Lot Metadata:")
                    lines.append(contentsOf: meta.map { "• \($0)" })
                }

                let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return joined.isEmpty ? nil : joined
            }()

            return LiquidationSetContext(
                setName: set.name,
                setType: set.setTypeRaw,
                story: storyWithClosetLotMetadata,
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
        }

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
            setContext: setContext,
            inputs: LiquidationInputsDTO(goal: goal, constraints: constraints, locationHint: locationHint)
        )
    }

    /// NEW: build request for LTCItemSet (Sets v1).
    static func buildRequest(
        for itemSet: LTCItemSet,
        goal: LiquidationGoalDTO,
        constraints: LiquidationConstraintsDTO?,
        locationHint: String?
    ) -> LiquidationBriefRequest {

        // Text-only v1: summarize members.
        let memberItems: [LTCItem] = itemSet.memberships.compactMap { $0.item }

        // Total “quantity” concept for set: sum of per-item quantities (membership override if present).
        let totalQty: Int = memberItems.reduce(0) { partial, item in
            let m = itemSet.memberships.first(where: { $0.item?.persistentModelID == item.persistentModelID })
            let q = m?.quantityInSet ?? item.quantity
            return partial + max(1, q)
        }

        let summaries: [LiquidationMemberSummary] = itemSet.memberships.compactMap { membership in
            guard let item = membership.item else { return nil }
            return LiquidationMemberSummary(
                title: item.name,
                category: item.category,
                quantity: membership.quantityInSet ?? item.quantity,
                unitValue: item.value
            )
        }

        // If this is a Clothing closet lot, append the required lot metadata into story for the backend.
        let storyWithClosetLotMetadata: String? = {
            guard itemSet.setType == .closetLot else { return itemSet.story }

            var lines: [String] = []
            if let base = itemSet.story?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty {
                lines.append(base)
            }

            var meta: [String] = []
            if let v = itemSet.closetApproxItemCount?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                meta.append("Approx item count: \(v)")
            }
            if let v = itemSet.closetSizeBand?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                meta.append("Size band: \(v)")
            }
            if let v = itemSet.closetConditionBandRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                meta.append("Condition band: \(v)")
            }
            if let v = itemSet.closetBrandList?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                meta.append("Brands: \(v)")
            }

            if !meta.isEmpty {
                if !lines.isEmpty { lines.append("") }
                lines.append("Closet Lot Metadata:")
                lines.append(contentsOf: meta.map { "• \($0)" })
            }

            let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }()

        let context = LiquidationSetContext(
            setName: itemSet.name,
            setType: itemSet.setType.rawValue,
            story: storyWithClosetLotMetadata,
            sellTogetherPreference: itemSet.sellTogetherPreference.rawValue,
            completeness: itemSet.completeness.rawValue,
            memberSummaries: summaries
        )

        return LiquidationBriefRequest(
            schemaVersion: 1,
            scope: .set,
            title: itemSet.name,
            description: storyWithClosetLotMetadata ?? itemSet.notes,
            category: (itemSet.setType == .closetLot ? "Clothing" : itemSet.setType.rawValue),
            quantity: max(1, totalQty == 0 ? memberItems.count : totalQty),
            unitValue: nil,
            currencyCode: "USD",
            valuationLow: nil,
            valuationLikely: nil,
            valuationHigh: nil,
            photoJpegBase64: nil,
            setContext: context,
            inputs: LiquidationInputsDTO(goal: goal, constraints: constraints, locationHint: locationHint)
        )
    }

    // LEGACY: build request for LTCSet (kept for transition)
    static func buildRequest(
        for set: LTCSet,
        goal: LiquidationGoalDTO,
        constraints: LiquidationConstraintsDTO?,
        locationHint: String?
    ) -> LiquidationBriefRequest {

        // If this is a Clothing closet lot, append the required lot metadata into story for the backend.
        let storyWithClosetLotMetadata: String? = {
            guard set.setType == .closetLot else { return set.story }

            var lines: [String] = []
            if let base = set.story?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty {
                lines.append(base)
            }

            var meta: [String] = []
            if let v = set.closetApproxItemCount?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                meta.append("Approx item count: \(v)")
            }
            if let v = set.closetSizeBand?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                meta.append("Size band: \(v)")
            }
            if let v = set.closetConditionBandRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                meta.append("Condition band: \(v)")
            }
            if let v = set.closetBrandList?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                meta.append("Brands: \(v)")
            }

            if !meta.isEmpty {
                if !lines.isEmpty { lines.append("") }
                lines.append("Closet Lot Metadata:")
                lines.append(contentsOf: meta.map { "• \($0)" })
            }

            let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }()

        return LiquidationBriefRequest(
            schemaVersion: 1,
            scope: .set,
            title: set.name,
            description: storyWithClosetLotMetadata ?? set.notes,
            category: (set.setType == .closetLot ? "Clothing" : set.setTypeRaw),
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
                story: storyWithClosetLotMetadata,
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

// MARK: - Local Brief Fallback (minimal, deterministic)

/// Minimal local brief so the app compiles and remains usable if backend is gated/offline.
/// (You can delete this later once backend is always-on.)
struct LocalLiquidationBriefGenerator {

    func generate(from req: LiquidationBriefRequest, backendError: Error? = nil) -> LiquidationBriefDTO {

        let title = (req.title ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines)
        let category = (req.category ?? "Uncategorized").trimmingCharacters(in: .whitespacesAndNewlines)
        let qty = max(1, req.quantity ?? 1)

        let likelyTotal: Double = {
            // If this is a SET request, compute totals from member summaries when available.
            if req.scope == .set, let ctx = req.setContext, !ctx.memberSummaries.isEmpty {
                return ctx.memberSummaries.reduce(0) { partial, m in
                    let q = Double(max(1, m.quantity ?? 1))
                    let v = max(0, m.unitValue ?? 0)
                    return partial + (q * v)
                }
            }

            // Otherwise, compute from unit value / valuation.
            let likelyUnit = req.valuationLikely ?? req.unitValue ?? 0
            return max(0, likelyUnit) * Double(qty)
        }()

        // Conservative bounds if none provided
        let low = req.valuationLow ?? (likelyTotal * 0.75)
        let high = req.valuationHigh ?? (likelyTotal * 1.25)

        // Simple heuristic: bulky/furniture -> quick exit; otherwise balanced -> quick exit unless higher value
        let lowerCat = category.lowercased()
        let isBulky = lowerCat.contains("furniture") || lowerCat.contains("rug") || lowerCat.contains("appliance")

        let recommended: LiquidationPathDTO = {
            if likelyTotal < 50 { return .donate }
            if isBulky { return .pathC_quickExit }
            if likelyTotal >= 200 { return .pathA_maximizePrice }
            return .pathC_quickExit
        }()

        let reasoning = "Local fallback brief for “\(title)” (\(category)) — qty \(qty). Estimated total ~\(formatMoney(likelyTotal)) (range \(formatMoney(low))–\(formatMoney(high)))."

        let options: [LiquidationPathOptionDTO] = [
            .init(path: .pathA_maximizePrice, label: "Path A — Maximize Price",
                  netProceeds: .init(currencyCode: req.currencyCode ?? "USD", low: low * 0.70, likely: likelyTotal * 0.75, high: high * 0.80),
                  effort: .high, timeEstimate: "1–4 weeks",
                  risks: ["Returns", "Buyer disputes"], logisticsNotes: "More work, potentially higher net."),
            .init(path: .pathB_delegateConsign, label: "Path B — Delegate / Consign",
                  netProceeds: .init(currencyCode: req.currencyCode ?? "USD", low: low * 0.55, likely: likelyTotal * 0.62, high: high * 0.65),
                  effort: .low, timeEstimate: "2–12 weeks",
                  risks: ["Commission", "Payout delays"], logisticsNotes: "Less effort, less control."),
            .init(path: .pathC_quickExit, label: "Path C — Quick Exit",
                  netProceeds: .init(currencyCode: req.currencyCode ?? "USD", low: low * 0.65, likely: likelyTotal * 0.72, high: high * 0.78),
                  effort: .medium, timeEstimate: "1–10 days",
                  risks: ["No-shows", "Lowball offers"], logisticsNotes: "Fastest, simplest.")
        ]

        let steps: [String] = [
            "Confirm details (condition, measurements, maker marks).",
            "Choose a venue appropriate for \(category).",
            "List honestly with clear photos; record final outcome."
        ]

        return LiquidationBriefDTO(
            schemaVersion: req.schemaVersion,
            scope: req.scope,
            generatedAt: .now,
            aiProvider: "local",
            aiModel: "heuristic-min",
            recommendedPath: recommended,
            reasoning: reasoning,
            pathOptions: options,
            actionSteps: steps,
            missingDetails: [],
            assumptions: {
                var a = ["Local fallback used"]
                if let backendError {
                    a.append("Backend error: \(backendError.localizedDescription)")
                }
                return a
            }(),
            confidence: 0.60,
            inputs: req.inputs
        )
    }

    private func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Local Plan Fallback (minimal)

struct LocalLiquidationPlanGenerator {

    func generate(from req: LiquidationPlanRequest) -> LiquidationPlanChecklistDTO {

        let title = req.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = req.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title.isEmpty ? "this item" : title
        let safeCategory = category.isEmpty ? "Uncategorized" : category

        var steps: [String] = [
            "Confirm details for “\(safeTitle)” (\(safeCategory)) — condition, measurements, maker marks.",
            "Review the liquidation brief and note any missing details."
        ]

        switch req.chosenPath {
        case .pathA_maximizePrice:
            steps += [
                "Take 10–14 high-quality photos (front/back/detail/flaws).",
                "Research 3–5 SOLD comps (not asking prices).",
                "Draft a clear listing description with measurements and condition.",
                "Choose an appropriate selling venue for \(safeCategory).",
                "List at a realistic price with a small negotiation buffer.",
                "Review after 7–10 days and adjust if needed."
            ]
        case .pathB_delegateConsign:
            steps += [
                "Identify 1–3 consignors/dealers that handle \(safeCategory).",
                "Prepare intake packet (photos, measurements, condition notes).",
                "Ask about commission %, payout timing, and insurance/liability.",
                "Confirm logistics and document the agreement.",
                "Schedule a follow-up date."
            ]
        case .pathC_quickExit:
            steps += [
                "Take 6–10 clear photos (include flaws).",
                "Write a short, factual description.",
                "Set a fast-sale price and decide your minimum acceptable offer.",
                "Post locally (Facebook Marketplace / Nextdoor / Craigslist).",
                "Use safe pickup practices (daytime, confirm payment method, no holds).",
                "Close sale and record final net proceeds."
            ]
        case .donate:
            steps += [
                "Choose donation destination (Goodwill, Habitat Restore, specialty charity).",
                "Drop off and request a receipt if useful for taxes.",
                "Record donation details and mark complete."
            ]
        case .needsInfo:
            steps += [
                "Collect missing details noted in the brief (maker marks, measurements, condition).",
                "Regenerate the brief.",
                "Choose a path and regenerate the plan."
            ]
        }

        steps.append("AI brief recommended: \(req.brief.recommendedPath.rawValue). Adjust if your situation differs.")

        let items = steps.enumerated().map { idx, text in
            LiquidationChecklistItemDTO(order: idx + 1, text: text)
        }

        return LiquidationPlanChecklistDTO(schemaVersion: req.schemaVersion, createdAt: .now, items: items)
    }
}

// MARK: - Mapping: App Path -> DTO Path

private extension LiquidationPath {
    var asDTO: LiquidationPathDTO {
        switch self {
        case .pathA: return .pathA_maximizePrice
        case .pathB: return .pathB_delegateConsign
        case .pathC: return .pathC_quickExit
        case .donate: return .donate
        case .needsInfo: return .needsInfo
        }
    }
}
