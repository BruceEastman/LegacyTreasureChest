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

    // MARK: - Plan (Item)

    /// Plan for the approach the homeowner chose. More Information Needed is a
    /// Brief state, never a chosen approach, so it is rejected here.
    func generatePlanChecklistDTO(
        for item: LTCItem,
        chosenPath: LiquidationPath,
        briefDTO: LiquidationBriefDTO
    ) async throws -> LiquidationPlanChecklistDTO {
        let req = try LiquidationRequestBuilder.buildPlanRequest(for: item, chosenPath: chosenPath, brief: briefDTO)
        return try await generatePlanBackendFirst(from: req)
    }

    // MARK: - Plan (Set)

    func generatePlanChecklistDTO(
        for itemSet: LTCItemSet,
        chosenPath: LiquidationPath,
        briefDTO: LiquidationBriefDTO
    ) async throws -> LiquidationPlanChecklistDTO {
        let req = try LiquidationRequestBuilder.buildPlanRequest(for: itemSet, chosenPath: chosenPath, brief: briefDTO)
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
            // Transport failures (device can't reach server, timeout) -> fallback OK
            if Self.allowsBasicBriefFallback(for: error) {
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

    /// The basic offline Plan covers only connectivity and temporary service
    /// problems. Schema, decoding, and request errors are surfaced, never
    /// masked by a generic checklist.
    private func generatePlanBackendFirst(from req: LiquidationPlanRequest) async throws -> LiquidationPlanChecklistDTO {

        guard flags.enableMarketAI else {
            debugLog("ℹ️ Backend liquidation plan skipped (FeatureFlags.enableMarketAI == false). Using basic plan.")
            return localPlan.generate(from: req)
        }

        do {
            let dto = try await backend.generateLiquidationPlan(request: req)

            if dto.schemaVersion != req.schemaVersion {
                debugLog("⚠️ Liquidation plan schemaVersion mismatch. req=\(req.schemaVersion) resp=\(dto.schemaVersion)")
            }

            return dto
        } catch {
            guard Self.allowsBasicPlanFallback(for: error) else {
                debugLog("❌ Backend liquidation plan failed; NOT falling back. Error: \(error)")
                throw error
            }
            debugLog("⚠️ Backend liquidation plan unavailable; using basic plan. Error: \(error)")
            return localPlan.generate(from: req)
        }
    }

    /// The offline Brief covers only a device that cannot reach the server.
    /// BackendAIProvider reports that as AIError.offline or .timeout (raw
    /// URLErrors never reach this service), so checking only URLError meant the
    /// fallback never ran. Server, decoding, and request errors are surfaced.
    static func allowsBasicBriefFallback(for error: Error) -> Bool {
        if let ai = error as? AIError {
            switch ai {
            case .offline, .timeout: return true
            default: return false
            }
        }
        if error is URLError { return true }
        return (error as NSError).domain == NSURLErrorDomain
    }

    /// Offline, timeouts, and temporary server unavailability (including an AI
    /// provider failure reported as 5xx) allow the basic Plan.
    static func allowsBasicPlanFallback(for error: Error) -> Bool {
        if let ai = error as? AIError {
            switch ai {
            case .offline, .timeout, .temporarilyUnavailable, .serviceUnavailable:
                return true
            default:
                return false
            }
        }
        if error is URLError { return true }
        return (error as NSError).domain == NSURLErrorDomain
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
                        unitValue: $0.estimatedUnitValue
                    )
                }
            )
        }

        // Send the AI range only while it still describes the current Estimated Unit Value.
        // A user edit makes the stored range obsolete. Compare in whole dollars, the
        // precision the value field edits in.
        let unitValue = item.estimatedUnitValue
        let aiRangeIsCurrent = aiValuationRangeIsCurrent(for: item)

        return LiquidationBriefRequest(
            schemaVersion: 1,
            scope: .item,
            title: item.name,
            description: item.itemDescription,
            category: item.category,
            quantity: item.quantity,
            unitValue: unitValue,
            currencyCode: valuation?.currencyCode ?? "USD",
            valuationLow: aiRangeIsCurrent ? valuation?.valueLow : nil,
            valuationLikely: aiRangeIsCurrent ? valuation?.estimatedValue : nil,
            valuationHigh: aiRangeIsCurrent ? valuation?.valueHigh : nil,
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
                unitValue: item.estimatedUnitValue,
                photoCount: item.images.count
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
                        unitValue: $0.estimatedUnitValue
                    )
                }
            ),
            inputs: LiquidationInputsDTO(goal: goal, constraints: constraints, locationHint: locationHint)
        )
    }

    /// Whether the stored AI range still describes the item's current Estimated
    /// Unit Value. A user edit makes it obsolete. Compared in whole dollars, the
    /// precision the value field edits in.
    static func aiValuationRangeIsCurrent(for item: LTCItem) -> Bool {
        guard let likely = item.valuation?.estimatedValue, let unit = item.estimatedUnitValue else { return false }
        return likely.rounded() == unit.rounded()
    }

    // MARK: - Plan v2 requests

    enum PlanRequestError: LocalizedError {
        case noApproachChosen

        var errorDescription: String? {
            "Choose Maximize Price, Consignment, Quick Sale, or Donation to create a Plan."
        }
    }

    /// The chosen approach as sent to the Gateway. More Information Needed is never one.
    static func planPath(_ chosenPath: LiquidationPath) throws -> LiquidationPathDTO {
        guard chosenPath != .needsInfo else { throw PlanRequestError.noApproachChosen }
        return chosenPath.briefPath
    }

    /// Plan v2 request for an item: the chosen Brief option plus what LTC already
    /// knows (metadata only: photo/document counts and types, never the files).
    static func buildPlanRequest(
        for item: LTCItem,
        chosenPath: LiquidationPath,
        brief: LiquidationBriefDTO
    ) throws -> LiquidationPlanRequest {
        let path = try planPath(chosenPath)
        let valuation = item.valuation
        let rangeIsCurrent = aiValuationRangeIsCurrent(for: item)

        let description = item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = valuation?.aiNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let documentTypes = Set(item.documents.map {
            $0.documentType.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })

        let context = LiquidationPlanItemContextDTO(
            description: description.isEmpty ? nil : description,
            quantity: max(item.quantity, 1),
            unitValue: item.estimatedUnitValue,
            currencyCode: valuation?.currencyCode ?? "USD",
            valuationLow: rangeIsCurrent ? valuation?.valueLow : nil,
            valuationHigh: rangeIsCurrent ? valuation?.valueHigh : nil,
            valuationNotes: (rangeIsCurrent && !notes.isEmpty) ? notes : nil,
            photoCount: item.images.count,
            documentCount: item.documents.count,
            documentTypes: documentTypes.sorted(),
            hasAudioStory: !item.audioRecordings.isEmpty
        )

        return LiquidationPlanRequest(
            schemaVersion: 2,
            scope: .item,
            chosenPath: path,
            brief: brief,
            title: item.name,
            category: item.category,
            selectedOption: brief.pathOptions.first(where: { $0.path == path }),
            isRecommended: brief.recommendedPath == path,
            itemContext: context
        )
    }

    /// Plan v2 request for a Set, with the same Set context the Brief used
    /// (member summaries, completeness, sell-together preference, closet-lot details).
    static func buildPlanRequest(
        for itemSet: LTCItemSet,
        chosenPath: LiquidationPath,
        brief: LiquidationBriefDTO
    ) throws -> LiquidationPlanRequest {
        let path = try planPath(chosenPath)
        let setContext = buildRequest(for: itemSet, goal: .balanced, constraints: nil, locationHint: nil).setContext

        return LiquidationPlanRequest(
            schemaVersion: 2,
            scope: .set,
            chosenPath: path,
            brief: brief,
            title: itemSet.name,
            category: itemSet.setType.rawValue,
            selectedOption: brief.pathOptions.first(where: { $0.path == path }),
            isRecommended: brief.recommendedPath == path,
            setContext: setContext
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

        // nil means no value has been estimated; it must not be treated as $0.
        let knownLikelyTotal: Double? = {
            // If this is a SET request, compute totals from member summaries when available.
            if req.scope == .set, let ctx = req.setContext, !ctx.memberSummaries.isEmpty {
                let valued = ctx.memberSummaries.filter { $0.unitValue != nil }
                guard !valued.isEmpty else { return nil }
                return valued.reduce(0) { partial, m in
                    let q = Double(max(1, m.quantity ?? 1))
                    let v = max(0, m.unitValue ?? 0)
                    return partial + (q * v)
                }
            }

            // Otherwise, compute from unit value / valuation.
            guard let likelyUnit = req.valuationLikely ?? req.unitValue else { return nil }
            return max(0, likelyUnit) * Double(qty)
        }()

        guard let likelyTotal = knownLikelyTotal else {
            return notEstimatedBrief(from: req, title: title, category: category, backendError: backendError)
        }

        // Set members without an estimate make the total incomplete (a known subtotal only).
        let setMembers = (req.scope == .set) ? (req.setContext?.memberSummaries ?? []) : []
        let unvaluedMemberCount = setMembers.filter { $0.unitValue == nil }.count
        let isIncompleteTotal = unvaluedMemberCount > 0

        // Conservative bounds if none provided
        let low = req.valuationLow ?? (likelyTotal * 0.75)
        let high = req.valuationHigh ?? (likelyTotal * 1.25)

        // Simple heuristic: bulky/furniture -> quick exit; otherwise balanced -> quick exit unless higher value
        let lowerCat = category.lowercased()
        let isBulky = lowerCat.contains("furniture") || lowerCat.contains("rug") || lowerCat.contains("appliance")

        let recommended: LiquidationPathDTO = {
            // A low known subtotal says nothing about unvalued members.
            if likelyTotal < 50 { return isIncompleteTotal ? .needsInfo : .donate }
            if isBulky { return .pathC_quickExit }
            if likelyTotal >= 200 { return .pathA_maximizePrice }
            return .pathC_quickExit
        }()

        let reasoning: String = {
            if isIncompleteTotal {
                let valuedCount = setMembers.count - unvaluedMemberCount
                return "Basic estimate for “\(title)” (\(category)). Known subtotal about \(formatMoney(likelyTotal)) for \(valuedCount) of \(setMembers.count) members; \(unvaluedMemberCount) not estimated, so the set total is incomplete and may be higher."
            }
            return "Basic estimate for “\(title)” (\(category)), quantity \(qty). Estimated total about \(formatMoney(likelyTotal)) (range \(formatMoney(low)) to \(formatMoney(high)))."
        }()

        let isLuxuryHub = looksLikeLuxuryHubScenario(req)

        let options: [LiquidationPathOptionDTO] = [
            .init(path: .pathA_maximizePrice, label: UserFacingTerms.Liquidation.maximizePrice,
                  netProceeds: .init(currencyCode: req.currencyCode ?? "USD", low: low * 0.70, likely: likelyTotal * 0.75, high: high * 0.80),
                  effort: .high, timeEstimate: "1–4 weeks",
                  risks: ["Returns", "Buyer disputes"], logisticsNotes: "More work, potentially higher net."),
            .init(
                path: .pathB_delegateConsign,
                label: isLuxuryHub ? "Luxury mail-in consignment" : UserFacingTerms.Liquidation.consignment,
                netProceeds: .init(
                    currencyCode: req.currencyCode ?? "USD",
                    low: low * 0.55,
                    likely: likelyTotal * 0.62,
                    high: high * 0.65
                ),
                effort: .low,
                timeEstimate: "2–12 weeks",
                risks: isLuxuryHub
                    ? ["Commission", "Acceptance / condition grading", "Payout delays"]
                    : ["Commission", "Payout delays"],
                logisticsNotes: isLuxuryHub
                    ? "Mail-in hub / specialist channel. Authentication + condition standards matter; expect commissions and variable payout timing."
                    : "Less effort, less control."
            ),
     .init(path: .pathC_quickExit, label: UserFacingTerms.Liquidation.quickSale,
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
            missingDetails: isIncompleteTotal
                ? ["Estimated values for \(unvaluedMemberCount) set member(s)"]
                : [],
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
    
    /// Fallback brief when no value has been estimated. Recommends gathering more
    /// information (which blocks plan creation) instead of reasoning from an assumed $0.
    private func notEstimatedBrief(
        from req: LiquidationBriefRequest,
        title: String,
        category: String,
        backendError: Error?
    ) -> LiquidationBriefDTO {
        LiquidationBriefDTO(
            schemaVersion: req.schemaVersion,
            scope: req.scope,
            generatedAt: .now,
            aiProvider: "local",
            aiModel: "heuristic-min",
            recommendedPath: .needsInfo,
            reasoning: "Basic estimate for “\(title)” (\(category)). The resale value has not been estimated, so a selling approach is not recommended yet.",
            pathOptions: [],
            actionSteps: [
                "Add identifying details or photos, then run Improve with AI.",
                "Or enter an Estimated Unit Value if you know it.",
                "Generate the brief again."
            ],
            missingDetails: ["Estimated resale value (run Improve with AI or enter an Estimated Unit Value)"],
            assumptions: {
                var a = ["Local fallback used", "Value not estimated"]
                if let backendError {
                    a.append("Backend error: \(backendError.localizedDescription)")
                }
                return a
            }(),
            confidence: nil,
            inputs: req.inputs
        )
    }

    private func looksLikeLuxuryHubScenario(_ req: LiquidationBriefRequest) -> Bool {
        var textParts: [String] = []

        if let s = req.category { textParts.append(s) }
        if let s = req.title { textParts.append(s) }
        if let s = req.description { textParts.append(s) }

        if let sc = req.setContext {
            if let s = sc.setName { textParts.append(s) }
            if let s = sc.story { textParts.append(s) }
            // member summaries
            for m in sc.memberSummaries {
                if let s = m.title { textParts.append(s) }
                if let s = m.category { textParts.append(s) }
            }
        }

        let text = textParts.joined(separator: " ").lowercased()

        // Broad luxury signals (category-driven)
        let luxuryCategorySignals = [
            "luxury clothing",
            "luxury personal items",
            "designer",
            "luxury"
        ]

        if luxuryCategorySignals.contains(where: { text.contains($0) }) {
            return true
        }

        // Watch & handbag signals (tight, specific)
        let hubSignals = [
            // watches
            "watch", "watches", "rolex", "omega", "cartier", "tudor", "chronograph", "gmt",
            // handbags
            "handbag", "handbags", "purse", "bag", "chanel", "louis vuitton", "lv", "hermes", "gucci", "prada",
            // handbags (optional extensions)
            "tote", "satchel", "clutch", "crossbody", "fendi", "celine", "ysl", "saint laurent", "bottega"
        ]

        return hubSignals.contains(where: { text.contains($0) })
    }


    private func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Basic Plan (offline fallback)

/// A short, honest checklist for the chosen approach when online Plan
/// generation is unavailable. The Plan screen labels it as basic.
struct LocalLiquidationPlanGenerator {

    static let providerName = "local"
    static let modelName = "basic-plan-v2"

    func generate(from req: LiquidationPlanRequest) -> LiquidationPlanChecklistDTO {
        let terms = UserFacingTerms.Liquidation.self
        let option = req.selectedOption ?? req.brief.pathOptions.first(where: { $0.path == req.chosenPath })
        let name = terms.approachName(req.chosenPath)
        let specific: String? = option.map { terms.customerLabel($0.label) }
            .flatMap { $0.isEmpty || $0.caseInsensitiveCompare(name) == .orderedSame ? nil : $0 }
        let helpAction = (req.brief.specialty?.isSpecialistItem == true) ? "findSpecialtyHelp" : "findHelp"
        let hasEstimate = option?.netProceeds.map { $0.low != nil || $0.high != nil || $0.likely != nil } ?? false
        let priceDetail = hasEstimate ? "Use the Brief's estimate as a rough guide, not a set price." : nil

        var steps: [LiquidationChecklistItemDTO] = []
        func add(_ text: String, detail: String? = nil, action: String? = nil) {
            steps.append(.init(order: steps.count + 1, text: text, detail: detail, action: action))
        }

        // A provisional Plan starts with the fact the Brief could not confirm.
        if req.brief.recommendedPath == .needsInfo,
           let missing = req.brief.missingDetails.first.map(terms.customerText), !missing.isEmpty {
            add("Confirm the key missing detail: \(missing)",
                detail: "The Brief could not recommend an approach without it.")
        }

        switch req.chosenPath {
        case .pathA_maximizePrice:
            add("Choose where buyers for this kind of item look", detail: specific)
            add("List it with your saved photos and description", detail: priceDetail)
            add("Compare offers, then arrange safe payment and delivery")
        case .pathB_delegateConsign:
            add("Find a consignor or dealer who handles this kind of item",
                detail: specific.map { "The Brief suggests: \($0)." }, action: helpAction)
            add("Confirm they will accept it, and compare commission and payout timing")
            add("Hand it over and keep the signed agreement")
        case .pathC_quickExit:
            add("Post it locally with your saved photos and an honest description")
            add("Set an asking price and decide your lowest acceptable offer", detail: priceDetail)
            add("Meet buyers safely and accept only secure payment")
        case .donate:
            add("Find a charity or donation center that accepts this kind of item", action: "findHelp")
            add("Confirm they will take it, then drop it off or schedule pickup")
            add("Ask for a receipt if it is useful for taxes")
        case .needsInfo:
            add("Add the missing details from the Brief, then create the Plan again")
        }

        return LiquidationPlanChecklistDTO(
            schemaVersion: req.schemaVersion,
            createdAt: .now,
            items: steps,
            aiProvider: Self.providerName,
            aiModel: Self.modelName
        )
    }
}
