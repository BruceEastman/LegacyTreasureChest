//
//  LiquidationPlanPanel.swift
//  LegacyTreasureChest
//
//  The Plan as the homeowner works it, shared by the Item and Set Liquidate
//  screens (Set Execute Plan reuses the pieces): the chosen approach, progress,
//  actionable steps, the outcome, and deliberate change/regenerate controls.
//  All rules live in LiquidationWorkflow; this file only presents them.
//

import SwiftUI

struct LiquidationPlanPanel: View {
    let planRecord: LiquidationPlanRecord
    let checklist: LiquidationPlanChecklistDTO
    /// The Plan was made from an earlier Brief and has not been kept with the current one.
    let earlierBriefDate: Date?
    let isBusy: Bool

    let onToggle: (UUID, Bool) -> Void
    let onAction: (LiquidationStepAction, LiquidationChecklistItemDTO?) -> Void
    let onKeepPlan: () -> Void
    let onCreateNewPlan: () -> Void
    let onChangeApproach: () -> Void
    let onRegenerate: () -> Void
    /// Change or remove the business chosen for a group ("main", or a closet-lot pile).
    var onChangeProvider: (String) -> Void = { _ in }
    var onRemoveProvider: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LiquidationPlanContextHeader(
                chosenPath: planRecord.chosenPath,
                status: planRecord.status,
                checklist: checklist
            )

            LiquidationPlanProgressView(checklist: checklist)

            if let earlierBriefDate {
                earlierBriefNotice(earlierBriefDate)
            }

            ForEach(checklist.items.sorted(by: { $0.order < $1.order })) { step in
                LiquidationChecklistStepRow(
                    step: step,
                    isDisabled: isBusy,
                    onToggle: { onToggle(step.id, $0) },
                    onAction: { onAction($0, step) }
                )
            }

            ForEach(checklist.selectedProviders ?? [], id: \.group) { selection in
                VStack(alignment: .leading, spacing: 2) {
                    if selection.group != LiquidationProviderSelectionDTO.mainGroup {
                        Text(Self.pileName(selection.group))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    SavedProviderRow(
                        selection: selection,
                        isDisabled: isBusy,
                        onChange: { onChangeProvider(selection.group) },
                        onRemove: { onRemoveProvider(selection.group) }
                    )
                }
            }

            Divider()

            LiquidationOutcomeRow(outcome: checklist.outcome, isDisabled: isBusy) {
                onAction(.recordOutcome, nil)
            }

            Divider()

            // Side by side when they fit; stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { planControls }
                VStack(alignment: .leading, spacing: 8) { planControls }
            }
            .disabled(isBusy)
        }
        .padding(.vertical, 6)
    }

    static func pileName(_ group: String) -> String {
        switch group {
        case "luxury": return "Luxury / designer pile"
        case "contemporary": return "Contemporary pile"
        case "donate": return "Donation pile"
        case "discard": return "Discard / recycle pile"
        default: return "Other steps"
        }
    }

    @ViewBuilder
    private var planControls: some View {
        Button("Change Approach…", action: onChangeApproach)
            .buttonStyle(.bordered)
            .fixedSize()
        if planRecord.chosenPath != .needsInfo {
            Button("Regenerate Plan…", action: onRegenerate)
                .buttonStyle(.bordered)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var keepOrReplaceControls: some View {
        Button("Keep This Plan", action: onKeepPlan)
            .buttonStyle(.bordered)
            .fixedSize()
        Button("Create a New Plan", action: onCreateNewPlan)
            .buttonStyle(.bordered)
            .fixedSize()
    }

    private func earlierBriefNotice(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Plan is based on an earlier Brief from \(date.formatted(date: .abbreviated, time: .shortened)). Your progress is unchanged.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { keepOrReplaceControls }
                VStack(alignment: .leading, spacing: 8) { keepOrReplaceControls }
            }
            .disabled(isBusy)
        }
        .padding(10)
        .background(Theme.accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// "2 of 5 steps done", with a reminder that the outcome, not the checkboxes,
/// finishes a Plan v2.
struct LiquidationPlanProgressView: View {
    let checklist: LiquidationPlanChecklistDTO

    var body: some View {
        let progress = LiquidationWorkflow.progress(checklist)
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress.fraction)
                .accessibilityLabel("Plan progress")
                .accessibilityValue(progress.summary)
            Text(progress.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if progress.allDone && checklist.outcome == nil && checklist.context != nil {
                Text("All steps are done. Record the outcome to finish this Plan.")
                    .font(.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One step: checkbox, wording and detail, and at most one contextual action.
struct LiquidationChecklistStepRow: View {
    let step: LiquidationChecklistItemDTO
    let isDisabled: Bool
    let onToggle: (Bool) -> Void
    let onAction: (LiquidationStepAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { step.isCompleted }, set: onToggle)) {
                LiquidationChecklistStepLabel(item: step)
            }
            .disabled(isDisabled)

            if let action = LiquidationStepAction(step: step) {
                Button {
                    onAction(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isDisabled)
            }
        }
    }
}

/// The application-owned outcome entry at the end of every Plan (never a
/// generated step, so it cannot be duplicated).
struct LiquidationOutcomeRow: View {
    let outcome: LiquidationPlanOutcomeDTO?
    let isDisabled: Bool
    let onRecord: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let outcome {
                Text("Outcome: \(outcome.result.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Self.detailLines(outcome), id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Edit Outcome", action: onRecord)
                    .buttonStyle(.bordered)
                    .disabled(isDisabled)
            } else {
                Text("When it is sold, donated, or otherwise settled, record what actually happened.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    onRecord()
                } label: {
                    Label(LiquidationStepAction.recordOutcome.title, systemImage: LiquidationStepAction.recordOutcome.systemImage)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled)
            }
        }
    }

    static func detailLines(_ outcome: LiquidationPlanOutcomeDTO) -> [String] {
        var lines: [String] = []
        if let amount = outcome.amountReceived {
            lines.append("Actually received: \(CurrencyFormat.dollars(amount))")
        }
        if let who = outcome.counterparty, let label = outcome.result.counterpartyLabel {
            lines.append("\(label): \(who)")
        }
        lines.append("Date: \(outcome.date.formatted(date: .abbreviated, time: .omitted))")
        if let notes = outcome.notes {
            lines.append(notes)
        }
        return lines
    }
}

/// Where a checklist's Find Help action leads: the shared Find Help screen,
/// told which Plan, step, pile, and approach it serves.
struct LiquidationFindHelpDestination: View {
    let owner: LiquidationOwner
    let request: LiquidationFindHelpRequest

    var body: some View {
        DispositionPartnersView(owner: owner, request: request)
    }
}

/// A read-only Brief for screens without their own Full Brief sheet.
struct LiquidationBriefReviewSheet: View {
    let dto: LiquidationBriefDTO
    let createdAt: Date

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LiquidationBriefSummaryView(
                    presentation: LiquidationBriefPresentation(dto: dto),
                    createdAt: createdAt,
                    hasFullBriefSheet: false
                )
                .padding()
            }
            .navigationTitle("Brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A Plan or Brief change that waits for the homeowner's confirmation.
enum LiquidationPendingChange: Identifiable {
    /// Create a Plan for a different approach, replacing the current one.
    case replace(LiquidationPath)
    /// Create a fresh Plan for the same approach from the latest Brief.
    case regenerate(LiquidationPath)
    /// Generate a new Brief while a Plan exists (the Plan is kept).
    case updateBrief

    var id: String {
        switch self {
        case .replace(let p): return "replace.\(p.rawValue)"
        case .regenerate(let p): return "regenerate.\(p.rawValue)"
        case .updateBrief: return "updateBrief"
        }
    }

    func title(currentPlanTitle: String) -> String {
        switch self {
        case .replace: return "Replace your \(currentPlanTitle)?"
        case .regenerate: return "Regenerate your \(currentPlanTitle)?"
        case .updateBrief: return "Update the Brief?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .replace: return "Replace Plan"
        case .regenerate: return "Regenerate Plan"
        case .updateBrief: return "Update Brief"
        }
    }

    var isDestructive: Bool {
        if case .updateBrief = self { return false }
        return true
    }

    func message(currentPlan: LiquidationPlanRecord) -> String {
        switch self {
        case .replace(let path), .regenerate(let path):
            return LiquidationWorkflow.replacementMessage(
                current: currentPlan,
                newPlanTitle: UserFacingTerms.Liquidation.planTitle(path)
            )
        case .updateBrief:
            return "Your \(UserFacingTerms.Liquidation.planTitle(currentPlan.chosenPath)) and its progress stay exactly as they are. Afterwards you can keep it or create a new Plan."
        }
    }
}
