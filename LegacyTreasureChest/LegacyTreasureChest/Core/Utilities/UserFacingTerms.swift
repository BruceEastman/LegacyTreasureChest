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
    }

    // MARK: - Liquidation language (UI-only)

    enum Liquidation {
        static let liquidationHelpHeader = "Selling Help"
        static let localHelpHeader = "Local Help"
    }
}

