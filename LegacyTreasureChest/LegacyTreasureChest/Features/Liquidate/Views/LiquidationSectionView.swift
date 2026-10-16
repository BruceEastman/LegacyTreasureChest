//
//  LiquidationSectionView.swift
//  LegacyTreasureChest
//
//  Production-facing Liquidation panel for an item.
//  - Generates Brief (backend-first via LiquidationAIService)
//  - Choosing an approach creates a Plan (backend-first); the Plan is worked via LiquidationWorkflow
//  - Persists to SwiftData: LiquidationState -> BriefRecord / PlanRecord
//
//  This is intentionally "minimal but real" UX.
//  We keep LiquidateSandboxView as a dev harness.
//

import SwiftUI
import SwiftData

struct LiquidationSectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var item: LTCItem

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

    // NEW: brief detail presentation
    @State private var isBriefDetailPresented: Bool = false
    @State private var briefDetailDTO: LiquidationBriefDTO?
    @State private var briefDetailTimestamp: Date?

    @StateObject private var consentGate = AIConsentGate()

    private let liquidationAI = LiquidationAIService()

    private var owner: LiquidationOwner { .item(item) }
    private var isBusy: Bool { isGeneratingBrief || isGeneratingPlan }

    var body: some View {
        let briefRecord = LiquidationWorkflow.activeBrief(item.liquidationState)
        let planRecord = LiquidationWorkflow.activePlan(item.liquidationState)

        Form {
            Section {
                headerRow()

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

                // NEW: clearer "work happening" feedback
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

                    // NEW: view full brief action
                    Button {
                        presentFullBrief(from: brief)
                    } label: {
                        Label("View Full Brief", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                    .padding(.top, 6)

                    Divider().padding(.vertical, 4)

                    approachChooser(briefRecord: brief, hasPlan: planRecord != nil)
                } else {
                    Text("No liquidation brief yet.")
                        .foregroundStyle(.secondary)
                }

                // Optional: give plan generation similar feedback
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

                    if _isDebugAssertConfiguration() {
                        Button(role: .destructive) {
                            deletePlan(plan, from: item)
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
        .navigationTitle("Liquidate")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isBriefDetailPresented) {
            LiquidationBriefDetailSheet(
                dto: briefDetailDTO,
                createdAt: briefDetailTimestamp
            )
        }
        .sheet(item: $outcomePlan) { plan in
            LiquidationOutcomeForm(
                planTitle: UserFacingTerms.Liquidation.planTitle(plan.chosenPath),
                existing: LiquidationWorkflow.checklist(of: plan)?.outcome,
                currencyCode: item.valuation?.currencyCode ?? "USD",
                suggestedCounterparty: LiquidationWorkflow.checklist(of: plan)?.selectedProviders?
                    .compactMap(\.storedDisplayName).first
            ) { outcome in
                saveOutcome(outcome, in: plan)
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
    private func headerRow() -> some View {
        HStack {
            Text("Status:")
                .foregroundStyle(.secondary)

            Text(UserFacingTerms.Liquidation.statusName(item.liquidationStatus))
                .font(.subheadline.weight(.semibold))

            Spacer()

            if let chosen = item.selectedLiquidationPath {
                Text("Approach: \(chosen.displayName)")
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

        item.disposition = .liquidate
        item.updatedAt = .now
        let hadPlan = LiquidationWorkflow.activePlan(item.liquidationState) != nil

        do {
            // v1: text-only (no image), same as Sandbox.
            let dto = try await liquidationAI.generateBriefDTO(
                for: item,
                goal: .balanced,
                constraints: nil,
                locationHint: nil,
                imageData: nil
            )
            try LiquidationWorkflow.recordNewBrief(dto, owner: owner, context: modelContext)
            isCreatingPlanAnyway = false
            message = hadPlan ? "Brief updated. Your current Plan is unchanged." : "Brief updated."
        } catch {
            errorMessage = "Brief failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Brief UI

    @MainActor
    private func presentFullBrief(from briefRecord: LiquidationBriefRecord) {
        message = nil
        errorMessage = nil

        guard let dto = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) else {
            errorMessage = "Could not decode brief payload JSON."
            return
        }

        briefDetailDTO = dto
        briefDetailTimestamp = briefRecord.createdAt
        isBriefDetailPresented = true
    }

    @ViewBuilder
    private func briefSummaryCard(briefRecord: LiquidationBriefRecord) -> some View {
        if let dto = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) {
            LiquidationBriefSummaryView(
                presentation: LiquidationBriefPresentation(dto: dto),
                createdAt: briefRecord.createdAt
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
                Text("Add the missing details below to the item, then update the Brief, or create a Plan anyway.")
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

        let state = item.liquidationState
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
                try await liquidationAI.generatePlanChecklistDTO(for: item, chosenPath: chosen, briefDTO: briefDTO)
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
                earlierBriefDate: LiquidationWorkflow.earlierBriefDate(for: plan, in: item.liquidationState),
                isBusy: isBusy,
                onToggle: { id, done in setStep(id, completed: done, in: plan) },
                onAction: { action, step in handle(action, step: step, plan: plan) },
                onKeepPlan: { keepPlan(plan) },
                onCreateNewPlan: { isChoosingApproach = true },
                onChangeApproach: { isChoosingApproach = true },
                onRegenerate: { pendingChange = .regenerate(plan.chosenPath) },
                onChangeProvider: { group in
                    findHelpRequest = LiquidationWorkflow.findHelpRequest(
                        plan: plan, step: nil, action: .findHelp,
                        group: group == LiquidationProviderSelectionDTO.mainGroup ? nil : group)
                },
                onRemoveProvider: { group in removeProvider(group, from: plan) }
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
            if let brief = LiquidationWorkflow.originatingBrief(of: plan, in: item.liquidationState) {
                presentFullBrief(from: brief)
            }
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
    private func removeProvider(_ group: String, from plan: LiquidationPlanRecord) {
        do {
            try LiquidationWorkflow.removeProvider(group: group, in: plan, owner: owner, context: modelContext)
        } catch {
            errorMessage = "Could not remove the business: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func keepPlan(_ plan: LiquidationPlanRecord) {
        guard let brief = LiquidationWorkflow.activeBrief(item.liquidationState) else { return }
        do {
            try LiquidationWorkflow.keepPlan(plan, with: brief, context: modelContext)
            isChoosingApproach = false
        } catch {
            errorMessage = "Failed saving your choice: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete plan

    @MainActor
    private func deletePlan(_ plan: LiquidationPlanRecord, from item: LTCItem) {
        message = nil
        errorMessage = nil

        guard let state = item.liquidationState else { return }

        do {
            modelContext.delete(plan)
            state.plans.removeAll(where: { $0.persistentModelID == plan.persistentModelID })

            item.selectedLiquidationPath = nil
            item.liquidationStatus = (LiquidationWorkflow.activeBrief(state) == nil) ? .notStarted : .hasBrief
            item.updatedAt = .now

            state.status = item.liquidationStatus
            state.updatedAt = .now

            try modelContext.save()
            message = "Deleted plan."
        } catch {
            errorMessage = "Failed to delete plan: \(error.localizedDescription)"
        }
    }
}

// MARK: - Full Brief Sheet (local)

private struct LiquidationBriefDetailSheet: View {
    let dto: LiquidationBriefDTO?
    let createdAt: Date?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let dto {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(dto.recommendedPath == .needsInfo ? "Status" : "Recommended")
                                    .font(.headline)
                                Spacer()
                                Text(dto.recommendedPath.displayName)
                                    .font(.headline.weight(.semibold))
                            }

                            if let specific = LiquidationBriefPresentation(dto: dto).specificRecommendation {
                                Text(specific)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.accent)
                            }

                            if let createdAt {
                                Text("Generated \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            Text("Reasoning")
                                .font(.subheadline.weight(.semibold))
                            Text(UserFacingTerms.Liquidation.customerText(dto.reasoning))
                                .font(.body)
                                .textSelection(.enabled)

                            if !dto.missingDetails.isEmpty {
                                Divider()
                                Text("Missing Details")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(dto.missingDetails.map(UserFacingTerms.Liquidation.customerText), id: \.self) { s in
                                    Text("• \(s)")
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }

                            // Optional: surface provider info if present
                            if (dto.aiProvider?.isEmpty == false) || (dto.aiModel?.isEmpty == false) {
                                Divider()
                                Text("AI Provider")
                                    .font(.subheadline.weight(.semibold))
                                VStack(alignment: .leading, spacing: 4) {
                                    if let p = dto.aiProvider, !p.isEmpty {
                                        Text("Provider: \(p)")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let m = dto.aiModel, !m.isEmpty {
                                        Text("Model: \(m)")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 10) {
                        Text("Brief not available.")
                            .font(.headline)
                        Text("We couldn't load the brief details.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Full Brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
