//
//  LiquidationWorkflow.swift
//  LegacyTreasureChest
//
//  The single set of rules for running a Liquidation Plan, shared by the Item
//  and Set Liquidate screens and Set Execute Plan:
//  - which Brief and Plan are current
//  - checklist progress and status (an outcome, not ticked boxes, finishes a Plan)
//  - recording an outcome
//  - saving a new Brief without disturbing an existing Plan
//  - creating or replacing a Plan only after generation succeeds
//
//  Everything persists in the existing Plan JSON; no SwiftData model changes.
//

import Foundation
import SwiftData

/// Who a Brief and Plan belong to.
enum LiquidationOwner {
    case item(LTCItem)
    case itemSet(LTCItemSet)

    var state: LiquidationState? {
        switch self {
        case .item(let item): return item.liquidationState
        case .itemSet(let set): return set.liquidationState
        }
    }

    /// Status shown in the screen header.
    var status: LiquidationStatus {
        switch self {
        case .item(let item): return item.liquidationStatus
        case .itemSet(let set): return set.liquidationState?.status ?? .notStarted
        }
    }

    var isSet: Bool {
        if case .itemSet = self { return true }
        return false
    }

    @MainActor
    func ensureState(in context: ModelContext) -> LiquidationState {
        if let existing = state { return existing }
        switch self {
        case .item(let item):
            let state = LiquidationState(ownerType: .item, status: .notStarted, createdAt: .now, updatedAt: .now)
            state.item = item
            item.liquidationState = state
            context.insert(state)
            return state
        case .itemSet(let set):
            let state = LiquidationState(ownerType: .itemSet, status: .notStarted, createdAt: .now, updatedAt: .now)
            state.itemSet = set
            set.liquidationState = state
            context.insert(state)
            return state
        }
    }

    /// Keeps the owner's status and the shared LiquidationState in step.
    func apply(_ status: LiquidationStatus) {
        switch self {
        case .item(let item):
            item.liquidationStatus = status
            item.updatedAt = .now
        case .itemSet(let set):
            set.updatedAt = .now
        }
        state?.status = status
        state?.updatedAt = .now
    }
}

/// A checklist step's contextual action. Unknown values are ignored, so the
/// step stays an ordinary checkbox.
enum LiquidationStepAction: String, CaseIterable {
    case findHelp
    case findSpecialtyHelp
    case viewBrief
    case recordOutcome

    init?(step: LiquidationChecklistItemDTO) {
        guard let raw = step.action, let action = LiquidationStepAction(rawValue: raw) else { return nil }
        self = action
    }

    /// Specialty-aware searching arrives with Initiative B; until then both
    /// Find Help actions read "Find Help" and open the existing Find Help.
    var title: String {
        switch self {
        case .findHelp, .findSpecialtyHelp: return "Find Help"
        case .viewBrief: return "View Brief"
        case .recordOutcome: return "Record the Outcome"
        }
    }

    var systemImage: String {
        switch self {
        case .findHelp, .findSpecialtyHelp: return "person.2.wave.2"
        case .viewBrief: return "doc.text.magnifyingglass"
        case .recordOutcome: return "checkmark.seal"
        }
    }
}

/// Everything Find Help needs to know about where it was opened from. Today it
/// selects the existing Item or Set Find Help; Initiative B can add specialty
/// search from the same request (the Plan context is the source of truth for
/// the chosen approach) and return a chosen provider to `planRecordId`/`stepID`.
struct LiquidationFindHelpRequest: Hashable, Identifiable {
    let id = UUID()
    /// The Plan the request came from (LiquidationPlanRecord.planRecordId).
    let planRecordId: UUID?
    /// The checklist step it was opened from, if any.
    let stepID: UUID?
    /// The step asked for a specialist (findSpecialtyHelp).
    let wantsSpecialist: Bool
    /// The closet-lot pile the step belongs to, if any.
    let group: String?
    let approach: LiquidationPathDTO?
    let specificRecommendation: String?
}

enum LiquidationWorkflow {

    // MARK: - Current records

    /// The active Brief, or the newest when none is marked active.
    static func activeBrief(_ state: LiquidationState?) -> LiquidationBriefRecord? {
        guard let state else { return nil }
        return state.briefs.first(where: { $0.isActive })
            ?? state.briefs.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    /// The active Plan, or the newest when none is marked active.
    static func activePlan(_ state: LiquidationState?) -> LiquidationPlanRecord? {
        guard let state else { return nil }
        return state.plans.first(where: { $0.isActive })
            ?? state.plans.sorted(by: { $0.createdAt > $1.createdAt }).first
    }

    static func checklist(of plan: LiquidationPlanRecord) -> LiquidationPlanChecklistDTO? {
        LiquidationJSONCoding.tryDecode(LiquidationPlanChecklistDTO.self, from: plan.payloadJSON)
    }

    static func brief(of record: LiquidationBriefRecord) -> LiquidationBriefDTO? {
        LiquidationJSONCoding.tryDecode(LiquidationBriefDTO.self, from: record.payloadJSON)
    }

    /// The Brief a Plan was made from, when it still exists; otherwise the active one.
    static func originatingBrief(of plan: LiquidationPlanRecord, in state: LiquidationState?) -> LiquidationBriefRecord? {
        let id = plan.derivedFromBriefRecordId ?? checklist(of: plan)?.context?.briefRecordId
        if let id, let match = state?.briefs.first(where: { $0.briefRecordId == id }) { return match }
        return activeBrief(state)
    }

    // MARK: - Progress and status

    struct Progress: Equatable {
        let done: Int
        let total: Int

        var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
        var allDone: Bool { total > 0 && done == total }
        /// "2 of 5 steps done"
        var summary: String { "\(done) of \(total) step\(total == 1 ? "" : "s") done" }
    }

    static func progress(_ checklist: LiquidationPlanChecklistDTO) -> Progress {
        Progress(done: checklist.items.filter(\.isCompleted).count, total: checklist.items.count)
    }

    /// A recorded outcome decides the status. Without one, ticking every step of
    /// a Plan v2 leaves it In progress until the outcome is recorded; Plans from
    /// app 1.2 (no context) keep their original "all steps done = Completed" rule.
    static func planStatus(for checklist: LiquidationPlanChecklistDTO) -> PlanStatus {
        if let outcome = checklist.outcome { return outcome.result.planStatus }
        let p = progress(checklist)
        if p.done == 0 { return .notStarted }
        if p.allDone && checklist.context == nil { return .completed }
        return .inProgress
    }

    /// The Item/Set status that corresponds to a Plan status.
    static func ownerStatus(for planStatus: PlanStatus) -> LiquidationStatus {
        switch planStatus {
        case .notStarted, .inProgress: return .inProgress
        case .completed: return .completed
        case .onHold: return .onHold
        }
    }

    // MARK: - Checklist and outcome

    @MainActor
    static func setStep(
        _ stepID: UUID,
        completed: Bool,
        in plan: LiquidationPlanRecord,
        owner: LiquidationOwner,
        context: ModelContext
    ) throws {
        guard var checklist = checklist(of: plan) else { throw WorkflowError.unreadablePlan }
        guard let idx = checklist.items.firstIndex(where: { $0.id == stepID }) else { throw WorkflowError.missingStep }
        checklist.items[idx].isCompleted = completed
        checklist.items[idx].completedAt = completed ? .now : nil
        try save(checklist, to: plan, owner: owner, context: context)
    }

    /// Records or edits the outcome. The checklist steps are untouched; only the
    /// Plan and owner status follow the outcome.
    @MainActor
    static func saveOutcome(
        _ outcome: LiquidationPlanOutcomeDTO,
        in plan: LiquidationPlanRecord,
        owner: LiquidationOwner,
        context: ModelContext
    ) throws {
        guard var checklist = checklist(of: plan) else { throw WorkflowError.unreadablePlan }
        checklist.outcome = outcome
        try save(checklist, to: plan, owner: owner, context: context)
    }

    @MainActor
    private static func save(
        _ checklist: LiquidationPlanChecklistDTO,
        to plan: LiquidationPlanRecord,
        owner: LiquidationOwner,
        context: ModelContext
    ) throws {
        plan.payloadJSON = try LiquidationJSONCoding.encode(checklist)
        plan.updatedAt = .now
        let status = planStatus(for: checklist)
        plan.status = status
        if plan.isActive { owner.apply(ownerStatus(for: status)) }
        try context.save()
    }

    // MARK: - Briefs

    /// Saves a new active Brief. An existing Plan, its progress, and the status
    /// it implies are left exactly as they are.
    @MainActor
    @discardableResult
    static func recordNewBrief(
        _ dto: LiquidationBriefDTO,
        owner: LiquidationOwner,
        context: ModelContext
    ) throws -> LiquidationBriefRecord {
        let state = owner.ensureState(in: context)
        let hadPlan = activePlan(state) != nil

        for brief in state.briefs { brief.isActive = false }
        let record = LiquidationBriefRecord(
            createdAt: .now,
            isActive: true,
            inputFingerprint: nil,
            payloadVersion: "brief.v1",
            aiProvider: dto.aiProvider ?? "unknown",
            aiModel: dto.aiModel ?? "unknown",
            payloadJSON: try LiquidationJSONCoding.encode(dto)
        )
        record.state = state
        context.insert(record)
        state.briefs.append(record)

        if hadPlan {
            state.updatedAt = .now
        } else {
            owner.apply(.hasBrief)
        }
        try context.save()
        return record
    }

    /// True when the Plan was made from a Brief other than the current one and
    /// the homeowner has not chosen to keep it. Plans without a recorded
    /// originating Brief (app 1.2) never show the notice.
    static func isBasedOnEarlierBrief(_ plan: LiquidationPlanRecord, activeBrief: LiquidationBriefRecord?) -> Bool {
        guard let activeBrief else { return false }
        let checklist = checklist(of: plan)
        guard let origin = plan.derivedFromBriefRecordId ?? checklist?.context?.briefRecordId else { return false }
        if origin == activeBrief.briefRecordId { return false }
        return checklist?.keptWithBriefRecordId != activeBrief.briefRecordId
    }

    /// When the earlier-Brief notice applies, the date of the Brief the Plan was made from.
    static func earlierBriefDate(for plan: LiquidationPlanRecord, in state: LiquidationState?) -> Date? {
        let current = activeBrief(state)
        guard isBasedOnEarlierBrief(plan, activeBrief: current) else { return nil }
        let id = plan.derivedFromBriefRecordId ?? checklist(of: plan)?.context?.briefRecordId
        return state?.briefs.first(where: { $0.briefRecordId == id })?.createdAt
            ?? checklist(of: plan)?.context?.briefGeneratedAt
            ?? plan.createdAt
    }

    /// "Keep This Plan": remembers the choice for the current Brief.
    @MainActor
    static func keepPlan(
        _ plan: LiquidationPlanRecord,
        with brief: LiquidationBriefRecord,
        context: ModelContext
    ) throws {
        guard var checklist = checklist(of: plan) else { throw WorkflowError.unreadablePlan }
        checklist.keptWithBriefRecordId = brief.briefRecordId
        plan.payloadJSON = try LiquidationJSONCoding.encode(checklist)
        plan.updatedAt = .now
        try context.save()
    }

    // MARK: - Creating and replacing Plans

    /// Generates a Plan and, only once generation has succeeded, makes it the
    /// active Plan. A failure leaves the current Plan active and unchanged.
    /// Earlier Plans stay stored as inactive records, as before.
    @MainActor
    @discardableResult
    static func createPlan(
        owner: LiquidationOwner,
        chosen: LiquidationPath,
        briefRecord: LiquidationBriefRecord,
        brief: LiquidationBriefDTO,
        context: ModelContext,
        generate: () async throws -> LiquidationPlanChecklistDTO
    ) async throws -> LiquidationPlanRecord {
        let generated = try await generate()
        let checklist = LiquidationPlanAssembler.withContext(
            generated,
            chosenPath: chosen,
            brief: brief,
            briefRecordId: briefRecord.briefRecordId
        )
        let data = try LiquidationJSONCoding.encode(checklist)

        let state = owner.ensureState(in: context)
        for plan in state.plans { plan.isActive = false }

        let record = LiquidationPlanRecord(
            createdAt: .now,
            updatedAt: .now,
            isActive: true,
            chosenPath: chosen,
            status: .notStarted,
            payloadVersion: LiquidationPlanAssembler.payloadVersion,
            aiProvider: checklist.aiProvider,
            aiModel: checklist.aiModel,
            derivedFromBriefRecordId: briefRecord.briefRecordId,
            payloadJSON: data
        )
        record.state = state
        context.insert(record)
        state.plans.append(record)

        if case .item(let item) = owner {
            item.selectedLiquidationPath = chosen
            item.disposition = .liquidate
        }
        owner.apply(.inProgress)
        try context.save()
        return record
    }

    /// Confirmation text for replacing or regenerating the current Plan.
    static func replacementMessage(current plan: LiquidationPlanRecord, newPlanTitle: String) -> String {
        var message = "Your new \(newPlanTitle) will start with a fresh checklist."
        guard let checklist = checklist(of: plan) else { return message }
        let p = progress(checklist)
        var lost: [String] = []
        if p.done > 0 { lost.append("\(p.done) of \(p.total) completed steps") }
        if checklist.outcome != nil { lost.append("the recorded outcome") }
        if lost.isEmpty {
            message += " No steps in your current Plan have been completed yet."
        } else {
            message += " The \(lost.joined(separator: " and ")) in your current Plan will not carry over."
        }
        return message + " The current Plan stays until the new one is ready."
    }

    // MARK: - Find Help

    static func findHelpRequest(
        plan: LiquidationPlanRecord,
        step: LiquidationChecklistItemDTO?,
        action: LiquidationStepAction,
        group: String? = nil
    ) -> LiquidationFindHelpRequest {
        let context = checklist(of: plan)?.context
        return LiquidationFindHelpRequest(
            planRecordId: plan.planRecordId,
            stepID: step?.id,
            wantsSpecialist: action == .findSpecialtyHelp,
            group: group ?? step?.group,
            approach: context?.chosenPath ?? plan.chosenPath.briefPath,
            specificRecommendation: context?.specificRecommendation
        )
    }

    // MARK: - Providers

    static func selection(in checklist: LiquidationPlanChecklistDTO?, group: String?) -> LiquidationProviderSelectionDTO? {
        let g = group ?? LiquidationProviderSelectionDTO.mainGroup
        return checklist?.selectedProviders?.first(where: { $0.group == g })
    }

    /// Chooses a business for one group of the Plan, replacing any earlier
    /// choice for that group. Checklist progress, outcome, and status are not
    /// touched, and no step is ticked.
    @MainActor
    static func selectProvider(
        _ selection: LiquidationProviderSelectionDTO,
        in plan: LiquidationPlanRecord,
        owner: LiquidationOwner,
        context: ModelContext
    ) throws {
        guard var checklist = checklist(of: plan) else { throw WorkflowError.unreadablePlan }
        var providers = (checklist.selectedProviders ?? []).filter { $0.group != selection.group }
        providers.append(selection)
        checklist.selectedProviders = providers
        // A new choice settles any choice from an earlier app version for this group.
        var handled = Set(checklist.legacySelectionGroupsHandled ?? [])
        handled.insert(selection.group)
        checklist.legacySelectionGroupsHandled = handled.sorted()
        try save(checklist, to: plan, owner: owner, context: context)
    }

    @MainActor
    static func removeProvider(
        group: String,
        in plan: LiquidationPlanRecord,
        owner: LiquidationOwner,
        context: ModelContext
    ) throws {
        guard var checklist = checklist(of: plan) else { throw WorkflowError.unreadablePlan }
        let remaining = (checklist.selectedProviders ?? []).filter { $0.group != group }
        checklist.selectedProviders = remaining.isEmpty ? nil : remaining
        try save(checklist, to: plan, owner: owner, context: context)
    }

    // MARK: - Provider choices saved by earlier app versions (Set piles)

    /// A Set pile choice from an earlier version that cannot be turned into a
    /// reliable reference. It stays where it was saved and is shown so the
    /// homeowner can choose again; nothing is guessed from its name.
    struct LegacyProviderChoice: Equatable {
        let group: String
        let savedName: String
    }

    /// The UserDefaults key earlier versions used for a Set pile's choice.
    static func legacySelectionKey(planKey: String, group: String) -> String {
        "ltc.set.execute.partner.\(planKey).\(group)"
    }

    /// LTC directory IDs for curated providers the earlier Set picker offered.
    /// Only providers that exist in the Gateway directory are mapped.
    private static let legacyCuratedDirectoryIds: [String: String] = [
        "curated-fashionphile": "directory:fashionphile",
        "curated-fashionphile-handbags": "directory:fashionphile",
        "curated-fashionphile-jewelry": "directory:fashionphile",
        "curated-realreal": "curated:luxury:therealreal",
        "curated-realreal-handbags": "curated:luxury:therealreal",
        "curated-realreal-jewelry": "curated:luxury:therealreal",
        "curated-realreal-watches": "curated:luxury:therealreal",
        "curated-vestiaire": "curated:luxury:vestiaire",
        "curated-vestiaire-handbags": "curated:luxury:vestiaire",
        "curated-vestiaire-jewelry": "curated:luxury:vestiaire",
        "curated-worthydotcom": "directory:worthy",
    ]

    /// A reliable reference for an earlier saved choice, or nil when there is none.
    static func legacyReference(partnerId: String) -> (LiquidationProviderSelectionDTO.Source, String)? {
        if partnerId.hasPrefix("gplaces:") {
            let placeId = String(partnerId.dropFirst("gplaces:".count))
            return placeId.range(of: #"^[A-Za-z0-9_-]{10,300}$"#, options: .regularExpression) != nil
                ? (.googlePlaces, placeId) : nil
        }
        if partnerId.hasPrefix("curated:luxury:") || partnerId.hasPrefix("directory:") {
            return (.ltcDirectory, partnerId)
        }
        if let id = legacyCuratedDirectoryIds[partnerId] {
            return (.ltcDirectory, id)
        }
        return nil
    }

    /// Imports earlier Set pile choices into the Plan where a reliable reference
    /// exists (Google place ID or LTC directory ID), without overwriting a newer
    /// choice. Google names, phones, and addresses are never copied into the
    /// Plan. Earlier storage is left in place. Returns choices that could not be
    /// imported, to show with a "choose again" prompt.
    @MainActor
    @discardableResult
    static func importLegacySetChoices(
        plan: LiquidationPlanRecord,
        planKey: String,
        groups: [String],
        owner: LiquidationOwner,
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> [LegacyProviderChoice] {
        guard var checklist = checklist(of: plan) else { return [] }
        var handled = Set(checklist.legacySelectionGroupsHandled ?? [])
        var providers = checklist.selectedProviders ?? []
        var unresolved: [LegacyProviderChoice] = []
        var changed = false

        for group in groups where !handled.contains(group) {
            guard let data = defaults.data(forKey: legacySelectionKey(planKey: planKey, group: group)),
                  let saved = try? JSONDecoder().decode(LTCSavedSelectedPartner.self, from: data) else { continue }

            if providers.contains(where: { $0.group == group }) {
                handled.insert(group)
                changed = true
            } else if let (source, ref) = legacyReference(partnerId: saved.partnerId) {
                providers.append(LiquidationProviderSelectionDTO(
                    group: group,
                    source: source,
                    providerRef: ref,
                    // LTC's own curated name and site; Google content is not copied.
                    directoryName: source == .ltcDirectory ? saved.name : nil,
                    directoryWebsite: source == .ltcDirectory ? saved.website : nil
                ))
                handled.insert(group)
                changed = true
            } else {
                unresolved.append(LegacyProviderChoice(group: group, savedName: saved.name))
            }
        }

        if changed {
            checklist.selectedProviders = providers.isEmpty ? nil : providers
            checklist.legacySelectionGroupsHandled = handled.sorted()
            try save(checklist, to: plan, owner: owner, context: context)
        }
        return unresolved
    }

    // MARK: - Set execution groups

    /// Closet-lot piles for Set Execute Plan, keyed by pile name (luxury,
    /// contemporary, donate, discard, other). Explicit Plan v2 groups win;
    /// older closet-lot Plans keep keyword grouping; other Sets use one group.
    static func executionGroups(for checklist: LiquidationPlanChecklistDTO, isClosetLot: Bool) -> [String: [Int]] {
        let indices = Array(checklist.items.indices)
        let known: Set<String> = ["luxury", "contemporary", "donate", "discard", "other"]

        if checklist.items.contains(where: { $0.group != nil }) {
            var groups: [String: [Int]] = [:]
            for i in indices {
                let g = checklist.items[i].group.flatMap { known.contains($0) ? $0 : nil } ?? "other"
                groups[g, default: []].append(i)
            }
            return groups
        }

        guard isClosetLot else { return ["other": indices] }

        var groups: [String: [Int]] = [:]
        for i in indices {
            groups[legacyGroup(for: checklist.items[i].text), default: []].append(i)
        }
        return groups
    }

    /// Keyword grouping used before Plans carried explicit piles (unchanged).
    private static func legacyGroup(for text: String) -> String {
        let t = text.lowercased()
        if t.contains("hub") || t.contains("mail") || t.contains("ship") || t.contains("insured") || t.contains("authentication") || t.contains("designer") || t.contains("luxury") {
            return "luxury"
        }
        if t.contains("consign") || t.contains("consignment") || t.contains("resale") || t.contains("poshmark") || t.contains("depop") || t.contains("thredup") || t.contains("contemporary") || t.contains("facebook marketplace") {
            return "contemporary"
        }
        if t.contains("donat") || t.contains("charity") || t.contains("thrift") {
            return "donate"
        }
        if t.contains("discard") || t.contains("trash") || t.contains("recycle") || t.contains("damaged") || t.contains("stain") {
            return "discard"
        }
        return "other"
    }

    enum WorkflowError: LocalizedError {
        case unreadablePlan
        case missingStep

        var errorDescription: String? {
            switch self {
            case .unreadablePlan: return "This Plan could not be read."
            case .missingStep: return "That checklist step could not be found."
            }
        }
    }
}
