//
//  LiquidationBriefPresentation.swift
//  LegacyTreasureChest
//
//  What the Item and Set Liquidate screens show for a Brief: the recommended
//  approach, its specific recommendation, and the alternatives for comparison.
//  Pure value type (no SwiftUI) so both screens present a Brief identically.
//

import Foundation

struct LiquidationBriefPresentation {

    struct Option: Identifiable {
        let path: LiquidationPathDTO
        /// Maximize Price, Consignment, Quick Sale, or Donation.
        let name: String
        /// The Brief's more specific recommendation, when it adds something to `name`.
        let specificRecommendation: String?
        /// "$900 – $1,300", or nil when the Brief has no estimate.
        let estimatedNet: String?
        let effort: String
        let timeEstimate: String?
        let risks: [String]
        let notes: String?
        let isRecommended: Bool

        var id: String { path.rawValue }
    }

    let recommendedPath: LiquidationPathDTO
    /// The Brief recommends gathering more information before choosing an approach.
    let needsMoreInformation: Bool
    /// "Recommended: Consignment", or "More Information Needed".
    let headline: String
    let specificRecommendation: String?
    let reasoning: String
    /// The recommended option first, then the others in their usual order.
    let options: [Option]
    let missingDetails: [String]
    /// Made on the device because the server could not be reached.
    let isBasicBrief: Bool

    var recommendedOption: Option? { options.first(where: { $0.isRecommended }) }

    init(dto: LiquidationBriefDTO) {
        let terms = UserFacingTerms.Liquidation.self

        recommendedPath = dto.recommendedPath
        needsMoreInformation = dto.recommendedPath == .needsInfo
        headline = needsMoreInformation
            ? terms.moreInformationNeeded
            : "Recommended: \(terms.approachName(dto.recommendedPath))"
        reasoning = terms.customerText(dto.reasoning)
        missingDetails = dto.missingDetails.map(terms.customerText)
        isBasicBrief = dto.aiProvider == "local"

        let built = dto.pathOptions
            .filter { $0.path != .needsInfo }
            .map { opt in
                Self.makeOption(opt, isRecommended: opt.path == dto.recommendedPath)
            }
        options = built.filter(\.isRecommended)
            + built.filter { !$0.isRecommended }.sorted { Self.order($0.path) < Self.order($1.path) }

        specificRecommendation = options.first(where: { $0.isRecommended })?.specificRecommendation
    }

    /// The approaches a homeowner can choose for a Plan, recommended first.
    /// All four are always offered so the homeowner keeps control.
    static func selectableApproaches(recommended: LiquidationPathDTO) -> [LiquidationPath] {
        let all: [LiquidationPath] = [.pathA, .pathB, .pathC, .donate]
        guard let rec = all.first(where: { $0.briefPath == recommended }) else { return all }
        return [rec] + all.filter { $0 != rec }
    }

    // MARK: - Helpers

    private static func makeOption(_ opt: LiquidationPathOptionDTO, isRecommended: Bool) -> Option {
        let terms = UserFacingTerms.Liquidation.self
        let name = terms.approachName(opt.path)

        let label = terms.customerLabel(opt.label)
        let specific: String? = {
            guard !label.isEmpty else { return nil }
            // A label that only repeats the approach name adds nothing.
            return label.caseInsensitiveCompare(name) == .orderedSame ? nil : label
        }()

        let notes = opt.logisticsNotes
            .map(terms.customerText)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Option(
            path: opt.path,
            name: name,
            specificRecommendation: specific,
            estimatedNet: estimatedNet(opt.netProceeds),
            effort: terms.effortName(opt.effort),
            timeEstimate: opt.timeEstimate.flatMap { $0.isEmpty ? nil : terms.customerText($0) },
            risks: opt.risks.map(terms.customerText).filter { !$0.isEmpty },
            notes: (notes?.isEmpty ?? true) ? nil : notes,
            isRecommended: isRecommended
        )
    }

    /// A range when the Brief gives one; a single figure only as "About $X".
    /// Nil when there is no estimate, so nothing is invented.
    static func estimatedNet(_ range: MoneyRangeDTO?) -> String? {
        guard let range else { return nil }
        if range.low != nil || range.high != nil {
            return CurrencyFormat.dollarsRange(low: range.low, high: range.high)
        }
        if let likely = range.likely {
            return "About \(CurrencyFormat.dollars(likely))"
        }
        return nil
    }

    private static func order(_ path: LiquidationPathDTO) -> Int {
        switch path {
        case .pathA_maximizePrice: return 0
        case .pathB_delegateConsign: return 1
        case .pathC_quickExit: return 2
        case .donate: return 3
        case .needsInfo: return 4
        }
    }
}
