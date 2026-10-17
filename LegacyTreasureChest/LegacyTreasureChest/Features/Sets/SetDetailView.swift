//
//  SetDetailView.swift
//  LegacyTreasureChest
//

import SwiftUI
import SwiftData
import UIKit
import Combine

// MARK: - Pile choices saved by earlier app versions

/// How app versions before B2 saved a Set pile's business in UserDefaults.
/// Kept only so LiquidationWorkflow.importLegacySetChoices can read those
/// choices; new choices are stored in the Plan.
struct LTCSavedSelectedPartner: Codable {
    var partnerId: String
    var name: String
    var partnerType: String
    var distanceMiles: Double?
    var website: String?
    var phone: String?
}

struct SetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var itemSet: LTCItemSet

    @State private var isPresentingEdit: Bool = false
    @State private var isPresentingItemsPicker: Bool = false

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    init(itemSet: LTCItemSet) {
        self._itemSet = Bindable(wrappedValue: itemSet)
    }

    private var membersSorted: [LTCItemSetMembership] {
        itemSet.memberships.sorted { lhs, rhs in
            let lName = lhs.item?.name ?? ""
            let rName = rhs.item?.name ?? ""
            return lName.localizedCaseInsensitiveCompare(rName) == .orderedAscending
        }
    }

    private var suggestedHint: String {
        switch itemSet.setType {
        case .china: return "Suggested: China / Dinnerware (and related Crystal)"
        case .crystal: return "Suggested: Crystal / Stemware / Glass"
        case .flatware: return "Suggested: Flatware / Silverware"
        case .rugCollection: return "Suggested: Rugs"
        case .diningRoom: return "Suggested: Furniture / Decor (Dining Room)"
        case .bedroom: return "Suggested: Furniture / Decor (Bedroom)"
        case .furnitureSuite: return "Suggested: Furniture / Decor"
        case .closetLot: return "Suggested: Clothing (Closet Lot)"
        case .other: return "Suggested: All Items (mixed set)"
        }
    }


    var body: some View {
        Form {
            Section("Set") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(itemSet.name)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Type")
                    Spacer()
                    Text(itemSet.setType.rawValue)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    Text("Sell Preference")
                    Spacer()
                    Text(UserFacingTerms.Sets.name(itemSet.sellTogetherPreference))
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    Text("Completeness")
                    Spacer()
                    Text(UserFacingTerms.Sets.name(itemSet.completeness))
                        .foregroundStyle(Theme.textSecondary)
                }

                Text(suggestedHint)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
            }

            if let story = itemSet.story, !story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Story") {
                    Text(story)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.text)
                }
            }

            if let notes = itemSet.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.text)
                }
            }

            Section {
                Button {
                    isPresentingItemsPicker = true
                } label: {
                    HStack {
                        Image(systemName: "checklist")
                        Text("Add / Remove Items")
                    }
                }

                Button {
                    isPresentingEdit = true
                } label: {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit Set")
                    }
                }
            }

            // MARK: - Next Step (parity with Item)
            Section {
                NavigationLink {
                    SetLiquidationSectionView(itemSet: itemSet)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox.and.arrow.backward")
                            .foregroundStyle(Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Liquidate Set")
                                .font(Theme.bodyFont.weight(.semibold))
                                .foregroundStyle(Theme.text)

                            Text("Generate a Brief, choose an approach, and create a checklist Plan.")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                // Find Help (Set scope): available with or without a Plan.
                NavigationLink {
                    DispositionPartnersView(itemSet: itemSet)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.wave.2")
                            .foregroundStyle(Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Find Help")
                                .font(Theme.bodyFont.weight(.semibold))
                                .foregroundStyle(Theme.text)

                            Text("Find businesses that can help with this set.")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                NavigationLink {
                    SetExecutePlanView(itemSet: itemSet)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Execute Plan")
                                .font(Theme.bodyFont.weight(.semibold))
                                .foregroundStyle(Theme.text)

                            Text("Work the plan one step at a time.")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

            } header: {
                Text("Next Step")
                    .ltcSectionHeaderStyle()
            } footer: {
                Text("Local Help is enabled after you have both a Brief and a Plan for the set.")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            Section("Members (\(itemSet.memberships.count))") {
                if membersSorted.isEmpty {
                    Text("No items in this set yet.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(membersSorted) { membership in
                        if let item = membership.item {
                            NavigationLink {
                                ItemDetailView(item: item)
                            } label: {
                                memberRow(item: item, membership: membership)
                            }
                        } else {
                            Text("Unknown Item")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Set Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingEdit) {
            NavigationStack {
                SetEditorSheet(mode: .edit(itemSet))
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isPresentingItemsPicker) {
            NavigationStack {
                SetItemsPickerView(itemSet: itemSet)
            }
            .presentationDetents([.large])
        }
        .onChange(of: itemSet.name) { _, _ in touchUpdatedAt() }
        .onChange(of: itemSet.setTypeRaw) { _, _ in touchUpdatedAt() }
        .onChange(of: itemSet.sellTogetherPreferenceRaw) { _, _ in touchUpdatedAt() }
        .onChange(of: itemSet.completenessRaw) { _, _ in touchUpdatedAt() }
    }

    // MARK: - Member Row

    @ViewBuilder
    private func memberRow(item: LTCItem, membership: LTCItemSetMembership) -> some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail(for: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(Theme.sectionHeaderFont)
                    .foregroundStyle(Theme.text)

                let qty = membership.quantityInSet ?? item.quantity
                let total = item.value * Double(max(1, qty))

                Text("\(item.category) • Qty \(max(1, qty))")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)

                if item.value > 0 {
                    CurrencyText.view(total)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumbnail(for item: LTCItem) -> some View {
        if let firstImage = item.images.first,
           let uiImage = MediaStorage.loadImage(from: firstImage.filePath) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
                .clipped()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.background)

                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
            .frame(width: 56, height: 56)
        }
    }

    private func touchUpdatedAt() {
        itemSet.updatedAt = .now
    }
}

// MARK: - Set Execute Plan
// (unchanged below — your existing content continues)


// MARK: - Set Execute Plan

struct SetExecutePlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var itemSet: LTCItemSet

    @State private var expandedBlockID: BlockID? = .luxury
    @State private var readinessExpandedLuxury: Bool = false
    @State private var errorMessage: String?
    @State private var refreshToken: UUID = UUID()

    // Shared Plan execution (LiquidationWorkflow): one outcome for the whole Plan.
    @State private var outcomePlan: LiquidationPlanRecord?
    @State private var findHelpRequest: LiquidationFindHelpRequest?
    @State private var reviewBrief: LiquidationBriefRecord?
    /// Pile choices from earlier versions that could not be imported (shown, not copied).
    @State private var legacyChoices: [String: LiquidationWorkflow.LegacyProviderChoice] = [:]

    private var owner: LiquidationOwner { .itemSet(itemSet) }

    enum BlockID: String, CaseIterable, Identifiable {
        case luxury
        case contemporary
        case donate
        case discard
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .luxury: return "Luxury / Designer → Mail-in Hub"
            case .contemporary: return "Better Contemporary → Secondary Channels"
            case .donate: return "Donate"
            case .discard: return "Discard / Recycle"
            case .other: return "Other Steps"
            }
        }

        var subtitle: String {
            switch self {
            case .luxury: return "Highest-value pile. Usually requires one hub partner."
            case .contemporary: return "Good condition brands; local consignment or resale apps."
            case .donate: return "Fast exit; keep a simple record."
            case .discard: return "Worn/damaged; keep it simple."
            case .other: return "General steps not tied to a specific pile."
            }
        }

        var icon: String {
            switch self {
            case .luxury: return "shippingbox.fill"
            case .contemporary: return "tag.fill"
            case .donate: return "heart.fill"
            case .discard: return "trash.fill"
            case .other: return "checkmark.circle.fill"
            }
        }

        var requiresPartner: Bool {
            switch self {
            case .luxury, .contemporary: return true
            default: return false
            }
        }
    }

    private func latestActivePlanRecord(for itemSet: LTCItemSet) -> LiquidationPlanRecord? {
        guard let state = itemSet.liquidationState else { return nil }
        if let active = state.plans.first(where: { $0.isActive }) { return active }
        return state.plans.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Execute Plan")
                        .font(Theme.sectionHeaderFont)
                        .foregroundStyle(Theme.text)

                    Text("Work one pile at a time. Choose businesses only where needed.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 4)
            }

            if let plan = latestActivePlanRecord(for: itemSet) {
                planBackedExecution(planRecord: plan)
                    .id(refreshToken)
            } else {
                Section("No Plan Yet") {
                    Text("Generate a brief and create a plan first.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)

                    NavigationLink {
                        SetLiquidationSectionView(itemSet: itemSet)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Go to Liquidate Set")
                        }
                    }
                    .foregroundStyle(Theme.accent)
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(Theme.secondaryFont)
                }
            }
        }
        .navigationTitle("Execute Plan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $outcomePlan) { plan in
            LiquidationOutcomeForm(
                planTitle: UserFacingTerms.Liquidation.planTitle(plan.chosenPath),
                existing: LiquidationWorkflow.checklist(of: plan)?.outcome,
                currencyCode: Locale.current.currency?.identifier ?? "USD",
                suggestedCounterparty: LiquidationWorkflow.checklist(of: plan)?.selectedProviders?
                    .compactMap(\.storedDisplayName).first
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
        // Runs once per Plan. It must stay outside the `.id(refreshToken)`
        // subtree: an appearance trigger inside it re-fires on every identity
        // reset, which kept the main thread busy and caused a watchdog kill.
        .task(id: latestActivePlanRecord(for: itemSet)?.persistentModelID) {
            if let plan = latestActivePlanRecord(for: itemSet) { importLegacyChoices(plan) }
        }
    }

    // MARK: - Plan-backed UI

    @ViewBuilder
    private func planBackedExecution(planRecord: LiquidationPlanRecord) -> some View {
        if let checklist = LiquidationJSONCoding.tryDecode(
            LiquidationPlanChecklistDTO.self,
            from: planRecord.payloadJSON
        ) {
            Section("Plan") {
                VStack(alignment: .leading, spacing: 8) {
                    LiquidationPlanContextHeader(
                        chosenPath: planRecord.chosenPath,
                        status: planRecord.status,
                        checklist: checklist
                    )
                    LiquidationPlanProgressView(checklist: checklist)
                }
                .padding(.vertical, 4)
            }

            let groupedIndices = groupChecklistItemIndices(
                checklist: checklist,
                setType: itemSet.setType
            )

            let planID = String(describing: planRecord.persistentModelID)

            Section("Work Units") {
                ForEach(BlockID.allCases) { blockID in
                    let indices = groupedIndices[blockID, default: []]
                    if !indices.isEmpty {
                        blockCard(
                            blockID: blockID,
                            indices: indices,
                            checklist: checklist,
                            planRecord: planRecord,
                            planID: planID
                        )
                    }
                }
            }

            // One outcome for the whole Plan, never one per pile.
            Section("Outcome") {
                LiquidationOutcomeRow(outcome: checklist.outcome, isDisabled: false) {
                    outcomePlan = planRecord
                }
                .padding(.vertical, 4)
            }
        } else {
            Section("Plan") {
                Text("Could not decode plan checklist JSON.")
                    .foregroundStyle(.red)
                    .font(Theme.secondaryFont)
            }
        }
    }

    @ViewBuilder
    private func blockCard(
        blockID: BlockID,
        indices: [Int],
        checklist: LiquidationPlanChecklistDTO,
        planRecord: LiquidationPlanRecord,
        planID: String
    ) -> some View {
        let isExpanded = (expandedBlockID == blockID)
        let completedCount = indices.filter { checklist.items[$0].isCompleted }.count
        let totalCount = indices.count

        Group {
            // Row 1: Header (tap to expand/collapse)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedBlockID = isExpanded ? nil : blockID
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: blockID.icon)
                        .foregroundStyle(Theme.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(blockID.title)
                            .font(Theme.sectionHeaderFont)
                            .foregroundStyle(Theme.text)

                        Text(blockID.subtitle)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    Text("\(completedCount)/\(totalCount)")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Row 2: Readiness (if applicable)
                readinessChecklistIfApplicable(for: blockID)

                // Row 3: Partner row (or "not needed")
                partnerRow(blockID: blockID, planRecord: planRecord, checklist: checklist)

                // Rows 4..N: Plan checklist items (each as its own Form row)
                ForEach(indices.sorted(), id: \.self) { i in
                    let item = checklist.items[i]
                    LiquidationChecklistStepRow(
                        step: item,
                        isDisabled: false,
                        onToggle: { newValue in
                            toggleChecklistItem(
                                planRecord: planRecord,
                                checklistItemID: item.id,
                                newValue: newValue
                            )
                        },
                        onAction: { action in
                            handleStepAction(action, step: item, blockID: blockID, planRecord: planRecord, planID: planID)
                        }
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    /// The business chosen for a pile, from the Plan (B2). A pile choice saved
    /// by an earlier version without a reliable reference is shown so the
    /// homeowner can choose again; it is never copied or guessed.
    private func partnerRow(blockID: BlockID, planRecord: LiquidationPlanRecord, checklist: LiquidationPlanChecklistDTO) -> some View {
        Group {
            if blockID.requiresPartner {
                if let selection = LiquidationWorkflow.selection(in: checklist, group: blockID.rawValue) {
                    SavedProviderRow(
                        selection: selection,
                        isDisabled: false,
                        onChange: { openFindHelp(for: blockID, planRecord: planRecord) },
                        onRemove: { removeProvider(group: blockID.rawValue, from: planRecord) }
                    )
                } else if let legacy = legacyChoices[blockID.rawValue] {
                    LegacyProviderChoiceRow(choice: legacy) { openFindHelp(for: blockID, planRecord: planRecord) }
                } else {
                    HStack(spacing: 10) {
                        Text("No business chosen yet.")
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button("Find Help") { openFindHelp(for: blockID, planRecord: planRecord) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(Theme.textSecondary)
                    Text("No business needed for this pile.")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
            }
        }
    }

    private func openFindHelp(for blockID: BlockID, planRecord: LiquidationPlanRecord) {
        findHelpRequest = LiquidationWorkflow.findHelpRequest(
            plan: planRecord, step: nil, action: .findHelp, group: blockID.rawValue)
    }

    @MainActor
    private func removeProvider(group: String, from plan: LiquidationPlanRecord) {
        do {
            try LiquidationWorkflow.removeProvider(group: group, in: plan, owner: owner, context: modelContext)
            refreshToken = UUID()
        } catch {
            errorMessage = "Could not remove the business: \(error.localizedDescription)"
        }
    }

    /// Brings pile choices saved by earlier versions into the Plan where a
    /// reliable reference exists. Earlier storage is left untouched.
    @MainActor
    private func importLegacyChoices(_ plan: LiquidationPlanRecord) {
        let planKey = String(describing: plan.persistentModelID)
        let groups = BlockID.allCases.filter(\.requiresPartner).map(\.rawValue)
        do {
            let unresolved = try LiquidationWorkflow.importLegacySetChoices(
                plan: plan, planKey: planKey, groups: groups, owner: owner, context: modelContext)
            let choices = Dictionary(uniqueKeysWithValues: unresolved.map { ($0.group, $0) })
            if choices != legacyChoices { legacyChoices = choices }
        } catch {
            errorMessage = "Could not read earlier business choices: \(error.localizedDescription)"
        }
    }

    // MARK: - Readiness Checklist (v1)

    private func readinessChecklistIfApplicable(for blockID: BlockID) -> some View {
        return Group {
            if blockID == .luxury {

                // 1) Shoes / Boots
                if setLooksLikeFootwear(itemSet),
                   let checklist = try? ReadinessChecklistLibrary.shared.luxuryClothingShoesBoots()
                {
                    DisclosureGroup(isExpanded: $readinessExpandedLuxury) {
                        readinessChecklistCard(checklist: checklist)
                            .padding(.top, 6)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checklist")
                                .foregroundStyle(Theme.accent)

                            Text("Readiness Checklist (Advisory)")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.text)

                            Spacer()

                            Text(readinessExpandedLuxury ? "Hide" : "Show")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 6)
                    }
                }

                // 2) Designer Apparel
                else if setLooksLikeDesignerApparel(itemSet),
                        let checklist = try? ReadinessChecklistLibrary.shared.luxuryClothingDesignerApparel()
                {
                    DisclosureGroup(isExpanded: $readinessExpandedLuxury) {
                        readinessChecklistCard(checklist: checklist)
                            .padding(.top, 6)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checklist")
                                .foregroundStyle(Theme.accent)

                            Text("Readiness Checklist (Advisory)")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.text)

                            Spacer()

                            Text(readinessExpandedLuxury ? "Hide" : "Show")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 6)
                    }
                }

                // 3) Watches
                else if setLooksLikeWatches(itemSet),
                        let checklist = try? ReadinessChecklistLibrary.shared.luxuryPersonalItemsWatches()
                {
                    DisclosureGroup(isExpanded: $readinessExpandedLuxury) {
                        readinessChecklistCard(checklist: checklist)
                            .padding(.top, 6)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checklist")
                                .foregroundStyle(Theme.accent)

                            Text("Readiness Checklist (Advisory)")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.text)

                            Spacer()

                            Text(readinessExpandedLuxury ? "Hide" : "Show")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 6)
                    }
                }

                // 4) Handbags
                else if setLooksLikeHandbags(itemSet),
                        let checklist = try? ReadinessChecklistLibrary.shared.luxuryPersonalItemsHandbags()
                {
                    DisclosureGroup(isExpanded: $readinessExpandedLuxury) {
                        readinessChecklistCard(checklist: checklist)
                            .padding(.top, 6)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checklist")
                                .foregroundStyle(Theme.accent)

                            Text("Readiness Checklist (Advisory)")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.text)

                            Spacer()

                            Text(readinessExpandedLuxury ? "Hide" : "Show")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 6)
                    }
                }

                // 5) Jewelry
                else if setLooksLikeJewelry(itemSet),
                        let checklist = try? ReadinessChecklistLibrary.shared.luxuryPersonalItemsJewelry()
                {
                    DisclosureGroup(isExpanded: $readinessExpandedLuxury) {
                        readinessChecklistCard(checklist: checklist)
                            .padding(.top, 6)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checklist")
                                .foregroundStyle(Theme.accent)

                            Text("Readiness Checklist (Advisory)")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.text)

                            Spacer()

                            Text(readinessExpandedLuxury ? "Hide" : "Show")
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 6)
                    }
                }

                else {
                    EmptyView()
                }
            } else {
                EmptyView()
            }
        }
    }
    // MARK: - Readiness Matching (v1)

    private func setLooksLikeFootwear(_ set: LTCItemSet) -> Bool {
        let text = setSearchText(set)
        let tokens = tokenize(text)

        let footwearSignals: Set<String> = [
            "shoe", "shoes",
            "boot", "boots",
            "heel", "heels",
            "sneaker", "sneakers",
            "loafer", "loafers",
            "sandal", "sandals",
            "pump", "pumps",
            "stiletto", "stilettos"
        ]

        // Avoid obvious false-positive
        if tokens.contains("bootcut") { return false }

        return !footwearSignals.isDisjoint(with: tokens)
    }

    private func setLooksLikeWatches(_ set: LTCItemSet) -> Bool {
        let text = setSearchText(set)
        let tokens = tokenize(text)

        let watchSignals: Set<String> = [
            "watch", "watches",
            "timepiece", "chronograph",
            "gmt", "automatic", "mechanical",
            "rolex", "omega", "cartier", "tudor",
            "tag", "heuer", "breitling", "panerai",
            "iwc", "jaeger", "jlc", "patek", "audemars", "ap"
        ]

        // Avoid accidental match from plain English
        if tokens.contains("watching") { return false }

        return !watchSignals.isDisjoint(with: tokens)
    }

    private func setLooksLikeDesignerApparel(_ set: LTCItemSet) -> Bool {
        let text = setSearchText(set)
        let tokens = tokenize(text)

        // If it's footwear, let footwear win (avoid double match)
        if tokens.contains("shoe") || tokens.contains("shoes") || tokens.contains("boot") || tokens.contains("boots") {
            return false
        }

        let apparelSignals: Set<String> = [
            "shirt", "shirts",
            "blouse", "blouses",
            "dress", "dresses",
            "skirt", "skirts",
            "coat", "coats",
            "jacket", "jackets",
            "sportcoat", "sportcoats",
            "blazer", "blazers",
            "sweater", "sweaters",
            "cardigan", "cardigans",
            "shawl", "shawls",
            "scarf", "scarves",
            "pants", "trousers", "jeans",
            "suit", "suits"
        ]

        return !apparelSignals.isDisjoint(with: tokens)
    }

    private func setLooksLikeHandbags(_ set: LTCItemSet) -> Bool {
        let text = setSearchText(set)
        let tokens = tokenize(text)

        let handbagSignals: Set<String> = [
            // generic
            "handbag", "handbags",
            "purse", "purses",
            "bag", "bags",
            "tote", "totes",
            "satchel", "satchels",
            "crossbody", "cross-body",
            "clutch", "clutches",
            "hobo", "hobos",
            "shoulderbag", "shoulderbags",
            "backpack", "backpacks",
            // luxury brands (signals, not exhaustive)
            "chanel", "louis", "vuitton", "lv",
            "hermes", "hermès",
            "gucci", "prada", "dior", "celine", "céline",
            "ysl", "saint", "laurent",
            "balenciaga", "bottega", "veneta",
            "fendi", "givenchy", "loewe", "coach"
        ]

        // Avoid obvious false positives
        if tokens.contains("bagel") { return false }

        return !handbagSignals.isDisjoint(with: tokens)
    }

    private func setLooksLikeJewelry(_ set: LTCItemSet) -> Bool {
        let text = setSearchText(set)
        let tokens = tokenize(text)

        // Primary jewelry nouns
        let jewelrySignals: Set<String> = [
            "jewelry", "jewellery",
            "ring", "rings",
            "bracelet", "bracelets",
            "necklace", "necklaces",
            "pendant", "pendants",
            "earring", "earrings",
            "stud", "studs",
            "hoop", "hoops",
            "bangle", "bangles",
            "brooch", "brooches",
            "anklet", "anklets",
            "charm", "charms",
            "chain", "chains",
            "cufflink", "cufflinks"
        ]

        // High-signal brand terms (still advisory, not classification)
        let brandSignals: Set<String> = [
            "tiffany",
            "cartier",
            "bulgari", "bvlgari",
            "mikimoto",
            "chopard",
            "buccellati",
            "graff",
            "winston", "harry",
            "yurman", "david",
            "vca", "arpels", "cleef", "vancleef"
        ]

        // Avoid a few common false positives where "ring" appears in other contexts
        let falsePositives: Set<String> = [
            "ringtone", "ringtones",
            "ringing",
            "keyring", "keyrings",
            "ringlight", "ringlights"
        ]

        // If we only hit a false-positive token and nothing else, bail out.
        if !falsePositives.isDisjoint(with: tokens) {
            let hasOtherJewelrySignal = !jewelrySignals.isDisjoint(with: tokens) || !brandSignals.isDisjoint(with: tokens)
            if !hasOtherJewelrySignal { return false }
        }

        return !jewelrySignals.isDisjoint(with: tokens) || !brandSignals.isDisjoint(with: tokens)
    }

    private func setSearchText(_ set: LTCItemSet) -> String {
        [
            set.name,
            set.notes ?? "",
            set.story ?? "",
            set.closetBrandList ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func tokenize(_ text: String) -> Set<String> {
        let cleaned = text.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : " "
        }

        let tokens = String(cleaned)
            .split(separator: " ")
            .map { String($0) }

        return Set(tokens)
    }
    // MARK: - Readiness UI

    @ViewBuilder
    private func readinessChecklistCard(checklist: ReadinessChecklist) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let attributed = try? AttributedString(markdown: checklist.markdown) {
                Text(attributed)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
            } else {
                Text(checklist.markdown)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
            }

            Text("This is optional preparation. You can proceed even if you skip items.")
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Grouping logic (safe, heuristic, index-based)

    private func groupChecklistItemIndices(
        checklist: LiquidationPlanChecklistDTO,
        setType: SetType
    ) -> [BlockID: [Int]] {
        // Shared rules: explicit Plan v2 piles, else legacy keyword grouping for closet lots.
        let groups = LiquidationWorkflow.executionGroups(for: checklist, isClosetLot: setType == .closetLot)
        var dict: [BlockID: [Int]] = [:]
        for (name, indices) in groups {
            dict[BlockID(rawValue: name) ?? .other, default: []].append(contentsOf: indices)
        }
        return dict
    }

    // MARK: - Persistence (checklist)

    @MainActor
    private func toggleChecklistItem(
        planRecord: LiquidationPlanRecord,
        checklistItemID: UUID,
        newValue: Bool
    ) {
        errorMessage = nil
        do {
            try LiquidationWorkflow.setStep(checklistItemID, completed: newValue, in: planRecord, owner: owner, context: modelContext)
            refreshToken = UUID()
        } catch {
            errorMessage = "Failed saving checklist: \(error.localizedDescription)"
        }
    }

    /// Find Help opens the shared Find Help screen for the step's pile. Never ticks the step.
    private func handleStepAction(
        _ action: LiquidationStepAction,
        step: LiquidationChecklistItemDTO,
        blockID: BlockID,
        planRecord: LiquidationPlanRecord,
        planID: String
    ) {
        switch action {
        case .findHelp, .findSpecialtyHelp:
            // The shared Find Help screen, for this pile when it needs a business.
            findHelpRequest = LiquidationWorkflow.findHelpRequest(
                plan: planRecord, step: step, action: action,
                group: blockID.requiresPartner ? blockID.rawValue : step.group)
        case .viewBrief:
            reviewBrief = LiquidationWorkflow.originatingBrief(of: planRecord, in: itemSet.liquidationState)
        case .recordOutcome:
            outcomePlan = planRecord
        }
    }

    @MainActor
    private func saveOutcome(_ outcome: LiquidationPlanOutcomeDTO, in plan: LiquidationPlanRecord) {
        errorMessage = nil
        do {
            try LiquidationWorkflow.saveOutcome(outcome, in: plan, owner: owner, context: modelContext)
            refreshToken = UUID()
        } catch {
            errorMessage = "Failed saving outcome: \(error.localizedDescription)"
        }
    }

}
