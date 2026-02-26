//
//  CurrencyFormat.swift
//  LegacyTreasureChest
//
//  Centralized currency formatting for UI + PDFs.
//  v1.1 decision: whole-dollar currency only (no cents).
//

import Foundation

enum CurrencyFormat {

    private static let wholeDollarFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        return f
    }()

    /// Formats a single currency value as whole dollars (no cents).
    static func dollars(_ value: Double) -> String {
        let rounded = value.rounded() // whole dollars
        return wholeDollarFormatter.string(from: NSNumber(value: rounded)) ?? "$\(Int(rounded))"
    }

    /// Formats a currency range as whole dollars: "$4,200 – $5,800"
    static func dollarsRange(low: Double?, high: Double?) -> String {
        switch (low, high) {
        case let (l?, h?):
            let lo = min(l, h)
            let hi = max(l, h)
            return "\(dollars(lo)) – \(dollars(hi))"
        case let (l?, nil):
            return dollars(l)
        case let (nil, h?):
            return dollars(h)
        default:
            return "—"
        }
    }
}
