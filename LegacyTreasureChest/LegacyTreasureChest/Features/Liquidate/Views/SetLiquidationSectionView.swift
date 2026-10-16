//
//  SetLiquidationSectionView.swift
//  LegacyTreasureChest
//
//  Production-facing Liquidation panel for a set (LTCItemSet).
//  - Generates Brief (backend-first via LiquidationAIService)
//  - Choosing an approach creates a Plan (backend-first); the Plan is worked via LiquidationWorkflow
//  - Persists to SwiftData: LiquidationState -> BriefRecord / PlanRecord
//

import SwiftUI
import SwiftData

struct SetLiquidationSectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var itemSet: LTCItemSet

    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isGeneratingBrief: Bool = false
    @State private var isGeneratingPlan: Bool = false
    /// The homeowner chose to plan before the Brief's missing details are confirmed.
    @State private var isCreatingPlanAnyway: Bool = false
    /// The approach choices are open while a Plan already exists.
    @State private var isChoosingApproach: Bool = false
    /// A replacement, regeneration, or Brief update awaiting confirmation.
    @State private var pendingChange: LiquidationPendingChange?
    /// The Plan whose outcome form is open.
    @State private var outcomePlan: LiquidationPlanRecord?
    /// Find Help opened from a checklist step.
    @State private var findHelpRequest: LiquidationFindHelpRequest?
    /// The Brief opened from a "View Brief" step.
    @State private var reviewBrief: LiquidationBriefRecord?

    @StateObject private var consentGate = AIConsentGate()

    private let liquidationAI = LiquidationAIService()

    private var owner: LiquidationOwner { .itemSet(itemSet) }
    private var isBusy: Bool { isGeneratingBrief || isGeneratingPlan }

    var body: some View {
        let briefRecord = LiquidationWorkflow.activeBrief(itemSet.liquidationState)
        let planRecord = LiquidationWorkflow.activePlan(itemSet.liquidationState)

        Form {
            Section {
                headerRow(planRecord: planRecord)

                Button {
                    if planRecord != nil {
                        pendingChange = .updateBrief
                    } else {
                        startBriefGeneration()
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isGeneratingBrief {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isGeneratingBrief ? "Generating Brief…" : "Generate / Update Brief")
                    }
                }
                .disabled(isBusy)

                if isGeneratingBrief {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Working… this can take a few seconds.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 6)
                }

                if let brief = briefRecord {
                    briefSummaryCard(briefRecord: brief)

                    Divider().padding(.vertical, 4)

                    approachChooser(briefRecord: brief, hasPlan: planRecord != nil)
                } else {
                    Text("No liquidation brief yet.")
                        .foregroundStyle(.secondary)
                }

                if isGeneratingPlan {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Generating plan…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 6)
                }

                if let plan = planRecord {
                    Divider().padding(.vertical, 4)
                    planPanel(plan)
                        .id(plan.persistentModelID)

                    if _isDebugAssertConfiguration() && FeatureFlags().showDebugInfo {

                        Button(role: .destructive) {
                            deletePlan(plan, from: itemSet)
                        } label: {
                            Label("Delete Plan (Debug)", systemImage: "trash")
                        }
                        .padding(.top, 6)
                    }
                } else {
                    Text("No Plan yet. Generate a Brief, then choose an approach.")
                        .foregroundStyle(.secondary)
                }

                if let message {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }

            } header: {
                Text("Liquidation")
                    .ltcSectionHeaderStyle()
            } footer: {
                Text("Liquidation is a workflow: generate a Brief, choose an approach, then work through a checklist Plan.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Liquidate Set")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $outcomePlan) { plan in
            LiquidationOutcomeForm(
                planTitle: UserFacingTerms.Liquidation.planTitle(plan.chosenPath),
                existing: LiquidationWorkflow.checklist(of: plan)?.outcome,
                currencyCode: Locale.current.currency?.identifier ?? "USD"
            ) { outcome in
                saveOutcome(outcome, in: plan)
            }
        }
        .sheet(item: $reviewBrief) { record in
            if let dto = LiquidationWorkflow.brief(of: record) {
                LiquidationBriefReviewSheet(dto: dto, createdAt: record.createdAt)
            }
        }
        .navigationDestination(item: $findHelpRequest) { request in
            LiquidationFindHelpDestination(owner: owner, request: request)
        }
        .alert(
            pendingChange.map { change in
                change.title(currentPlanTitle: planRecord.map { UserFacingTerms.Liquidation.planTitle($0.chosenPath) } ?? "Plan")
            } ?? "",
            isPresented: Binding(get: { pendingChange != nil }, set: { if !$0 { pendingChange = nil } }),
            presenting: pendingChange
        ) { change in
            Button(change.confirmTitle, role: change.isDestructive ? .destructive : nil) {
                perform(change)
            }
            Button("Cancel", role: .cancel) {}
        } message: { change in
            if let planRecord {
                Text(change.message(currentPlan: planRecord))
            }
        }
        .aiConsentSheet(consentGate)
    }

    // MARK: - Header

    @ViewBuilder
    private func headerRow(planRecord: LiquidationPlanRecord?) -> some View {
        HStack {
            Text("Status:")
                .foregroundStyle(.secondary)

            Text(UserFacingTerms.Liquidation.statusName(owner.status))
                .font(.subheadline.weight(.semibold))

            Spacer()

            if let plan = planRecord {
                Text("Approach: \(plan.chosenPath.displayName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
    }

    // MARK: - Generate Brief

    private func startBriefGeneration() {
        Task { await consentGate.perform { await generateBrief() } }
    }

    /// Saves a new Brief; an existing Plan and its progress are kept.
    @MainActor
    private func generateBrief() async {
        guard !isBusy else { return }
        message = nil
        errorMessage = nil
        isGeneratingBrief = true
        defer { isGeneratingBrief = false }

        let hadPlan = LiquidationWorkflow.activePlan(itemSet.liquidationState) != nil

        do {
            let dto = try await liquidationAI.generateBriefDTO(
                for: itemSet,
                goal: .balanced,
                constraints: nil,
                locationHint: nil
            )
            try LiquidationWorkflow.recordNewBrief(dto, owner: owner, context: modelContext)
            isCreatingPlanAnyway = false
            message = hadPlan ? "Brief updated. Your current Plan is unchanged." : "Brief updated."
        } catch {
            errorMessage = "Brief failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Brief UI

    @ViewBuilder
    private func briefSummaryCard(briefRecord: LiquidationBriefRecord) -> some View {
        if let dto = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) {
            LiquidationBriefSummaryView(
                presentation: LiquidationBriefPresentation(dto: dto),
                createdAt: briefRecord.createdAt,
                hasFullBriefSheet: false
            )
        } else {
            Text("Could not decode brief payload JSON.")
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }

    /// More Information Needed no longer blocks a Plan; it asks for an explicit
    /// "Create a Plan Anyway" before the four approaches are offered.
    private func briefNeedsMoreInformation(_ briefRecord: LiquidationBriefRecord) -> Bool {
        LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON)?
            .recommendedPath == .needsInfo
    }

    @ViewBuilder
    private func needsInfoCard(from briefRecord: LiquidationBriefRecord) -> some View {
        if let dto = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) {
            VStack(alignment: .leading, spacing: 8) {
                Text("The Brief needs more information before it can recommend an approach.")
                    .font(.subheadline.weight(.semibold))
                Text("Add the missing details below to the set or its items, then update the Brief, or create a Plan anyway.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(dto.missingDetails.prefix(8).map(UserFacingTerms.Liquidation.customerText), id: \.self) { s in
                    Text("• \(s)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Choosing an approach

    /// Without a Plan the approaches are shown; with one, they open only from
    /// "Change Approach…" or "Create a New Plan", and choosing asks first.
    @ViewBuilder
    private func approachChooser(briefRecord: LiquidationBriefRecord, hasPlan: Bool) -> some View {
        let needsInfo = briefNeedsMoreInformation(briefRecord)
        if needsInfo {
            needsInfoCard(from: briefRecord)
        }
        if !hasPlan || isChoosingApproach {
            if needsInfo && !isCreatingPlanAnyway {
                Button(UserFacingTerms.Liquidation.createPlanAnyway) {
                    isCreatingPlanAnyway = true
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            } else {
                if needsInfo {
                    Text(UserFacingTerms.Liquidation.createPlanAnywayExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                pathButtonsRow(briefRecord: briefRecord, hasPlan: hasPlan)
            }
            if hasPlan {
                Button("Keep Current Plan") {
                    isChoosingApproach = false
                    isCreatingPlanAnyway = false
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
    }

    @ViewBuilder
    private func pathButtonsRow(briefRecord: LiquidationBriefRecord, hasPlan: Bool) -> some View {
        if let dto = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) {
            LiquidationApproachPicker(
                recommendedPath: dto.recommendedPath,
                isDisabled: isBusy
            ) { chosen in
                if hasPlan {
                    pendingChange = .replace(chosen)
                } else {
                    startPlanGeneration(chosen)
                }
            }
        }
    }

    // MARK: - Plan creation

    private func perform(_ change: LiquidationPendingChange) {
        switch change {
        case .replace(let path), .regenerate(let path):
            startPlanGeneration(path)
        case .updateBrief:
            startBriefGeneration()
        }
    }

    private func startPlanGeneration(_ chosen: LiquidationPath) {
        Task { await consentGate.perform { await createPlan(chosen: chosen) } }
    }

    /// Generates from the current Brief; the current Plan stays active unless
    /// generation succeeds. Repeated taps are ignored while a Plan is generating.
    @MainActor
    private func createPlan(chosen: LiquidationPath) async {
        guard !isBusy else { return }
        message = nil
        errorMessage = nil

        let state = itemSet.liquidationState
        let hadPlan = LiquidationWorkflow.activePlan(state) != nil
        guard let briefRecord = LiquidationWorkflow.activeBrief(state),
              let briefDTO = LiquidationWorkflow.brief(of: briefRecord) else {
            errorMessage = "Generate a Brief before creating a Plan."
            return
        }

        isGeneratingPlan = true
        defer { isGeneratingPlan = false }

        do {
            // Backend-first; the service uses the basic Plan only when offline or unavailable.
            try await LiquidationWorkflow.createPlan(
                owner: owner,
                chosen: chosen,
                briefRecord: briefRecord,
                brief: briefDTO,
                context: modelContext
            ) {
                try await liquidationAI.generatePlanChecklistDTO(for: itemSet, chosenPath: chosen, briefDTO: briefDTO)
            }
            isCreatingPlanAnyway = false
            isChoosingApproach = false
            message = "Created your \(UserFacingTerms.Liquidation.planTitle(chosen))."
        } catch {
            errorMessage = hadPlan
                ? "Plan failed: \(error.localizedDescription) Your current Plan is unchanged."
                : "Plan failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Plan

    @ViewBuilder
    private func planPanel(_ plan: LiquidationPlanRecord) -> some View {
        if let checklist = LiquidationWorkflow.checklist(of: plan) {
            LiquidationPlanPanel(
                planRecord: plan,
                checklist: checklist,
                earlierBriefDate: LiquidationWorkflow.earlierBriefDate(for: plan, in: itemSet.liquidationState),
                isBusy: isBusy,
                onToggle: { id, done in setStep(id, completed: done, in: plan) },
                onAction: { action, step in handle(action, step: step, plan: plan) },
                onKeepPlan: { keepPlan(plan) },
                onCreateNewPlan: { isChoosingApproach = true },
                onChangeApproach: { isChoosingApproach = true },
                onRegenerate: { pendingChange = .regenerate(plan.chosenPath) }
            )
        } else {
            Text("Could not decode plan checklist JSON.")
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }

    private func handle(_ action: LiquidationStepAction, step: LiquidationChecklistItemDTO?, plan: LiquidationPlanRecord) {
        switch action {
        case .findHelp, .findSpecialtyHelp:
            // Opening Find Help never ticks the step; the homeowner does that on return.
            findHelpRequest = LiquidationWorkflow.findHelpRequest(plan: plan, step: step, action: action)
        case .viewBrief:
            reviewBrief = LiquidationWorkflow.originatingBrief(of: plan, in: itemSet.liquidationState)
        case .recordOutcome:
            outcomePlan = plan
        }
    }

    @MainActor
    private func setStep(_ id: UUID, completed: Bool, in plan: LiquidationPlanRecord) {
        message = nil
        errorMessage = nil
        do {
            try LiquidationWorkflow.setStep(id, completed: completed, in: plan, owner: owner, context: modelContext)
        } catch {
            errorMessage = "Failed saving checklist: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func saveOutcome(_ outcome: LiquidationPlanOutcomeDTO, in plan: LiquidationPlanRecord) {
        errorMessage = nil
        do {
            try LiquidationWorkflow.saveOutcome(outcome, in: plan, owner: owner, context: modelContext)
            message = "Outcome saved: \(outcome.result.displayName)."
        } catch {
            errorMessage = "Failed saving outcome: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func keepPlan(_ plan: LiquidationPlanRecord) {
        guard let brief = LiquidationWorkflow.activeBrief(itemSet.liquidationState) else { return }
        do {
            try LiquidationWorkflow.keepPlan(plan, with: brief, context: modelContext)
            isChoosingApproach = false
        } catch {
            errorMessage = "Failed saving your choice: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete plan

    @MainActor
    private func deletePlan(_ plan: LiquidationPlanRecord, from itemSet: LTCItemSet) {
        message = nil
        errorMessage = nil

        guard let state = itemSet.liquidationState else { return }

        do {
            modelContext.delete(plan)
            state.plans.removeAll(where: { $0.persistentModelID == plan.persistentModelID })

            state.status = (LiquidationWorkflow.activeBrief(state) == nil) ? .notStarted : .hasBrief
            state.updatedAt = .now
            itemSet.updatedAt = .now

            try modelContext.save()
            message = "Deleted plan."
        } catch {
            errorMessage = "Failed to delete plan: \(error.localizedDescription)"
        }
    }
}
