//
//  Theme.swift
//  LegacyTreasureChest
//
//  Centralized design system: colors, fonts, spacing, and a few helpers.
//

import SwiftUI

enum Theme {
    // MARK: - Colors (from Assets.xcassets)

    /// Main brand color used for key actions and highlights.
    static let primary = Color("BrandPrimary")

    /// Secondary / call-to-action accent color.
    static let accent = Color("BrandAccent")

    /// Background for main screens.
    static let background = Color("BrandBackground")

    /// Primary text color.
    static let text = Color("BrandText")

    /// Secondary text color for metadata, captions, etc.
    static let textSecondary = Color("BrandTextSecondary")

    /// Destructive color for delete / dangerous actions.
    static let destructive = Color("BrandDestructive")

    // MARK: - Typography

    /// Large titles (e.g., main screen titles or important headings).
    static let titleFont = Font.system(.title2, design: .rounded)
        .weight(.semibold)

    /// Section headers (e.g., "Photos", "Documents", "Audio").
    static let sectionHeaderFont = Font.system(.headline, design: .rounded)

    /// Primary body text.
    static let bodyFont = Font.system(.body, design: .rounded)

    /// Secondary text, captions, hints.
    static let secondaryFont = Font.system(.subheadline, design: .rounded)

    // MARK: - Spacing

    struct Spacing {
        let xs: CGFloat = 4
        let small: CGFloat = 8
        let medium: CGFloat = 16
        let large: CGFloat = 24
        let xl: CGFloat = 32
    }

    /// Global spacing scale for consistent padding/margins.
    static let spacing = Spacing()
}

// MARK: - Convenience View Modifiers

extension View {

    /// Standard style for section headers, so they look the same everywhere.
    func ltcSectionHeaderStyle() -> some View {
        self
            .font(Theme.sectionHeaderFont)
            .foregroundStyle(Theme.text)
            .padding(.vertical, Theme.spacing.small)
    }

    /// Simple card-style container background for grouped content.
    func ltcCardBackground() -> some View {
        self
            .padding(Theme.spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 1)
            )
    }
}
