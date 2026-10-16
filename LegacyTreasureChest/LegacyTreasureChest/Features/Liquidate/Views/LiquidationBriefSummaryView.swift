//
//  LiquidationBriefSummaryView.swift
//  LegacyTreasureChest
//
//  Shared Brief presentation for the Item and Set Liquidate screens:
//  - the recommended approach and its specific recommendation
//  - why it is recommended, with the Brief's estimates
//  - missing details, and a comparison of every approach
//  - the approach picker that creates a Plan (homeowner's choice)
//

import SwiftUI

struct LiquidationBriefSummaryView: View {
    let presentation: LiquidationBriefPresentation
    let createdAt: Date
    /// When the screen offers no "View Full Brief" sheet, long reasoning
    /// scrolls in place instead of being truncated.
    var hasFullBriefSheet: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Latest Brief")
                    .font(.headline)
                Spacer()
                Text(createdAt, style: .time)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(presentation.headline)
                .font(.title3.weight(.semibold))

            if let specific = presentation.specificRecommendation {
                Text(specific)
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
            }

            if hasFullBriefSheet {
                Text(presentation.reasoning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            } else {
                ScrollView {
                    Text(presentation.reasoning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 160)
            }

            if let rec = presentation.recommendedOption {
                LiquidationOptionFacts(option: rec)
            }

            // When more information is needed, the screen's own card lists the details.
            if !presentation.needsMoreInformation, !presentation.missingDetails.isEmpty {
                Divider()
                Text("Details that could improve this Brief:")
                    .font(.footnote.weight(.semibold))
                ForEach(presentation.missingDetails.prefix(6), id: \.self) { s in
                    Text("• \(s)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !presentation.options.isEmpty {
                Divider()
                DisclosureGroup("Compare approaches") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(presentation.options) { option in
                            LiquidationOptionComparisonRow(option: option)
                        }
                        Text(UserFacingTerms.Liquidation.estimatesDisclaimer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Estimated net, effort, and time for one option.
private struct LiquidationOptionFacts: View {
    let option: LiquidationBriefPresentation.Option

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let net = option.estimatedNet {
                Text("Estimated net: \(net)")
            }
            Text("Effort: \(option.effort)")
            if let time = option.timeEstimate {
                Text("Time: \(time)")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct LiquidationOptionComparisonRow: View {
    let option: LiquidationBriefPresentation.Option

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(option.name)
                    .font(.subheadline.weight(.semibold))
                if option.isRecommended {
                    Text("Recommended")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            if let specific = option.specificRecommendation {
                Text(specific)
                    .font(.footnote)
            }

            LiquidationOptionFacts(option: option)

            if !option.risks.isEmpty {
                Text("Risks: \(option.risks.joined(separator: "; "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let notes = option.notes {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The homeowner's choice of approach for a Plan. The Brief's recommendation is
/// listed first and highlighted; every approach stays available.
struct LiquidationApproachPicker: View {
    let recommendedPath: LiquidationPathDTO
    let isDisabled: Bool
    let onChoose: (LiquidationPath) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose an approach to create or replace your Plan:")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(LiquidationBriefPresentation.selectableApproaches(recommended: recommendedPath), id: \.self) { path in
                let isRecommended = path.briefPath == recommendedPath
                Button {
                    onChoose(path)
                } label: {
                    Text(isRecommended ? "\(path.displayName) (Recommended)" : path.displayName)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ApproachButtonStyle(isProminent: isRecommended))
            }
        }
        .disabled(isDisabled)
    }
}

private struct ApproachButtonStyle: PrimitiveButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isProminent {
            Button(configuration).buttonStyle(.borderedProminent)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}
