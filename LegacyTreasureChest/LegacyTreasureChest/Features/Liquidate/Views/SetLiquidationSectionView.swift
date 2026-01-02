//
//  SetLiquidationSectionView.swift
//  LegacyTreasureChest
//
//  Production-facing Liquidation panel for a set (LTCItemSet).
//  - Generates Brief (backend-first via LiquidationAIService)
//  - Allows choosing a path and generating a Plan (backend-first)
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

    private let liquidationAI = LiquidationAIService()

    var body: some View {
        Form {
            Section {
                headerRow()

                Button {
                    Task { await generateBrief(for: itemSet) }
                } label: {
                    Label(isGeneratingBrief ? "Generating Brief…" : "Generate / Update Brief", systemImage: "sparkles")
                }
                .disabled(isGeneratingBrief || isGeneratingPlan)

                if let brief = latestActiveBriefRecord(for: itemSet) {
                    briefSummaryCard(briefRecord: brief)

                    Divider().padding(.vertical, 4)

                    if shouldBlockPlanCreation(from: brief) {
                        needsInfoCard(from: brief)
                    } else {
                        pathButtonsRow(itemSet: itemSet, briefRecord: brief)
                    }
                } else {
                    Text("No liquidation brief yet.")
                        .foregroundStyle(.secondary)
                }

                if let plan = latestActivePlanRecord(for: itemSet) {
                    Divider().padding(.vertical, 4)
                    planChecklistEditor(planRecord: plan, itemSet: itemSet)
                        .id(plan.persistentModelID)

                    Button(role: .destructive) {
                        deletePlan(plan, from: itemSet)
                    } label: {
                        Label("Delete Plan (Debug)", systemImage: "trash")
                    }
                    .padding(.top, 6)
                } else {
                    Text("No plan yet. Generate a brief, then choose a path.")
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
                Text("Liquidation is a workflow: generate a brief, choose a path, then execute a checklist plan.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Liquidate Set")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    @ViewBuilder
    private func headerRow() -> some View {
        HStack {
            Text("Status:")
                .foregroundStyle(.secondary)

            Text(itemSet.liquidationState?.status.rawValue ?? LiquidationStatus.notStarted.rawValue)
                .font(.subheadline.weight(.semibold))

            Spacer()

            if let plan = latestActivePlanRecord(for: itemSet) {
                Text("Path: \(plan.chosenPathRaw)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
    }

    // MARK: - SwiftData helpers

    @MainActor
    private func ensureSetState(_ itemSet: LTCItemSet) -> LiquidationState {
        if let existing = itemSet.liquidationState { return existing }

        let state = LiquidationState(
            ownerType: .itemSet,
            status: .notStarted,
            createdAt: .now,
            updatedAt: .now
        )
        state.itemSet = itemSet
        itemSet.liquidationState = state

        modelContext.insert(state)
        return state
    }

    private func latestActiveBriefRecord(for itemSet: LTCItemSet) -> LiquidationBriefRecord? {
        guard let state = itemSet.liquidationState else { return nil }
        if let active = state.briefs.first(where: { $0.isActive }) { return active }
        return state.briefs.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    private func latestActivePlanRecord(for itemSet: LTCItemSet) -> LiquidationPlanRecord? {
        guard let state = itemSet.liquidationState else { return nil }
        if let active = state.plans.first(where: { $0.isActive }) { return active }
        return state.plans.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    // MARK: - Generate Brief

    @MainActor
    private func generateBrief(for itemSet: LTCItemSet) async {
        message = nil
        errorMessage = nil
        isGeneratingBrief = true

        let state = ensureSetState(itemSet)

        do {
            // v1: text-only set context (members summarized)
            let dto = try await liquidationAI.generateBriefDTO(
                for: itemSet,
                goal: .balanced,
                constraints: nil,
                locationHint: nil
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

            itemSet.updatedAt = .now

            try modelContext.save()
            message = "Brief updated."
        } catch {
            errorMessage = "Brief failed: \(error.localizedDescription)"
        }

        isGeneratingBrief = false
    }

    // MARK: - Brief UI

    @ViewBuilder
    private func briefSummaryCard(briefRecord: LiquidationBriefRecord) -> some View {
        if let dto = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Latest Brief")
                        .font(.headline)
                    Spacer()
                    Text(briefRecord.createdAt, style: .time)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Recommended: \(dto.recommendedPath.rawValue)")
                    .font(.subheadline)
                    .bold()

                Text(dto.reasoning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)

                if !dto.missingDetails.isEmpty {
                    Divider()
                    Text("Missing details:")
                        .font(.footnote.weight(.semibold))
                    ForEach(dto.missingDetails.prefix(6), id: \.self) { s in
                        Text("• \(s)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
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
                Text("More info needed before creating a plan.")
                    .font(.subheadline.weight(.semibold))
                Text("Update the set or its member items, then regenerate the brief.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(dto.missingDetails.prefix(8), id: \.self) { s in
                    Text("• \(s)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Plan creation

    private func pathButtonsRow(itemSet: LTCItemSet, briefRecord: LiquidationBriefRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a path to create/replace the plan:")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("Path A") { Task { await createOrReplacePlan(itemSet: itemSet, briefRecord: briefRecord, chosen: .pathA) } }
                Button("Path B") { Task { await createOrReplacePlan(itemSet: itemSet, briefRecord: briefRecord, chosen: .pathB) } }
                Button("Path C") { Task { await createOrReplacePlan(itemSet: itemSet, briefRecord: briefRecord, chosen: .pathC) } }
                Button("Donate") { Task { await createOrReplacePlan(itemSet: itemSet, briefRecord: briefRecord, chosen: .donate) } }
            }
            .buttonStyle(.bordered)
            .disabled(isGeneratingBrief || isGeneratingPlan)
        }
    }

    @MainActor
    private func createOrReplacePlan(itemSet: LTCItemSet, briefRecord: LiquidationBriefRecord, chosen: LiquidationPath) async {
        message = nil
        errorMessage = nil
        isGeneratingPlan = true

        let state = ensureSetState(itemSet)

        do {
            guard let briefDTO = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) else {
                throw NSError(
                    domain: "SetLiquidationSectionView",
                    code: 2201,
                    userInfo: [NSLocalizedDescriptionKey: "Could not decode LiquidationBriefDTO from brief payload."]
                )
            }

            let checklist = try await liquidationAI.generatePlanChecklistDTO(
                for: itemSet,
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

            state.status = .inProgress
            state.updatedAt = .now
            itemSet.updatedAt = .now

            try modelContext.save()
            message = "Plan created for path: \(chosen.rawValue)"
        } catch {
            errorMessage = "Plan failed: \(error.localizedDescription)"
        }

        isGeneratingPlan = false
    }

    // MARK: - Plan checklist UI

    @ViewBuilder
    private func planChecklistEditor(planRecord: LiquidationPlanRecord, itemSet: LTCItemSet) -> some View {
        if let checklist = LiquidationJSONCoding.tryDecode(LiquidationPlanChecklistDTO.self, from: planRecord.payloadJSON) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Plan: \(planRecord.chosenPathRaw)")
                        .font(.headline)
                    Spacer()
                    Text(planRecord.statusRaw)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(checklist.items.sorted(by: { $0.order < $1.order })) { checklistItem in
                    Toggle(isOn: Binding(
                        get: { checklistItem.isCompleted },
                        set: { newValue in
                            toggleChecklistItem(
                                planRecord: planRecord,
                                itemSet: itemSet,
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
        itemSet: LTCItemSet,
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
                itemSet.liquidationState?.status = .completed
            } else if pct > 0 {
                planRecord.statusRaw = PlanStatus.inProgress.rawValue
                itemSet.liquidationState?.status = .inProgress
            } else {
                planRecord.statusRaw = PlanStatus.notStarted.rawValue
                itemSet.liquidationState?.status = .inProgress
            }

            itemSet.updatedAt = .now
            itemSet.liquidationState?.updatedAt = .now

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
    private func deletePlan(_ plan: LiquidationPlanRecord, from itemSet: LTCItemSet) {
        message = nil
        errorMessage = nil

        guard let state = itemSet.liquidationState else { return }

        do {
            modelContext.delete(plan)
            state.plans.removeAll(where: { $0.persistentModelID == plan.persistentModelID })

            state.status = (latestActiveBriefRecord(for: itemSet) == nil) ? .notStarted : .hasBrief
            state.updatedAt = .now
            itemSet.updatedAt = .now

            try modelContext.save()
            message = "Deleted plan."
        } catch {
            errorMessage = "Failed to delete plan: \(error.localizedDescription)"
        }
    }
}
