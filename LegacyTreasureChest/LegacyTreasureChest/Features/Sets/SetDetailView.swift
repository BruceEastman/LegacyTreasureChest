//
//  SetDetailView.swift
//  LegacyTreasureChest
//

import SwiftUI
import SwiftData
import UIKit
import CoreLocation
import Combine

// MARK: - Shared partner selection model (file-level, accessible everywhere)

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
                    Text(itemSet.sellTogetherPreference.rawValue)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    Text("Completeness")
                    Spacer()
                    Text(itemSet.completeness.rawValue)
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

                NavigationLink {
                    SetLiquidationSectionView(itemSet: itemSet)
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Next Step → Liquidate Set")
                    }
                }
                .foregroundStyle(Theme.accent)

                NavigationLink {
                    SetExecutePlanView(itemSet: itemSet)
                } label: {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("Execute Plan")
                    }
                }
                .foregroundStyle(Theme.accent)
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
                    Text(total, format: .currency(code: currencyCode))
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

private struct SetExecutePlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var itemSet: LTCItemSet

    @State private var expandedBlockID: BlockID? = .luxury
    @State private var readinessExpandedLuxury: Bool = false
    @State private var errorMessage: String?
    @State private var refreshToken: UUID = UUID()

    // Partner picker (sheet(item:) prevents empty/blank sheet)
    private struct PartnerPickerSheet: Identifiable {
        let id: String
        let block: BlockID
        let planID: String

        init(block: BlockID, planID: String) {
            self.block = block
            self.planID = planID
            self.id = "\(planID).\(block.rawValue)"
        }
    }

    @State private var partnerPickerSheet: PartnerPickerSheet?

    private let dispositionAI = DispositionAIService()

    // NOTE: no longer `private` so SetPartnerPickerView can use it
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

    private func selectionKey(planID: String, block: BlockID) -> String {
        "ltc.set.execute.partner.\(planID).\(block.rawValue)"
    }

    private func loadSelectedPartner(planID: String, block: BlockID) -> LTCSavedSelectedPartner? {
        let key = selectionKey(planID: planID, block: block)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LTCSavedSelectedPartner.self, from: data)
    }

    private func saveSelectedPartner(planID: String, block: BlockID, partner: LTCSavedSelectedPartner?) {
        let key = selectionKey(planID: planID, block: block)
        if let partner {
            if let data = try? JSONEncoder().encode(partner) {
                UserDefaults.standard.set(data, forKey: key)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: key)
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

                    Text("Work one pile at a time. Choose partners only where needed.")
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
        .sheet(item: $partnerPickerSheet) { sheet in
            NavigationStack {
                SetPartnerPickerView(
                    itemSet: itemSet,
                    block: sheet.block,
                    planID: sheet.planID,
                    dispositionAI: dispositionAI,
                    onSelect: { selected in
                        saveSelectedPartner(planID: sheet.planID, block: sheet.block, partner: selected)
                        partnerPickerSheet = nil
                        refreshToken = UUID()
                    },
                    onCancel: {
                        partnerPickerSheet = nil
                    }
                )
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Plan-backed UI

    @ViewBuilder
    private func planBackedExecution(planRecord: LiquidationPlanRecord) -> some View {
        if let checklist = LiquidationJSONCoding.tryDecode(
            LiquidationPlanChecklistDTO.self,
            from: planRecord.payloadJSON
        ) {
            let pct = completionPercent(checklist)

            Section("Progress") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: pct)
                    Text("Completion: \(Int(pct * 100))%")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
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
                partnerRow(blockID: blockID, planID: planID)

                // Rows 4..N: Plan checklist items (each as its own Form row)
                ForEach(indices.sorted(), id: \.self) { i in
                    let item = checklist.items[i]
                    Toggle(isOn: Binding(
                        get: { item.isCompleted },
                        set: { newValue in
                            toggleChecklistItem(
                                planRecord: planRecord,
                                checklistItemID: item.id,
                                newValue: newValue
                            )
                        }
                    )) {
                        Text("\(item.order). \(item.text)")
                            .font(.subheadline)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func partnerRow(blockID: BlockID, planID: String) -> some View {
        if blockID.requiresPartner {
            let selected = loadSelectedPartner(planID: planID, block: blockID)
            let selectedName = selected?.name ?? "Not selected"
            let actionLabel = (selected == nil) ? "Select" : "Change"

            Button {
                partnerPickerSheet = PartnerPickerSheet(block: blockID, planID: planID)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(Theme.textSecondary)

                    Text(UserFacingTerms.Disposition.sellingOptionLabel + ":")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)

                    Text(selectedName)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.text)

                    Spacer()

                    Text(actionLabel)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(Theme.textSecondary)

                Text("\(UserFacingTerms.Disposition.sellingOptionLabel): Not needed")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()
            }
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
        let indices = Array(checklist.items.indices)

        guard setType == .closetLot else {
            return [.other: indices]
        }

        func blockForText(_ text: String) -> BlockID {
            let t = text.lowercased()

            if t.contains("hub") || t.contains("mail") || t.contains("ship") || t.contains("insured") || t.contains("authentication") || t.contains("designer") || t.contains("luxury") {
                return .luxury
            }

            if t.contains("consign") || t.contains("consignment") || t.contains("resale") || t.contains("poshmark") || t.contains("depop") || t.contains("thredup") || t.contains("contemporary") || t.contains("facebook marketplace") {
                return .contemporary
            }

            if t.contains("donat") || t.contains("charity") || t.contains("thrift") {
                return .donate
            }

            if t.contains("discard") || t.contains("trash") || t.contains("recycle") || t.contains("damaged") || t.contains("stain") {
                return .discard
            }

            return .other
        }

        var dict: [BlockID: [Int]] = [:]
        for i in indices {
            let bid = blockForText(checklist.items[i].text)
            dict[bid, default: []].append(i)
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
            refreshToken = UUID()
        } catch {
            errorMessage = "Failed saving checklist: \(error.localizedDescription)"
        }
    }

    private func completionPercent(_ checklist: LiquidationPlanChecklistDTO) -> Double {
        guard !checklist.items.isEmpty else { return 0 }
        let completed = checklist.items.filter { $0.isCompleted }.count
        return Double(completed) / Double(checklist.items.count)
    }
}

// MARK: - Partner Picker (Set scope)

private final class LTCLocationAutofill: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    @Published var city: String = ""
    @Published var region: String = ""
    @Published var countryCode: String = ""

    @Published var statusText: String? = nil
    @Published var isWorking: Bool = false

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestOnce() {
        // Don’t spam requests
        guard !isWorking else { return }
        isWorking = true
        statusText = "Using your current location…"

        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            statusText = "Location access is off. Enter a city or enable Location Services."
            isWorking = false
        @unknown default:
            statusText = "Location status unknown. Enter a city."
            isWorking = false
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            statusText = "Location access is off. Enter a city or enable Location Services."
            isWorking = false
        case .notDetermined:
            break
        @unknown default:
            statusText = "Location status unknown. Enter a city."
            isWorking = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusText = "Couldn’t get current location. Enter a city."
        isWorking = false
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else {
            statusText = "Couldn’t get current location. Enter a city."
            isWorking = false
            return
        }

        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self else { return }
            let pm = placemarks?.first

            let city = pm?.locality ?? ""
            let region = pm?.administrativeArea ?? ""
            let cc = pm?.isoCountryCode ?? ""

            if !city.isEmpty { self.city = city }
            if !region.isEmpty { self.region = region }
            if !cc.isEmpty { self.countryCode = cc }

            self.statusText = nil
            self.isWorking = false
        }
    }
}

private struct SetPartnerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    
    let itemSet: LTCItemSet
    let block: SetExecutePlanView.BlockID
    let planID: String
    
    let dispositionAI: DispositionAIService
    
    let onSelect: (LTCSavedSelectedPartner) -> Void
    let onCancel: () -> Void
    
    @State private var city: String = ""
    @State private var region: String = ""
    @State private var countryCode: String = Locale.current.region?.identifier ?? "US"
    @State private var radiusMiles: Int = 25
    
    @State private var isSearching: Bool = false
    @State private var errorMessage: String?
    @State private var response: DispositionPartnersSearchResponse?
    
    @State private var isResultsExpanded: Bool = true
    
    @FocusState private var focusedField: Field?
    
    @StateObject private var autofill = LTCLocationAutofill()
    
    private enum Field {
        case city
        case region
        case country
    }
    
    private var blockForService: DispositionAIService.SetPartnerBlock? {
        switch block {
        case .luxury: return .luxury
        case .contemporary: return .contemporary
        default: return nil
        }
    }
    
    private func partnerPickerSetSearchText(_ set: LTCItemSet) -> String {
        [
            set.name,
            set.notes ?? "",
            set.story ?? "",
            set.closetBrandList ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func partnerPickerTokenize(_ text: String) -> Set<String> {
        let cleaned = text.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        return Set(cleaned.split(separator: " ").map { String($0) })
    }

    private func setLooksLikeWatches(_ set: LTCItemSet) -> Bool {
        let tokens = partnerPickerTokenize(partnerPickerSetSearchText(set))

        let watchSignals: Set<String> = [
            "watch", "watches",
            "timepiece", "chronograph",
            "gmt", "automatic", "mechanical",
            "rolex", "omega", "cartier", "tudor",
            "tag", "heuer", "breitling", "panerai",
            "iwc", "jaeger", "jlc", "patek", "audemars", "ap"
        ]

        if tokens.contains("watching") { return false }
        return !watchSignals.isDisjoint(with: tokens)
    }
    
    private func setLooksLikeHandbags(_ set: LTCItemSet) -> Bool {
        let tokens = partnerPickerTokenize(partnerPickerSetSearchText(set))

        let handbagSignals: Set<String> = [
            "handbag", "handbags",
            "purse", "purses",
            "bag", "bags",
            "tote", "totes",
            "satchel", "satchels",
            "crossbody", "cross", "body",
            "clutch", "clutches",
            "hobo", "hobos",
            "shoulder", "shoulderbag", "shoulderbags",
            // brand signals
            "chanel", "louis", "vuitton", "lv",
            "hermes", "gucci", "prada", "dior",
            "celine", "ysl", "saint", "laurent",
            "balenciaga", "bottega", "veneta",
            "fendi", "givenchy", "loewe", "coach"
        ]

        // Avoid obvious accidental matches
        if tokens.contains("baggage") { return false }

        return !handbagSignals.isDisjoint(with: tokens)
    }
    
    private func setLooksLikeJewelry(_ set: LTCItemSet) -> Bool {
        let tokens = partnerPickerTokenize(partnerPickerSetSearchText(set))

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

        let falsePositives: Set<String> = [
            "ringtone", "ringtones",
            "ringing",
            "keyring", "keyrings",
            "ringlight", "ringlights"
        ]

        if !falsePositives.isDisjoint(with: tokens) {
            let hasOtherJewelrySignal = !jewelrySignals.isDisjoint(with: tokens) || !brandSignals.isDisjoint(with: tokens)
            if !hasOtherJewelrySignal { return false }
        }

        return !jewelrySignals.isDisjoint(with: tokens) || !brandSignals.isDisjoint(with: tokens)
    }


    
    private var chosenPathForRequest: DispositionChosenPath {
        // IMPORTANT: backend requires chosenPath.
        // We avoid the donation path for luxury/contemporary partner searches.
        switch block {
        case .luxury:
            return .B
        case .contemporary:
            return .C
        default:
            return .needsInfo
        }
    }
    
    var body: some View {
        Form {
            Section("Location") {
                TextField("City", text: $city)
                    .focused($focusedField, equals: .city)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                
                TextField("State / Region", text: $region)
                    .focused($focusedField, equals: .region)
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.done)
                
                TextField("Country Code (e.g. US)", text: $countryCode)
                    .focused($focusedField, equals: .country)
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.done)
                
                Stepper(value: $radiusMiles, in: 5...200, step: 5) {
                    Text("Radius: \(radiusMiles) miles")
                }
                
                if let status = autofill.statusText {
                    Text(status)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                
                Button {
                    autofill.requestOnce()
                } label: {
                    Label(autofill.isWorking ? "Locating…" : "Use Current Location", systemImage: "location.fill")
                }
                .disabled(autofill.isWorking)
            }
            
            Section {
                Button {
                    focusedField = nil
                    Task { await search() }
                } label: {
                    Label(isSearching ? "Searching…" : UserFacingTerms.Disposition.searchSellingOptionsCTA, systemImage: "magnifyingglass")
                }
                .disabled(isSearching || blockForService == nil)
                
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(Theme.secondaryFont)
                }
            }
            
            if let response {
                Section {
                    DisclosureGroup(isExpanded: $isResultsExpanded) {
                        if response.results.isEmpty {
                            Text(UserFacingTerms.Disposition.noSellingOptionsFound)
                                .font(Theme.secondaryFont)
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            ForEach(response.results) { p in
                                partnerRowButton(p)
                            }
                        }
                    } label: {
                        Text(UserFacingTerms.Disposition.sellingOptionsHeader)
                            .font(Theme.sectionHeaderFont)
                            .foregroundStyle(Theme.text)
                    }
                }
            }
            
            Section {
                Button(role: .cancel) {
                    focusedField = nil
                    onCancel()
                    dismiss()
                } label: {
                    Text("Close")
                }
            }
        }
        .navigationTitle(UserFacingTerms.Disposition.chooseWhereToSellTitle)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear {
            // If we have last-used values, keep them.
            let lastCity = UserDefaults.standard.string(forKey: "ltc.lastDisposition.city") ?? ""
            let lastRegion = UserDefaults.standard.string(forKey: "ltc.lastDisposition.region") ?? ""
            
            if city.isEmpty { city = lastCity }
            if region.isEmpty { region = lastRegion }
            
            // If still empty, try current location autofill.
            if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                autofill.requestOnce()
            }
        }
        .onReceive(autofill.$city) { newCity in
            // Only auto-fill if user hasn’t typed anything yet
            if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !newCity.isEmpty {
                city = newCity
            }
        }
        .onReceive(autofill.$region) { newRegion in
            if region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !newRegion.isEmpty {
                region = newRegion
            }
        }
        .onReceive(autofill.$countryCode) { newCC in
            if countryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !newCC.isEmpty {
                countryCode = newCC
            }
        }
    }
    
    @ViewBuilder
    private func partnerRowButton(_ p: DispositionPartnerResult) -> some View {
        let name = p.name
        let type = p.partnerType
        let distText: String? = {
            if let d = p.distanceMiles { return String(format: "%.1f mi", d) }
            return nil
        }()
        let why = (p.whyRecommended?.isEmpty == false) ? p.whyRecommended : nil
        let ratingText: String? = {
            guard let r = p.rating else { return nil }
            let count = p.userRatingsTotal ?? 0
            return "Rating: \(String(format: "%.1f", r)) (\(count))"
        }()
        let trustText: String? = {
            guard let gates = p.trust?.gates, !gates.isEmpty else { return nil }
            let passed = gates.filter { $0.status.lowercased() == "pass" }.count
            return "Trust gates passed: \(passed)/\(gates.count)"
        }()
        
        Button {
            focusedField = nil
            let selected = LTCSavedSelectedPartner(
                partnerId: p.partnerId,
                name: p.name,
                partnerType: p.partnerType,
                distanceMiles: p.distanceMiles,
                website: p.contact.website,
                phone: p.contact.phone
            )
            onSelect(selected)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name)
                        .font(Theme.sectionHeaderFont)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    if let distText {
                        Text(distText)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                
                Text(type)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                
                if let why {
                    Text(why)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                }
                
                if let ratingText {
                    Text(ratingText)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                
                if let trustText {
                    Text(trustText)
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
    
    @MainActor
    private func search() async {
        errorMessage = nil
        response = nil
        isSearching = true
        isResultsExpanded = true
        focusedField = nil
        
        // Persist last used (still useful for contemporary/local searches)
        UserDefaults.standard.set(city, forKey: "ltc.lastDisposition.city")
        UserDefaults.standard.set(region, forKey: "ltc.lastDisposition.region")
        
        guard let blockForService else {
            errorMessage = "This block does not require a partner."
            isSearching = false
            return
        }
        
        // ✅ Luxury: return curated hubs instantly (no backend search)
        if block == .luxury {

            // Handbag-focused curated hubs
            let curatedHandbags: [DispositionPartnerResult] = [
                DispositionPartnerResult(
                    partnerId: "curated-fashionphile-handbags",
                    name: "Fashionphile",
                    partnerType: "Designer Handbags (Buy/Sell, Mail-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.fashionphile.com",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Handbag-first buyer with strong brand knowledge and a mail-in workflow.",
                    questionsToAsk: [
                        "Do you buy outright vs offer consignment for my bag?",
                        "How do you grade condition (corners, handles, interior, hardware)?",
                        "What documentation helps most (receipt, dust bag, authenticity card)?",
                        "What’s the payout timing and method?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-rebag-handbags",
                    name: "Rebag",
                    partnerType: "Designer Handbags (Mail-in / Offer)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.rebag.com",
                        email: nil,
                        address: nil,
                        city: "New York",
                        region: "NY"
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Often a good path for current-demand handbags; remote selling options.",
                    questionsToAsk: [
                        "Is my brand/model in current demand?",
                        "Do you provide an instant offer? What affects it most?",
                        "Are there fees if an item is not accepted?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-vestiaire-handbags",
                    name: "Vestiaire Collective",
                    partnerType: "Designer Handbags Marketplace (Ship-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.vestiairecollective.com",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Marketplace reach for luxury handbags; can be strong for certain brands.",
                    questionsToAsk: [
                        "What are seller fees and payout timing?",
                        "How does authentication work for handbags?",
                        "What photos are required to reduce disputes/returns?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-realreal-handbags",
                    name: "The RealReal",
                    partnerType: "Designer Handbags Consignment (Mail-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.therealreal.com",
                        email: nil,
                        address: nil,
                        city: "San Francisco / New York",
                        region: "CA / NY"
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Broad luxury hub that can handle handbags with authentication workflows.",
                    questionsToAsk: [
                        "Do you accept my specific brand/model right now?",
                        "What are commission tiers and payout timing?",
                        "Do you return items that don’t meet requirements?"
                    ]
                )
            ]


            // Watch-focused curated hubs
            let curatedWatches: [DispositionPartnerResult] = [
                DispositionPartnerResult(
                    partnerId: "curated-1916company",
                    name: "The 1916 Company (WatchBox)",
                    partnerType: "Luxury Watches (Sell / Trade-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.the1916company.com/sell-and-trade/",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Watch-specialist buyer/trade-in path with insured shipping workflows.",
                    questionsToAsk: [
                        "Do you buy outright, offer consignment, or both for my brand/model?",
                        "How do you handle authentication and condition grading?",
                        "What is the payout timeline and method?",
                        "What documentation helps most (serial/ref, service history, box/papers)?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-chrono24",
                    name: "Chrono24",
                    partnerType: "Luxury Watches Marketplace (Ship-in / Escrow)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.chrono24.com",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Large watch-focused marketplace; useful for price discovery and broader buyer reach.",
                    questionsToAsk: [
                        "What are seller fees and payout timing?",
                        "What protections/escrow options are available?",
                        "What photo/verification details are required for my watch?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-ebay-auth",
                    name: "eBay Authenticity Guarantee (Watches)",
                    partnerType: "Watches Marketplace (Authentication)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.ebay.com/authenticity-guarantee/watches",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Often a practical path for single watches with authentication support.",
                    questionsToAsk: [
                        "Does my watch qualify for authenticity guarantee?",
                        "What fees and shipping/insurance rules apply?",
                        "What condition disclosures are required to avoid returns?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-realreal-watches",
                    name: "The RealReal",
                    partnerType: "Luxury Consignment (Mail-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.therealreal.com",
                        email: nil,
                        address: nil,
                        city: "San Francisco / New York",
                        region: "CA / NY"
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Broad luxury consignment hub that also handles watches; good general option.",
                    questionsToAsk: [
                        "What watch brands/models do you accept right now?",
                        "Do you offer a mail-in kit and prepaid label?",
                        "What are your commission tiers and payout timing?",
                        "Do you return items that don’t meet requirements?"
                    ]
                )
            ]

            // Jewelry-focused curated hubs
            let curatedJewelry: [DispositionPartnerResult] = [
                DispositionPartnerResult(
                    partnerId: "curated-realreal-jewelry",
                    name: "The RealReal",
                    partnerType: "Fine Jewelry Consignment (Mail-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.therealreal.com",
                        email: nil,
                        address: nil,
                        city: "San Francisco / New York",
                        region: "CA / NY"
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Broad luxury consignment hub that can handle many fine jewelry scenarios with authentication workflows.",
                    questionsToAsk: [
                        "Do you accept my brand/material type right now (designer vs estate jewelry)?",
                        "What are commission tiers and payout timing for jewelry?",
                        "What documentation helps most (receipt, appraisal, box/papers)?",
                        "Do you return items that don’t meet requirements?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-fashionphile-jewelry",
                    name: "Fashionphile",
                    partnerType: "Designer Jewelry (Buy/Sell, Mail-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.fashionphile.com",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Strong for designer-branded jewelry with a mail-in workflow and brand knowledge.",
                    questionsToAsk: [
                        "Do you buy outright or offer consignment for jewelry?",
                        "What condition factors affect offers most (scratches, missing box, repairs)?",
                        "What documentation helps most (receipt, authenticity card, appraisal)?",
                        "What’s the payout timing and method?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-vestiaire-jewelry",
                    name: "Vestiaire Collective",
                    partnerType: "Designer Jewelry Marketplace (Ship-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.vestiairecollective.com",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Marketplace reach for designer jewelry; can be useful for certain brands and styles.",
                    questionsToAsk: [
                        "What are seller fees and payout timing?",
                        "How does authentication work for jewelry?",
                        "What photos are required to reduce disputes/returns?",
                        "Are there restrictions on materials (gold/diamonds) or value thresholds?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-worthydotcom",
                    name: "Worthy",
                    partnerType: "Diamond Jewelry Resale (Auction-style, Mail-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.worthy.com",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Often a good pathway for diamond jewelry where value is materials-based and you want competitive offers.",
                    questionsToAsk: [
                        "What items are a good fit (diamonds, engagement rings, loose stones)?",
                        "What fees apply and when are they charged?",
                        "How do you handle insurance and shipping custody?",
                        "What documentation helps maximize bids (appraisal, grading report)?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-wpdiamonds",
                    name: "WP Diamonds",
                    partnerType: "Diamond Jewelry Buyer (Mail-in / Offer)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.wpdiamonds.com",
                        email: nil,
                        address: nil,
                        city: "New York",
                        region: "NY"
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Direct buyer option for diamond jewelry; can be useful for simpler, materials-based sales.",
                    questionsToAsk: [
                        "Do you buy my item type (diamond ring, loose stones, estate jewelry)?",
                        "What affects the offer most (carat, cut, clarity, certifications)?",
                        "What are the shipping/insurance rules and payout timeline?",
                        "Do you provide a return option if I decline the offer?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-idonowidont",
                    name: "I Do Now I Don’t",
                    partnerType: "Bridal / Diamond Jewelry Resale (Consignment / Marketplace)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.idonowidont.com",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Specialized path for engagement rings and bridal diamond jewelry where audience-fit matters.",
                    questionsToAsk: [
                        "Is my ring a good fit for your audience/value range?",
                        "What fees apply and what is payout timing?",
                        "What photos/documents do you require (appraisal, certification)?",
                        "How do you handle returns, disputes, and authentication?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-sothebys-jewelry",
                    name: "Sotheby’s",
                    partnerType: "Important Jewelry (Auction / Specialist Review)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.sothebys.com",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "High-end pathway for exceptional, signed, or important jewelry; best for standout pieces.",
                    questionsToAsk: [
                        "Is my piece appropriate for an auction vs a private sale?",
                        "What estimate range would you suggest and why?",
                        "What seller fees/commission apply and what timeline should I expect?",
                        "What provenance documentation will you need?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-christies-jewelry",
                    name: "Christie’s",
                    partnerType: "Important Jewelry (Auction / Specialist Review)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.christies.com",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "High-end pathway for exceptional pieces, designer-signed jewelry, or notable gemstones.",
                    questionsToAsk: [
                        "Is my piece appropriate for an auction vs private sale?",
                        "What estimate range would you suggest and why?",
                        "What seller fees/commission apply and what timeline should I expect?",
                        "What documentation is most important (appraisal, provenance, certificates)?"
                    ]
                )
            ]

            // Default curated hubs (existing Luxury Clothing / accessories)
            let curatedLuxuryDefault: [DispositionPartnerResult] = [
                DispositionPartnerResult(
                    partnerId: "curated-realreal",
                    name: "The RealReal",
                    partnerType: "Luxury Mail-in Hub (SF/NYC)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.therealreal.com",
                        email: nil,
                        address: nil,
                        city: "San Francisco / New York",
                        region: "CA / NY"
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Major luxury consignment hub with mail-in kits and authentication workflows.",
                    questionsToAsk: [
                        "What brands do you accept right now?",
                        "Do you offer a mail-in kit and prepaid label?",
                        "What are your commission tiers and payout timing?",
                        "Do you return items that don’t meet condition/brand requirements?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-fashionphile",
                    name: "Fashionphile",
                    partnerType: "Luxury Buy/Sell (Mail-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.fashionphile.com",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Strong option for luxury accessories; mail-in process, fast quotes on many items.",
                    questionsToAsk: [
                        "Which categories do you buy outright vs consignment?",
                        "How do you handle authentication and condition grading?",
                        "What’s the payout timeline and method?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-rebag",
                    name: "Rebag",
                    partnerType: "Luxury Accessories (Mail-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.rebag.com",
                        email: nil,
                        address: nil,
                        city: "New York",
                        region: "NY"
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Often a good path for handbags/accessories; offers remote selling options.",
                    questionsToAsk: [
                        "Do you offer an instant offer vs consignment?",
                        "What brands/models are currently in demand?",
                        "Are there fees for items not accepted?"
                    ]
                ),
                DispositionPartnerResult(
                    partnerId: "curated-vestiaire",
                    name: "Vestiaire Collective",
                    partnerType: "Luxury Marketplace (Ship-in)",
                    contact: DispositionPartnerContact(
                        phone: nil,
                        website: "https://www.vestiairecollective.com",
                        email: nil,
                        address: nil,
                        city: nil,
                        region: nil
                    ),
                    distanceMiles: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    trust: nil,
                    ranking: nil,
                    whyRecommended: "Large luxury resale marketplace; good for brands with broad demand.",
                    questionsToAsk: [
                        "What are seller fees and payout timing?",
                        "How does authentication work for my category?",
                        "What shipping/label options are available?"
                    ]
                )
            ]

            let isWatches = setLooksLikeWatches(itemSet)
            let isHandbags = setLooksLikeHandbags(itemSet)
            let isJewelry = setLooksLikeJewelry(itemSet)

            let curated: [DispositionPartnerResult]
            let scenarioId: String
            let partnerTypes: [String]

            if isWatches {
                curated = curatedWatches
                scenarioId = "curated.luxury.watches.v1"
                partnerTypes = ["Luxury Watches", "Watches Marketplace"]
            } else if isHandbags {
                curated = curatedHandbags
                scenarioId = "curated.luxury.handbags.v1"
                partnerTypes = ["Designer Handbags", "Luxury Mail-in Hub", "Luxury Marketplace"]
            } else if isJewelry {
                curated = curatedJewelry
                scenarioId = "curated.luxury.jewelry.v1"
                partnerTypes = ["Fine Jewelry", "Designer Jewelry", "Jewelry Marketplace", "Important Jewelry"]
            } else {
                curated = curatedLuxuryDefault
                scenarioId = "curated.luxury.mailin.v1"
                partnerTypes = ["Luxury Mail-in Hub", "Luxury Resale"]
            }

            response = DispositionPartnersSearchResponse(
                schemaVersion: 1,
                generatedAt: Date(),
                scenarioId: scenarioId,
                partnerTypes: partnerTypes,
                results: curated
            )
            isSearching = false
            return
        }


        // Contemporary (and any non-luxury paths): use backend search
        do {
            let loc = DispositionLocationDTO(
                city: city.trimmingCharacters(in: .whitespacesAndNewlines),
                region: region.trimmingCharacters(in: .whitespacesAndNewlines),
                countryCode: countryCode.trimmingCharacters(in: .whitespacesAndNewlines),
                radiusMiles: radiusMiles,
                latitude: nil,
                longitude: nil
            )
            
            let resp = try await dispositionAI.searchPartners(
                itemSet: itemSet,
                block: blockForService,
                chosenPath: chosenPathForRequest,
                location: loc,
                radiusMiles: radiusMiles
            )
            
            response = resp
        } catch {
            errorMessage = "\(UserFacingTerms.Disposition.sellingOptionsSearchFailedPrefix) \(error.localizedDescription)"
        }
        
        isSearching = false
    }
}
