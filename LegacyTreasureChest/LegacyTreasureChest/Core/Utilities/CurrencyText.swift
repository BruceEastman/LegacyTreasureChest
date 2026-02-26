//
//  CurrencyText.swift
//  LegacyTreasureChest
//
//  SwiftUI helpers for consistent currency display.
//  v1.1: whole-dollar currency (no cents).
//

import SwiftUI

enum CurrencyText {

    /// Whole-dollar currency for non-optional values.
    static func string(_ value: Double) -> String {
        CurrencyFormat.dollars(value)
    }

    /// Whole-dollar currency for optional values.
    /// Displays an em dash if nil or <= 0.
    static func string(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return CurrencyFormat.dollars(value)
    }

    /// SwiftUI Text for non-optional value.
    static func view(_ value: Double) -> Text {
        Text(string(value))
    }

    /// SwiftUI Text for optional value.
    static func view(_ value: Double?) -> Text {
        Text(string(value))
    }
}
