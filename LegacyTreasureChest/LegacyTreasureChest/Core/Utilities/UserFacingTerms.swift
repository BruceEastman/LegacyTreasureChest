//
//  UserFacingTerms.swift
//  LegacyTreasureChest
//
//  Centralized user-facing copy for common concepts.
//  Keep internal names (Partner, DispositionPartnerResult, etc.) unchanged.
//

import Foundation

enum UserFacingTerms {

    // MARK: - Disposition / Partner language (UI-only)

    enum Disposition {
        // Navigation / Titles
        static let chooseWhereToSellTitle = "Choose Where to Sell"

        // Buttons / CTAs
        static let findSellingOptionsCTA = "Find Selling Options"
        static let searchSellingOptionsCTA = "Search Selling Options"

        // Sections / Headings
        static let sellingOptionsHeader = "Selling Options"
        static let recommendedSellingOptionsHeader = "Recommended Selling Options"

        // Field labels
        static let sellingOptionLabel = "Selling Option"
        static let sellingMethodLabel = "Selling Method"

        // States / messages
        static let noSellingOptionsFound = "No selling options found. Try a larger radius or different city."
        static let sellingOptionsSearchFailedPrefix = "Search failed:"
        // MARK: - Local Help (Disposition)

        static let localHelpTitle = "Local Help"
        static let findLocalHelpCTA = "Find Local Help"
        static let localHelpOptionsHeader = "Local Help Options"
        static let noLocalHelpFound = "No local help found. Try a larger radius or adjust the item/category."
        static let googleMapsAttribution = "Business information from Google Maps"
    }

    // MARK: - Liquidation language (UI-only)

    // Pure constants and text helpers; usable from any isolation context.
    nonisolated enum Liquidation {
        static let liquidationHelpHeader = "Selling Help"
        static let localHelpHeader = "Local Help"

        // Approach names. The single source for every customer-facing name of a
        // liquidation path; internal identifiers (PathB_DelegateConsign,
        // pathB_delegateConsign) never appear in the UI. The Gateway's
        // _APPROACH_NAMES must match.
        static let maximizePrice = "Maximize Price"
        static let consignment = "Consignment"
        static let quickSale = "Quick Sale"
        static let donation = "Donation"
        /// A recommendation state, not a selling approach.
        static let moreInformationNeeded = "More Information Needed"

        static func approachName(_ path: LiquidationPathDTO) -> String {
            switch path {
            case .pathA_maximizePrice: return maximizePrice
            case .pathB_delegateConsign: return consignment
            case .pathC_quickExit: return quickSale
            case .donate: return donation
            case .needsInfo: return moreInformationNeeded
            }
        }

        static func approachName(_ path: LiquidationPath) -> String {
            approachName(path.briefPath)
        }

        /// "Consignment Plan". A Plan saved with an unrecognized path reads as "Plan".
        static func planTitle(_ path: LiquidationPath) -> String {
            path == .needsInfo ? "Plan" : "\(approachName(path)) Plan"
        }

        static func statusName(_ status: LiquidationStatus) -> String {
            switch status {
            case .notStarted: return "Not started"
            case .hasBrief: return "Brief ready"
            case .inProgress: return "In progress"
            case .completed: return "Completed"
            case .onHold: return "On hold"
            case .notApplicable: return "Not applicable"
            }
        }

        static func statusName(_ status: PlanStatus) -> String {
            switch status {
            case .notStarted: return "Not started"
            case .inProgress: return "In progress"
            case .completed: return "Completed"
            case .onHold: return "On hold"
            }
        }

        static func effortName(_ effort: EffortLevelDTO) -> String {
            switch effort {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .veryHigh: return "Very high"
            }
        }

        static let estimatesDisclaimer = "Estimates are approximate and not guaranteed."

        // Plans
        static let createPlanAnyway = "Create a Plan Anyway"
        static let createPlanAnywayExplanation =
            "You can still choose an approach now. The Plan will start with the missing details, and its steps may change once they are confirmed."
        static let provisionalPlanNotice =
            "Provisional: created before the Brief could confirm key details."
        static let basicPlanNotice =
            "Basic plan: online Plan generation was unavailable. Choose the approach again when connected for steps specific to this item."

        /// Replaces internal path identifiers that older Briefs may contain in
        /// homeowner-facing text ("pathB_delegateConsign", "Path B", "needsInfo").
        static func customerText(_ text: String) -> String {
            var s = text
            for (pattern, letterGroup) in identifierPatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(s.startIndex..., in: s)
                for match in regex.matches(in: s, range: range).reversed() {
                    guard let whole = Range(match.range, in: s) else { continue }
                    let replacement: String
                    if letterGroup, let letterRange = Range(match.range(at: 1), in: s) {
                        replacement = nameByLetter[s[letterRange].uppercased()] ?? String(s[whole])
                    } else {
                        replacement = moreInformationNeeded
                    }
                    s.replaceSubrange(whole, with: replacement)
                }
            }
            return s
        }

        /// An option label without a leading "Path A — " and without identifiers.
        static func customerLabel(_ label: String) -> String {
            let stripped = label.replacingOccurrences(
                of: #"^\s*[Pp]ath ?[ABC]\s*[—–:\-]\s*"#,
                with: "",
                options: .regularExpression
            )
            return customerText(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static let nameByLetter = ["A": maximizePrice, "B": consignment, "C": quickSale]

        // (pattern, whether capture group 1 is the path letter). Mirrors the Gateway's
        // _RAW_PATH_ID_RE / _PATH_LETTER_RE / _NEEDS_INFO_RE.
        private static let identifierPatterns: [(String, Bool)] = [
            (#"\b[Pp]ath[ _-]?([ABCabc])_[A-Za-z_]+\b"#, true),
            (#"\b[Pp]ath ?([ABC])\b"#, true),
            (#"\bneedsInfo\b"#, false),
        ]
    }
}

