//
//  ItemValuationSummaryView.swift
//  LegacyTreasureChest
//
//  Read-only presentation of an item's saved estimate on Item Detail: whether
//  the current value came from AI or the owner, the AI range per unit, a short
//  explanation and what would improve it (both shown below Improve with AI).
//
//  Display only. Values are read from LTCItem / ItemValuation and nothing is
//  written. `LTCItem.value` remains the per-unit value; totals are unit × quantity
//  as everywhere else in the app.
//

import SwiftUI

// MARK: - Presentation model

struct ItemValuationPresentation: Equatable {

    enum Source: Equatable {
        /// No value and no AI result.
        case none
        /// Value entered by the owner; no AI estimate exists.
        case manual
        /// The current value is the AI estimate.
        case aiEstimate
        /// An AI estimate exists, but the current value differs (the owner
        /// changed it) or was cleared.
        case ownerOverride
        /// AI ran but could not estimate a value.
        case aiNotEstimated
    }

    let source: Source
    let quantity: Int
    /// Current per-unit value (nil when not estimated).
    let unitValue: Double?
    /// Unit value × quantity, only when quantity > 1.
    let totalValue: Double?

    /// The AI estimate per unit (midpoint as Apply computes it).
    let aiUnitEstimate: Double?
    let aiLow: Double?
    let aiHigh: Double?
    /// "High" / "Medium" / "Low", shown once.
    let confidenceLabel: String?
    let explanation: String?
    /// Up to three suggestions from the AI's missing details.
    let suggestions: [String]
    let estimatedOn: Date?

    static let maxSuggestions = 3

    init(item: LTCItem) {
        let quantity = max(item.quantity, 1)
        let unitValue = item.estimatedUnitValue
        self.quantity = quantity
        self.unitValue = unitValue
        self.totalValue = (quantity > 1) ? unitValue.map { $0 * Double(quantity) } : nil

        let valuation = item.valuation
        let low = valuation?.valueLow
        let high = valuation?.valueHigh
        let estimate = valuation?.estimatedValue
        let notes = valuation?.aiNotes?.trimmingCharacters(in: .whitespacesAndNewlines)

        // ItemValuation is also created just to hold the owner's More Details
        // notes, so only AI-written fields count as an AI result.
        let hasAIResult = low != nil || high != nil || estimate != nil
            || !(notes ?? "").isEmpty
            || !(valuation?.aiProvider ?? "").isEmpty

        let aiMid: Double? = {
            if let estimate { return estimate }
            if let low, let high { return (low + high) / 2 }
            return low ?? high
        }()

        self.aiLow = hasAIResult ? low : nil
        self.aiHigh = hasAIResult ? high : nil
        self.aiUnitEstimate = hasAIResult ? aiMid : nil
        self.explanation = (hasAIResult && !(notes ?? "").isEmpty) ? notes : nil
        self.suggestions = hasAIResult
            ? Array((valuation?.missingDetails ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(Self.maxSuggestions))
            : []
        self.estimatedOn = hasAIResult ? (valuation?.valuationDate ?? valuation?.updatedAt) : nil
        self.confidenceLabel = (hasAIResult && aiMid != nil)
            ? Self.confidenceLabel(for: valuation?.confidenceScore)
            : nil

        if !hasAIResult {
            self.source = unitValue == nil ? .none : .manual
        } else if let aiMid {
            if let unitValue, abs(unitValue - aiMid) < 0.5 {
                self.source = .aiEstimate
            } else {
                self.source = .ownerOverride
            }
        } else {
            self.source = .aiNotEstimated
        }
    }

    /// Whether a low–high range is worth showing.
    var hasRange: Bool {
        guard let aiLow, let aiHigh else { return false }
        return aiHigh > aiLow
    }

    /// Caption under the value field.
    var sourceCaption: String {
        switch source {
        case .none: return "Not estimated yet"
        case .manual: return "Entered by you"
        case .aiEstimate: return "AI estimate"
        case .ownerOverride: return unitValue == nil ? "No value set" : "Entered by you"
        case .aiNotEstimated: return unitValue == nil ? "AI could not estimate yet" : "Entered by you"
        }
    }

    static func confidenceLabel(for score: Double?) -> String? {
        guard let score else { return nil }
        switch score {
        case 0.8...: return "High"
        case 0.5..<0.8: return "Medium"
        default: return "Low"
        }
    }
}

// MARK: - View (Form rows)

/// The AI range shown below the value and total rows. Renders nothing when
/// there is no AI result, so a manually valued item shows only its value.
struct ItemValuationSummaryView: View {
    let presentation: ItemValuationPresentation

    var body: some View {
        if presentation.aiUnitEstimate != nil || presentation.source == .aiNotEstimated {
            estimateRow
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var estimateRow: some View {
        let p = presentation
        let each = p.quantity > 1 ? " each" : ""

        VStack(alignment: .leading, spacing: 4) {
            if let mid = p.aiUnitEstimate {
                Text(p.source == .aiEstimate ? "AI estimated range" : "AI estimate")
                    .font(Theme.secondaryFont.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)

                if p.hasRange, let low = p.aiLow, let high = p.aiHigh {
                    Text("\(CurrencyFormat.dollars(low)) – \(CurrencyFormat.dollars(high))\(each)")
                        .font(Theme.bodyFont.weight(.semibold))
                        .foregroundStyle(Theme.text)
                } else {
                    Text("\(CurrencyFormat.dollars(mid))\(each)")
                        .font(Theme.bodyFont.weight(.semibold))
                        .foregroundStyle(Theme.text)
                }

                Text(estimateCaption)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("AI could not estimate a value")
                    .font(Theme.secondaryFont.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var estimateCaption: String {
        let p = presentation
        var parts: [String] = []
        if p.source == .ownerOverride {
            parts.append("Your value is used for totals")
        }
        if let confidence = p.confidenceLabel {
            parts.append("\(confidence) confidence")
        }
        if let date = p.estimatedOn {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }
}

/// "Why this estimate": the AI's explanation, shown with the Improve with AI
/// action (below the button). Long text previews two lines with Show more.
/// Renders nothing when there is no explanation.
struct ItemValuationExplanationView: View {
    let explanation: String?

    @State private var showFullExplanation = false

    private static let explanationPreviewLimit = 110

    var body: some View {
        if let explanation {
            explanationRow(explanation)
        }
    }

    private func explanationRow(_ text: String) -> some View {
        let isLong = text.count > Self.explanationPreviewLimit

        return VStack(alignment: .leading, spacing: 6) {
            Text("Why this estimate")
                .font(Theme.secondaryFont.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            Text(text)
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.text)
                .lineLimit(isLong && !showFullExplanation ? 2 : nil)
                .fixedSize(horizontal: false, vertical: true)

            if isLong {
                Button(showFullExplanation ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullExplanation.toggle()
                    }
                }
                .font(Theme.secondaryFont.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The AI's suggestions for improving the estimate, shown with the Improve
/// with AI action. Renders nothing when there are none.
struct ItemValuationSuggestionsView: View {
    let suggestions: [String]

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Could improve this estimate")
                    .font(Theme.secondaryFont.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)

                ForEach(suggestions, id: \.self) { suggestion in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(suggestion)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.text)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }
}
