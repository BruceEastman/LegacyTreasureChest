//
//  ImproveWithAIReviewView.swift
//  LegacyTreasureChest
//
//  Improve with AI, state 2: what the AI proposes versus the item now, with
//  independent choices for name, category, description, each detail and the
//  value. Nothing is saved until "Apply Selected"; "Keep Current Information"
//  closes without changes. Defaults come from ItemAnalysisReview.
//

import SwiftUI

struct ImproveWithAIReviewView: View {
    @Bindable var model: ImproveWithAIModel
    let analysis: ItemAnalysis
    let review: ItemAnalysisReview
    let onApply: () -> Void
    let onKeepCurrent: () -> Void

    @State private var showFullCurrentDescription = false
    @State private var showFullExplanation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing.large) {
                if !review.warnings.isEmpty {
                    warningsCard
                }
                identificationSection
                descriptionSection
                if !review.attributes.isEmpty {
                    detailsSection
                }
                previewSection
                valueSection
                Spacer(minLength: 24)
            }
            .padding(.horizontal, Theme.spacing.large)
            .padding(.top, Theme.spacing.medium)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    // MARK: - Warnings

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Check before applying", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.bodyFont.weight(.semibold))
                .foregroundStyle(Theme.text)
            ForEach(review.warnings) { warning in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(message(for: warning)).fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.text)
            }
        }
        .padding(Theme.spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent.opacity(0.14)))
    }

    private func message(for warning: ItemAnalysisReview.Warning) -> String {
        switch warning {
        case .valuationUnclear(let quantity, _):
            return "LTC could not establish an estimate for one of the \(quantity) items, so no value will be applied. See Estimated Resale Value below."
        case .groupAllocation(let quantity):
            return "The AI priced all \(quantity) items together. LTC shows an equal per-item share below; it is applied only if you select it."
        case .conflict(let text):
            return "The AI noted: \(text)"
        case .possibleIdentifier:
            return "The suggestion may include a report, certificate, or account number, or personal details such as an address. Read the text before adding it."
        case .documentDerived:
            return "Suggestions may include information read from your document. Nothing is added unless you choose it below."
        case .largeValueChange(let current, let proposed):
            return "The new estimate is very different from the current value (\(CurrencyFormat.dollars(current)) → \(CurrencyFormat.dollars(proposed)) each)."
        }
    }

    // MARK: - Identification

    private var identificationSection: some View {
        section("Name and Category") {
            VStack(alignment: .leading, spacing: 12) {
                comparison(label: "Name",
                           current: review.title.current.isEmpty ? "No name" : review.title.current,
                           proposed: review.title.proposed)
                if review.title.isChange && !review.title.proposed.isEmpty {
                    Toggle("Use the suggested name", isOn: $model.choices.title)
                        .tint(Theme.accent)
                } else {
                    caption("The name is unchanged.")
                }

                if review.categoryChanged {
                    Divider()
                    comparison(label: "Category", current: review.category.current, proposed: review.category.proposed)
                    Toggle("Change the category", isOn: $model.choices.category)
                        .tint(Theme.accent)
                }
            }
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        section("Description") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    caption("Current · \(review.currentDescriptionOrigin)")
                    if review.currentDescription.isEmpty {
                        Text("No description").font(Theme.secondaryFont).foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(review.currentDescription)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.text)
                            .lineLimit(showFullCurrentDescription ? nil : 4)
                            .fixedSize(horizontal: false, vertical: true)
                        if review.currentDescription.count > 160 {
                            moreButton($showFullCurrentDescription)
                        }
                    }
                }

                if review.proposedParagraph.isEmpty {
                    caption("The AI did not suggest a description.")
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        caption("Suggested")
                        Text(review.proposedParagraph)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Toggle(review.paragraphActionLabel, isOn: Binding(
                        get: { model.choices.paragraph == .useAI },
                        set: { model.choices.paragraph = $0 ? .useAI : .keep }
                    ))
                    .tint(Theme.accent)

                    if review.paragraphReplacesOwnerText && model.choices.paragraph == .useAI {
                        Text("Your current description will be replaced. It may contain details you added.")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.destructive)
                    }
                }
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        section("Details") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(review.attributes) { row in
                    attributeRow(row)
                }
                caption("Existing details remain unchanged unless you select a suggested change.")
            }
        }
    }

    @ViewBuilder
    private func attributeRow(_ row: ItemAnalysisReview.AttributeRow) -> some View {
        switch row.kind {
        case .new:
            Toggle(isOn: attributeBinding(row.label)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \(row.label)").font(Theme.secondaryFont.weight(.semibold))
                    Text(row.proposed ?? "").font(Theme.secondaryFont).foregroundStyle(Theme.text)
                }
            }
            .tint(Theme.accent)
        case .changed:
            Toggle(isOn: attributeBinding(row.label)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Change \(row.label)").font(Theme.secondaryFont.weight(.semibold))
                    Text("\(row.current ?? "") → \(row.proposed ?? "")").font(Theme.secondaryFont).foregroundStyle(Theme.text)
                }
            }
            .tint(Theme.accent)
        case .same:
            caption("\(row.label): \(row.current ?? "") (no change)")
        case .notMentioned:
            caption("\(row.label): \(row.current ?? "") (kept)")
        }
    }

    private func attributeBinding(_ label: String) -> Binding<Bool> {
        Binding(
            get: { model.choices.attributeLabels.contains(label) },
            set: { on in
                if on { model.choices.attributeLabels.insert(label) } else { model.choices.attributeLabels.remove(label) }
            }
        )
    }

    // MARK: - Preview of the saved description

    @ViewBuilder
    private var previewSection: some View {
        let preview = model.previewDescription() ?? review.currentDescription
        section("Description After Applying") {
            if preview == review.currentDescription {
                caption("The description will not change.")
            } else {
                Text(preview)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Value

    private var valueSection: some View {
        let v = review.valuation
        let each = v.quantity > 1 ? " each" : ""
        return section("Estimated Resale Value") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    caption("Current value")
                    Spacer()
                    Text(v.currentUnitValue.map { CurrencyFormat.dollars($0) + each } ?? CurrencyFormat.notEstimated)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.text)
                }
                if let total = v.currentTotal {
                    amountRow("Current total for \(v.quantity)", CurrencyFormat.dollars(total))
                }

                Divider()

                if !v.hasEstimate {
                    caption(v.explanation ?? "The AI could not estimate a value.")
                    caption("Current value and valuation details will remain unchanged.")
                } else if v.isAmbiguous {
                    unclearValuation(v)
                } else {
                    proposedValuation(v, each: each)
                }
            }
        }
    }

    /// A per-unit estimate, or an equal allocation of a group estimate.
    @ViewBuilder
    private func proposedValuation(_ v: ItemAnalysisReview.Valuation, each: String) -> some View {
        if v.isAllocation, case .group(let size) = v.basis {
            if let low = v.aiLow, let high = v.aiHigh, high > low {
                amountRow("AI estimate for all \(size)", "\(CurrencyFormat.dollars(low)) – \(CurrencyFormat.dollars(high))",
                          emphasized: true)
            } else if let mid = v.aiEstimate {
                amountRow("AI estimate for all \(size)", CurrencyFormat.dollars(mid), emphasized: true)
            }
            if let low = v.proposedLow, let high = v.proposedHigh, high > low {
                amountRow("Allocated per item", "\(CurrencyFormat.dollars(low)) – \(CurrencyFormat.dollars(high)) each")
            }
            if let mid = v.proposedEstimate {
                amountRow("Value to apply", "\(CurrencyFormat.dollars(mid)) each", emphasized: true)
            }
            if let total = v.proposedTotal {
                amountRow("Total for \(v.quantity)", CurrencyFormat.dollars(total))
            }
            caption("The AI priced the \(size) items together. LTC divided that estimate equally; the per-item figure is an allocation, not a separately established selling price for one item.")
        } else if let mid = v.proposedEstimate {
            if let low = v.proposedLow, let high = v.proposedHigh, high > low {
                amountRow("Suggested resale range", "\(CurrencyFormat.dollars(low)) – \(CurrencyFormat.dollars(high))\(each)",
                          emphasized: true)
                amountRow("Value to apply", "\(CurrencyFormat.dollars(mid))\(each) (range midpoint)")
            } else {
                amountRow("Suggested estimate", "\(CurrencyFormat.dollars(mid))\(each)", emphasized: true)
            }
            if let total = v.proposedTotal {
                amountRow("Suggested total for \(v.quantity)", CurrencyFormat.dollars(total))
            }
            if let unit = v.unit {
                caption("Estimate is for: \(unit)")
            }
        }

        if let confidence = v.confidenceLabel {
            caption("\(ItemValuationPresentation.confidenceCaption(for: confidence)). "
                    + "A preliminary resale estimate, not an appraisal.")
        }
        explanationText(v.explanation)

        Toggle(v.currentUnitValue == nil ? "Use suggested estimate" : "Update estimated value",
               isOn: $model.choices.valuation)
            .tint(Theme.accent)
        if !model.choices.valuation {
            caption("Current value and valuation details will remain unchanged.")
        }
    }

    /// No per-unit estimate could be established: nothing can be applied.
    @ViewBuilder
    private func unclearValuation(_ v: ItemAnalysisReview.Valuation) -> some View {
        Label("No estimate to apply", systemImage: "exclamationmark.circle")
            .font(Theme.secondaryFont.weight(.semibold))
            .foregroundStyle(Theme.text)
        Text(unclearReason(v))
            .font(Theme.secondaryFont)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
        caption("Current value and valuation details will remain unchanged. Check the item's quantity and description, or add clearer details, and analyze again.")
    }

    private func unclearReason(_ v: ItemAnalysisReview.Valuation) -> String {
        let described = v.unit.map { " The AI described its estimate as “\($0)”." } ?? ""
        switch v.basis {
        case .ambiguous(.conflictingCount(let count)):
            return "LTC could not establish a reliable estimate for one item: the AI priced \(count) items together, but this item's quantity is \(v.quantity).\(described)"
        case .ambiguous(.unstated):
            return "LTC could not establish a reliable estimate for one item: the AI did not say whether its estimate is for one item or all \(v.quantity)."
        default:
            return "LTC could not establish a reliable estimate for one item from the AI's answer.\(described)"
        }
    }

    @ViewBuilder
    private func explanationText(_ explanation: String?) -> some View {
        if let explanation {
            Text(explanation)
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.text)
                .lineLimit(showFullExplanation ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if explanation.count > 140 { moreButton($showFullExplanation) }
        }
    }

    private func amountRow(_ label: String, _ amount: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            caption(label)
            Spacer(minLength: 12)
            Text(amount)
                .font(emphasized ? Theme.bodyFont.weight(.semibold) : Theme.secondaryFont)
                .foregroundStyle(emphasized ? Theme.text : Theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private var actionBar: some View {
        VStack(spacing: 8) {
            Button(action: onApply) {
                Text(model.choices.isEmpty ? "Nothing Selected" : "Apply Selected")
                    .font(Theme.bodyFont.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(model.choices.isEmpty ? Theme.textSecondary.opacity(0.35) : Theme.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(model.choices.isEmpty)

            Button(action: onKeepCurrent) {
                Text("Keep Current Information")
                    .font(Theme.bodyFont.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Theme.text)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Closes without changing the item.")
        }
        .padding(.horizontal, Theme.spacing.large)
        .padding(.vertical, Theme.spacing.small)
        .background(.thinMaterial)
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Text(title).ltcSectionHeaderStyle()
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .ltcCardBackground()
        }
    }

    private func comparison(label: String, current: String, proposed: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            caption("\(label) now")
            Text(current).font(Theme.secondaryFont).foregroundStyle(Theme.text)
            if current != proposed && !proposed.isEmpty {
                caption("Suggested")
                Text(proposed).font(Theme.bodyFont.weight(.semibold)).foregroundStyle(Theme.text)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.secondaryFont)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func moreButton(_ flag: Binding<Bool>) -> some View {
        Button(flag.wrappedValue ? "Show less" : "Show more") {
            withAnimation(.easeInOut(duration: 0.2)) { flag.wrappedValue.toggle() }
        }
        .font(Theme.secondaryFont.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .buttonStyle(.plain)
    }
}
