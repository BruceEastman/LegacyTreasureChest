//
//  LiquidateSandboxView.swift
//  LegacyTreasureChest
//
//  Debug/Sandbox view to validate Liquidate workflow end-to-end using Pattern A:
//
//  Generate Brief (local heuristic, photo-optional)
//    -> Choose Path -> Create Plan -> Execute checklist.
//
//  This is intentionally dev-only and is linked from HomeView under #if DEBUG.
//

import SwiftUI
import SwiftData

struct LiquidateSandboxView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \LTCItem.updatedAt, order: .reverse)
    private var items: [LTCItem]

    @State private var selectedItem: LTCItem?
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isGeneratingBrief: Bool = false

    private let liquidationAI = LiquidationAIService()

    var body: some View {
        NavigationStack {
            List {
                Section("1) Pick an Item") {
                    if items.isEmpty {
                        Text("No items found. Add at least one item first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Item", selection: $selectedItem) {
                            Text("Select…").tag(Optional<LTCItem>.none)
                            ForEach(items) { item in
                                Text(item.name).tag(Optional(item))
                            }
                        }
                    }

                    if let selectedItem {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Category: \(selectedItem.category)")
                                .foregroundStyle(.secondary)

                            Text("Qty: \(selectedItem.quantity) • Unit Value: \(formatCurrency(selectedItem.value))")
                                .foregroundStyle(.secondary)

                            HStack {
                                Text("Disposition: \(selectedItem.disposition.rawValue)")
                                Spacer()
                                Text("Status: \(selectedItem.liquidationStatus.rawValue)")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let selectedItem {
                    Section("2) Generate a Brief") {
                        Button {
                            Task { await generateBriefLocal(for: selectedItem) }
                        } label: {
                            Label(
                                isGeneratingBrief ? "Generating…" : "Generate Brief (Local Heuristic)",
                                systemImage: "sparkles"
                            )
                        }
                        .disabled(isGeneratingBrief)

                        if let brief = latestActiveBriefRecord(for: selectedItem) {
                            briefSummaryCard(brief, item: selectedItem)
                        } else {
                            Text("No brief yet for this item.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("3) Choose a Path → Create Plan") {
                        if let brief = latestActiveBriefRecord(for: selectedItem) {
                            pathButtonsRow(item: selectedItem, briefRecord: brief)
                        } else {
                            Text("Generate a brief first (Step 2).")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("4) Execute Plan Checklist") {
                        if let plan = latestActivePlanRecord(for: selectedItem) {
                            planChecklistEditor(planRecord: plan, item: selectedItem)
                                .id(plan.persistentModelID)

                            Button(role: .destructive) {
                                deletePlan(plan, from: selectedItem)
                            } label: {
                                Label("Delete Plan (Debug)", systemImage: "trash")
                            }
                        } else {
                            Text("No plan yet. Choose a path to create one.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .id(selectedItem.persistentModelID)
                }

                if let message {
                    Section("Message") {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Liquidate Sandbox")
            .onAppear {
                if selectedItem == nil { selectedItem = items.first }
            }
        }
    }

    // MARK: - Pattern A helpers

    @MainActor
    private func ensureItemState(_ item: LTCItem) -> LiquidationState {
        if let existing = item.liquidationState {
            return existing
        }

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

    // MARK: - Brief generation (local)

    @MainActor
    private func generateBriefLocal(for item: LTCItem) async {
        message = nil
        errorMessage = nil
        isGeneratingBrief = true

        item.disposition = .liquidate
        item.updatedAt = .now

        let state = ensureItemState(item)

        do {
            let dto = try await liquidationAI.generateBriefDTO(
                for: item,
                goal: .balanced,
                constraints: nil,
                locationHint: nil,
                imageData: nil
            )

            let payloadData = try LiquidationJSONCoding.encode(dto)

            // Deactivate existing brief records
            for i in state.briefs.indices {
                state.briefs[i].isActive = false
            }

            let rec = LiquidationBriefRecord(
                createdAt: .now,
                isActive: true,
                inputFingerprint: nil,
                payloadVersion: "brief.v1",
                aiProvider: dto.aiProvider ?? "local",
                aiModel: dto.aiModel ?? "heuristic",
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

            // 🔍 Pattern A persistence check
            print("✅ Pattern A check — item: \(item.name)")
            print("LiquidationState exists? \(item.liquidationState != nil)")
            print("Brief records: \(item.liquidationState?.briefs.count ?? -1)")
            print("Plan records: \(item.liquidationState?.plans.count ?? -1)")
            print("Active brief? \(item.liquidationState?.activeBrief != nil)")
            print("Active plan? \(item.liquidationState?.activePlan != nil)")

            message = "Generated liquidation brief (local) for “\(item.name)”."

        } catch {
            errorMessage = "Failed to generate brief: \(error.localizedDescription)"
        }

        isGeneratingBrief = false
    }

    // MARK: - Brief UI

    @ViewBuilder
    private func briefSummaryCard(_ brief: LiquidationBriefRecord, item: LTCItem) -> some View {
        if let dto = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: brief.payloadJSON) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Latest Brief")
                        .font(.headline)
                    Spacer()
                    Text(brief.createdAt, style: .time)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Recommended: \(dto.recommendedPath.rawValue)")
                    .font(.subheadline)
                    .bold()

                Text(dto.reasoning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)

                if !dto.pathOptions.isEmpty {
                    Divider()
                    ForEach(dto.pathOptions.prefix(3)) { opt in
                        HStack(alignment: .top) {
                            Text(opt.label)
                                .font(.footnote)
                                .frame(width: 170, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Effort: \(opt.effort.rawValue)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                if let net = opt.netProceeds {
                                    Text("Net: \(formatRange(net))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                if let time = opt.timeEstimate, !time.isEmpty {
                                    Text("Time: \(time)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text("Selected path: \(item.selectedLiquidationPath?.rawValue ?? "None")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Latest Brief")
                        .font(.headline)
                    Spacer()
                    Text(brief.createdAt, style: .time)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Could not decode brief payload JSON. (Schema mismatch?)")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Plan helpers (Pattern A)

    private func pathButtonsRow(item: LTCItem, briefRecord: LiquidationBriefRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose one path to create (or replace) the plan:")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("Path A") { createOrReplacePlan(item: item, briefRecord: briefRecord, chosen: .pathA) }
                Button("Path B") { createOrReplacePlan(item: item, briefRecord: briefRecord, chosen: .pathB) }
                Button("Path C") { createOrReplacePlan(item: item, briefRecord: briefRecord, chosen: .pathC) }
                Button("Donate") { createOrReplacePlan(item: item, briefRecord: briefRecord, chosen: .donate) }
            }
            .buttonStyle(.bordered)
        }
    }

    @MainActor
    private func createOrReplacePlan(item: LTCItem, briefRecord: LiquidationBriefRecord, chosen: LiquidationPath) {
        message = nil
        errorMessage = nil

        let state = ensureItemState(item)

        do {
            // Decode brief DTO (required for plan creation)
            guard let briefDTO = LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: briefRecord.payloadJSON) else {
                throw NSError(
                    domain: "LiquidateSandbox",
                    code: 2001,
                    userInfo: [NSLocalizedDescriptionKey: "Could not decode LiquidationBriefDTO from briefRecord.payloadJSON."]
                )
            }

            // Deactivate existing plan records
            for i in state.plans.indices {
                state.plans[i].isActive = false
            }

            // Build checklist steps (same logic as factory, kept local for sandbox safety)
            let checklistItems = buildChecklistItems(
                itemTitle: item.name,
                category: item.category,
                scopeIsSet: false,
                chosenPath: chosen,
                briefDTO: briefDTO
            )

            let checklist = LiquidationPlanChecklistDTO(
                schemaVersion: 1,
                createdAt: .now,
                items: checklistItems
            )

            let checklistData = try LiquidationJSONCoding.encode(checklist)

            // Create plan record
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
            message = "Created plan record for “\(item.name)” with chosen path: \(chosen.rawValue)"
        } catch {
            errorMessage = "Failed to create plan: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deletePlan(_ plan: LiquidationPlanRecord, from item: LTCItem) {
        message = nil
        errorMessage = nil

        guard let state = item.liquidationState else { return }

        do {
            modelContext.delete(plan)
            state.plans.removeAll(where: { $0.persistentModelID == plan.persistentModelID })

            // Reset selection if no active plan remains
            item.selectedLiquidationPath = nil
            item.liquidationStatus = (latestActiveBriefRecord(for: item) == nil) ? .notStarted : .hasBrief
            item.updatedAt = .now

            state.status = item.liquidationStatus
            state.updatedAt = .now

            try modelContext.save()
            message = "Deleted plan for “\(item.name)”."
        } catch {
            errorMessage = "Failed to delete plan: \(error.localizedDescription)"
        }
    }

    // MARK: - Plan checklist UI (using PlanRecord payloadJSON)

    @ViewBuilder
    private func planChecklistEditor(planRecord: LiquidationPlanRecord, item: LTCItem) -> some View {
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

    // MARK: - Checklist steps builder (sandbox-local)

    private func buildChecklistItems(
        itemTitle: String,
        category: String,
        scopeIsSet: Bool,
        chosenPath: LiquidationPath,
        briefDTO: LiquidationBriefDTO
    ) -> [LiquidationChecklistItemDTO] {
        var steps: [String] = [
            "Confirm item details for “\(itemTitle)” (\(category)) — photos, condition, measurements.",
            "Review the latest brief and note any missing details to improve outcome."
        ]

        switch chosenPath {
        case .pathA:
            steps += [
                "Take 10–14 high-quality photos (front/back/detail/maker marks/flaws).",
                "Measure key dimensions; capture maker marks/labels if present.",
                "Check 3–5 SOLD comps (not asking prices). Record typical range.",
                "Draft listing copy (materials, condition, provenance, measurements).",
                "Choose venue best fit for category (eBay/Etsy/Chairish/FB/etc.).",
                "Decide shipping vs local pickup; estimate shipping cost if shipping.",
                "List at a realistic price + small negotiation buffer; revisit after 7–10 days.",
                "Record offers and final sale; update actual net proceeds."
            ]
        case .pathB:
            steps += [
                "Identify 1–3 consignors / dealers that handle \(category).",
                "Prepare intake packet (photos + measurements + condition notes).",
                "Ask about commission %, payout timing, and pricing control.",
                "Confirm pickup/drop-off logistics and damage liability.",
                "Hand off item and store agreement details in notes.",
                "Follow up after 2–4 weeks; adjust strategy if stagnant."
            ]
        case .pathC:
            steps += [
                "Take 6–10 clear photos (include flaws).",
                "Write one-paragraph honest description (facts only).",
                "Set a fast-sale price (expect negotiation; decide your floor).",
                "Post locally (Facebook Marketplace / Nextdoor / Craigslist).",
                "Use safe pickup rules: daytime, no holds, confirm payment method.",
                "Close sale, record final price, mark completed."
            ]
        case .donate:
            steps += [
                "Pick donation destination (Goodwill, Habitat Restore, library, specialty charity).",
                "Take 1–2 photos for your records (optional).",
                "Drop off and request a receipt if useful for taxes.",
                "Record donation location + date in notes, mark completed."
            ]
        case .needsInfo:
            steps += [
                "Add missing details from the brief (measurements, maker marks, condition).",
                "Regenerate brief, then choose a path."
            ]
        }

        steps.append("AI recommended: \(briefDTO.recommendedPath.rawValue). (Adjust if your situation differs.)")

        if scopeIsSet {
            steps.insert("Confirm set completeness and decide together vs part-out approach.", at: 1)
        }

        return steps.enumerated().map { idx, text in
            LiquidationChecklistItemDTO(order: idx + 1, text: text)
        }
    }

    // MARK: - Formatting helpers

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func formatRange(_ range: MoneyRangeDTO) -> String {
        let parts = [
            range.low.map { formatCurrency($0) },
            range.likely.map { formatCurrency($0) },
            range.high.map { formatCurrency($0) }
        ].compactMap { $0 }

        if parts.isEmpty { return "—" }
        if parts.count == 1 { return parts[0] }
        return "\(parts.first!) – \(parts.last!)"
    }
}
