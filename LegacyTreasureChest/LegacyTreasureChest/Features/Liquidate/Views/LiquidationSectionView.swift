//
//  LiquidationSectionView.swift
//  LegacyTreasureChest
//
//  Production-facing Liquidation panel for an item.
//  - Generates Brief (backend-first via LiquidationAIService)
//  - Allows choosing a path and generating a Plan (backend-first)
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

    // NEW: brief detail presentation
    @State private var isBriefDetailPresented: Bool = false
    @State private var briefDetailDTO: LiquidationBriefDTO?
    @State private var briefDetailTimestamp: Date?

    @StateObject private var consentGate = AIConsentGate()

    private let liquidationAI = LiquidationAIService()

    var body: some View {
        Form {
            Section {
                headerRow()

                Button {
                    Task { await consentGate.perform { await generateBrief(for: item) } }
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
                .disabled(isGeneratingBrief || isGeneratingPlan)

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

                if let brief = latestActiveBriefRecord(for: item) {
                    briefSummaryCard(briefRecord: brief)

                    // NEW: view full brief action
                    Button {
                        presentFullBrief(from: brief)
                    } label: {
                        Label("View Full Brief", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGeneratingBrief || isGeneratingPlan)
                    .padding(.top, 6)

                    Divider().padding(.vertical, 4)

                    if shouldBlockPlanCreation(from: brief) {
                        needsInfoCard(from: brief)
                    } else {
                        pathButtonsRow(item: item, briefRecord: brief)
                    }
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

                if let plan = latestActivePlanRecord(for: item) {
                    Divider().padding(.vertical, 4)
                    planChecklistEditor(planRecord: plan, item: item)
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

    // MARK: - SwiftData helpers

    @MainActor
    private func ensureItemState(_ item: LTCItem) -> LiquidationState {
        if let existing = item.liquidationState { return existing }

        let state = LiquidationState(
            ownerType: .item,
            status: .notStarted,
            createdAt: .now,
            updatedAt: .now
        )
        state.item = item
        item.liquidationState = state

        modelContext.insert(state)
        return state
    }

    private func latestActiveBriefRecord(for item: LTCItem) -> LiquidationBriefRecord? {
        guard let state = item.liquidationState else { return nil }
        if let active = state.briefs.first(where: { $0.isActive }) { return active }
        return state.briefs.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    private func latestActivePlanRecord(for item: LTCItem) -> LiquidationPlanRecord? {
        guard let state = item.liquidationState else { return nil }
        if let active = state.plans.first(where: { $0.isActive }) { return active }
        return state.plans.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    // MARK: - Generate Brief

    @MainActor
    private func generateBrief(for item: LTCItem) async {
        message = nil
        errorMessage = nil
        isGeneratingBrief = true

        item.disposition = .liquidate
        item.updatedAt = .now

        let state = ensureItemState(item)

        do {
            // v1: text-only (no image), same as Sandbox.
            let dto = try await liquidationAI.generateBriefDTO(
                for: item,
                goal: .balanced,
                constraints: nil,
                locationHint: nil,
                imageData: nil
            )

            let payloadData = try LiquidationJSONCoding.encode(dto)

            // Deactivate existing brief records
            for i in state.briefs.indices { state.briefs[i].isActive = false }

            let rec = LiquidationBriefRecord(
                createdAt: .now,
                isActive: true,
                inputFingerprint: nil,
                payloadVersion: "brief.v1",
                aiProvider: dto.aiProvider ?? "unknown",
                aiModel: dto.aiModel ?? "unknown",
                payloadJSON: payloadData
            )

            rec.state = state
            modelContext.insert(rec)
            state.briefs.append(rec)

            state.status = .hasBrief
            state.updatedAt = .now

            item.liquidationStatus = .hasBrief
            item.updatedAt = .now

            try modelContext.save()
            message = "Brief updated."
        } catch {
            errorMessage = "Brief failed: \(error.localizedDescription)"
        }

        isGeneratingBrief = false
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

    private func shouldBlockPlanCreation(from briefRecord: LiquidationBriefRecord) -> Bool {
        guard let dto = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) else {
            return true
        }
        return dto.recommendedPath == .needsInfo
    }

    @ViewBuilder
    private func needsInfoCard(from briefRecord: LiquidationBriefRecord) -> some View {
        if let dto = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) {
            VStack(alignment: .leading, spacing: 8) {
                Text("More information is needed before creating a Plan.")
                    .font(.subheadline.weight(.semibold))
                Text("Add the missing details below to the item, then update the Brief.")
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

    // MARK: - Plan creation

    @ViewBuilder
    private func pathButtonsRow(item: LTCItem, briefRecord: LiquidationBriefRecord) -> some View {
        if let dto = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) {
            LiquidationApproachPicker(
                recommendedPath: dto.recommendedPath,
                isDisabled: isGeneratingBrief || isGeneratingPlan
            ) { chosen in
                Task { await consentGate.perform { await createOrReplacePlan(item: item, briefRecord: briefRecord, chosen: chosen) } }
            }
        }
    }

    @MainActor
    private func createOrReplacePlan(item: LTCItem, briefRecord: LiquidationBriefRecord, chosen: LiquidationPath) async {
        message = nil
        errorMessage = nil
        isGeneratingPlan = true

        let state = ensureItemState(item)

        do {
            guard let briefDTO = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) else {
                throw NSError(
                    domain: "LiquidationSectionView",
                    code: 2101,
                    userInfo: [NSLocalizedDescriptionKey: "Could not decode LiquidationBriefDTO from brief payload."]
                )
            }

            // Backend-first plan generation with local fallback inside the service
            let checklist = try await liquidationAI.generatePlanChecklistDTO(
                for: item,
                chosenPath: chosen,
                briefDTO: briefDTO
            )

            let checklistData = try LiquidationJSONCoding.encode(checklist)

            // Deactivate existing plan records
            for i in state.plans.indices { state.plans[i].isActive = false }

            let planRecord = LiquidationPlanRecord(
                createdAt: .now,
                updatedAt: .now,
                isActive: true,
                chosenPath: chosen,
                status: .notStarted,
                payloadVersion: "plan.v1",
                payloadJSON: checklistData
            )
            planRecord.state = state

            modelContext.insert(planRecord)
            state.plans.append(planRecord)

            // Update item workflow flags
            item.selectedLiquidationPath = chosen
            item.liquidationStatus = .inProgress
            item.disposition = .liquidate
            item.updatedAt = .now

            state.status = .inProgress
            state.updatedAt = .now

            try modelContext.save()
            message = "Created your \(UserFacingTerms.Liquidation.planTitle(chosen))."
        } catch {
            errorMessage = "Plan failed: \(error.localizedDescription)"
        }

        isGeneratingPlan = false
    }

    // MARK: - Plan checklist UI

    @ViewBuilder
    private func planChecklistEditor(planRecord: LiquidationPlanRecord, item: LTCItem) -> some View {
        if let checklist = LiquidationJSONCoding.tryDecode(LiquidationPlanChecklistDTO.self, from: planRecord.payloadJSON) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(UserFacingTerms.Liquidation.planTitle(planRecord.chosenPath))
                        .font(.headline)
                    Spacer()
                    Text(UserFacingTerms.Liquidation.statusName(planRecord.status))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(checklist.items.sorted(by: { $0.order < $1.order })) { checklistItem in
                    Toggle(isOn: Binding(
                        get: { checklistItem.isCompleted },
                        set: { newValue in
                            toggleChecklistItem(
                                planRecord: planRecord,
                                item: item,
                                checklistItemID: checklistItem.id,
                                newValue: newValue
                            )
                        }
                    )) {
                        Text("\(checklistItem.order). \(checklistItem.text)")
                            .font(.subheadline)
                    }
                }

                let pct = completionPercent(checklist)
                ProgressView(value: pct) {
                    Text("Progress")
                }
                .padding(.top, 6)

                Text("Completion: \(Int(pct * 100))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        } else {
            Text("Could not decode plan checklist JSON.")
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }

    @MainActor
    private func toggleChecklistItem(
        planRecord: LiquidationPlanRecord,
        item: LTCItem,
        checklistItemID: UUID,
        newValue: Bool
    ) {
        message = nil
        errorMessage = nil

        guard var checklist = LiquidationJSONCoding.tryDecode(LiquidationPlanChecklistDTO.self, from: planRecord.payloadJSON) else {
            errorMessage = "Could not decode plan checklist JSON."
            return
        }

        guard let idx = checklist.items.firstIndex(where: { $0.id == checklistItemID }) else {
            errorMessage = "Checklist item not found."
            return
        }

        checklist.items[idx].isCompleted = newValue
        checklist.items[idx].completedAt = newValue ? .now : nil

        do {
            let data = try LiquidationJSONCoding.encode(checklist)
            planRecord.payloadJSON = data
            planRecord.updatedAt = .now

            let pct = completionPercent(checklist)
            if pct >= 1.0, !checklist.items.isEmpty {
                planRecord.statusRaw = PlanStatus.completed.rawValue
                item.liquidationStatus = .completed
            } else if pct > 0 {
                planRecord.statusRaw = PlanStatus.inProgress.rawValue
                item.liquidationStatus = .inProgress
            } else {
                planRecord.statusRaw = PlanStatus.notStarted.rawValue
                item.liquidationStatus = .inProgress
            }

            item.updatedAt = .now
            try modelContext.save()
        } catch {
            errorMessage = "Failed saving checklist: \(error.localizedDescription)"
        }
    }

    private func completionPercent(_ checklist: LiquidationPlanChecklistDTO) -> Double {
        guard !checklist.items.isEmpty else { return 0 }
        let completed = checklist.items.filter { $0.isCompleted }.count
        return Double(completed) / Double(checklist.items.count)
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
            item.liquidationStatus = (latestActiveBriefRecord(for: item) == nil) ? .notStarted : .hasBrief
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
