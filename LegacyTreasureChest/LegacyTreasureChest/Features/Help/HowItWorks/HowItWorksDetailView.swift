//
//  HowItWorksDetailView.swift
//  LegacyTreasureChest
//
//  Reader view for orientation pages.
//

import SwiftUI

struct HowItWorksDetailView: View {
    let page: HowItWorksPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.medium) {

                Text(page.title)
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.text)
                    .padding(.top, Theme.spacing.small)

                Text(page.body)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)

                if !page.iconRows.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.spacing.medium) {
                        ForEach(page.iconRows) { row in
                            iconRow(row)
                        }
                    }
                    .padding(.top, Theme.spacing.small)
                }

                Spacer(minLength: Theme.spacing.large)
            }
            .padding(.horizontal, Theme.spacing.xl)
            .padding(.vertical, Theme.spacing.large)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func iconRow(_ row: HowItWorksIconRow) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing.medium) {
            Image(systemName: row.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Theme.spacing.xs) {
                Text(row.title)
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundStyle(Theme.text)

                Text(row.body)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
