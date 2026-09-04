//
//  CatalogAccessLimitMessageView.swift
//  LegacyTreasureChest
//
//  One-time, informational-only sheet shown to an existing LTC 1.0 user
//  whose migration baseline is already at or above the standard free
//  allowance, the first time monetization becomes applicable to them.
//  Never blocking, never repeated -- see CatalogAccessStateManager's
//  catalogAccessLimitMessageShown flag, checked/set from HomeView.
//
//  Deliberately carries no price -- App Store Connect pricing isn't this
//  view's concern, and nothing here duplicates catalog-count arithmetic.
//

import SwiftUI

struct CatalogAccessLimitMessageView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {
                Text("Your existing catalog is unchanged.")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Everything you've already added remains available to view, edit, organize, and use.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("If you want to add items beyond your current catalog allowance, Full Catalog Access is available as a one-time purchase.")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Got It")
                        .font(Theme.bodyFont.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing.medium)
                        .background(Theme.primary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(Theme.spacing.xl)
            .navigationTitle("Your Catalog")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    CatalogAccessLimitMessageView()
}
