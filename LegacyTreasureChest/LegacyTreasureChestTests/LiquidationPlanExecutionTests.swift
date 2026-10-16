//
//  LiquidationPlanExecutionTests.swift
//  LegacyTreasureChestTests
//
//  A3: the shared LiquidationWorkflow rules behind the Item, Set, and Set
//  Execute Plan screens: creating and replacing Plans safely, progress after
//  relaunch, outcomes and status, Brief updates that keep the Plan, step
//  actions, Find Help requests, closet-lot piles, and the offline fallbacks.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

// MARK: - Fixtures

private func brief(recommended: LiquidationPathDTO = .pathB_delegateConsign) -> LiquidationBriefDTO {
    LiquidationBriefDTO(
        scope: .item,
        recommendedPath: recommended,
        reasoning: "Specialists reach collectors.",
        pathOptions: [
            .init(path: .pathB_delegateConsign, label: "Specialist camera consignment", effort: .medium),
            .init(path: .pathC_quickExit, label: "Sell to a local shop", effort: .low),
        ],
        actionSteps: []
    )
}

private func generatedPlan(steps: Int = 3, provider: String = "gemini") -> LiquidationPlanChecklistDTO {
    LiquidationPlanChecklistDTO(
        schemaVersion: 2,
        items: (1...steps).map { i in
            .init(order: i, text: "Step \(i)", detail: "Why \(i)", action: i == 1 ? "findSpecialtyHelp" : nil)
        },
        focus: "Sell through a specialist.",
        aiProvider: provider
    )
}

@MainActor
private final class Fixture {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: LTCItem.self, LTCItemSet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func item() -> LTCItem {
        let item = LTCItem(name: "Leica M3", itemDescription: "Film camera.", category: "Electronics", value: 1800)
        context.insert(item)
        return item
    }

    func itemSet() -> LTCItemSet {
        let set = LTCItemSet(name: "Closet", setType: .closetLot)
        context.insert(set)
        return set
    }

    @discardableResult
    func newBrief(_ dto: LiquidationBriefDTO? = nil, owner: LiquidationOwner) throws -> LiquidationBriefRecord {
        try LiquidationWorkflow.recordNewBrief(dto ?? brief(), owner: owner, context: context)
    }

    @discardableResult
    func plan(
        _ chosen: LiquidationPath = .pathB,
        owner: LiquidationOwner,
        generated: LiquidationPlanChecklistDTO? = nil
    ) async throws -> LiquidationPlanRecord {
        let generated = generated ?? generatedPlan()
        let record = try #require(LiquidationWorkflow.activeBrief(owner.state))
        let dto = try #require(LiquidationWorkflow.brief(of: record))
        return try await LiquidationWorkflow.createPlan(
            owner: owner, chosen: chosen, briefRecord: record, brief: dto, context: context
        ) { generated }
    }
}

private struct GenerationFailed: Error {}

private func outcome(_ result: LiquidationOutcomeResult) -> LiquidationPlanOutcomeDTO {
    .fromForm(result: result, amount: 900, currencyCode: "USD", counterparty: "Camera shop",
              date: Date(timeIntervalSince1970: 1_790_000_000), notes: "", previous: nil)
}

// MARK: - Creating and replacing Plans

@MainActor
struct LiquidationPlanReplacementTests {

    @Test func creatingAPlanMakesItActiveWithContextAndProvenance() async throws {
        let f = try Fixture()
        let item = f.item()
        let briefRecord = try f.newBrief(owner: .item(item))
        #expect(item.liquidationStatus == .hasBrief)

        let plan = try await f.plan(owner: .item(item))
        #expect(plan.isActive)
        #expect(plan.derivedFromBriefRecordId == briefRecord.briefRecordId)
        #expect(plan.aiProvider == "gemini")
        #expect(plan.payloadVersion == LiquidationPlanAssembler.payloadVersion)
        #expect(LiquidationWorkflow.checklist(of: plan)?.context?.specificRecommendation == "Specialist camera consignment")
        #expect(item.selectedLiquidationPath == .pathB)
        #expect(item.liquidationStatus == .inProgress)
        #expect(item.liquidationState?.status == .inProgress)
    }

    @Test func failedGenerationLeavesTheCurrentPlanUntouched() async throws {
        let f = try Fixture()
        let item = f.item()
        try f.newBrief(owner: .item(item))
        let current = try await f.plan(owner: .item(item))
        try LiquidationWorkflow.setStep(current.planRecordIdStep(0), completed: true, in: current, owner: .item(item), context: f.context)
        let before = current.payloadJSON

        let briefRecord = try #require(LiquidationWorkflow.activeBrief(item.liquidationState))
        await #expect(throws: GenerationFailed.self) {
            try await LiquidationWorkflow.createPlan(
                owner: .item(item), chosen: .pathC, briefRecord: briefRecord, brief: brief(), context: f.context
            ) { throw GenerationFailed() }
        }
        #expect(item.liquidationState?.plans.count == 1)
        #expect(current.isActive)
        #expect(current.payloadJSON == before)
        #expect(item.selectedLiquidationPath == .pathB)
        #expect(LiquidationWorkflow.activePlan(item.liquidationState) === current)
    }

    @Test func replacingKeepsTheOldPlanAsInactiveHistory() async throws {
        let f = try Fixture()
        let item = f.item()
        try f.newBrief(owner: .item(item))
        let first = try await f.plan(.pathB, owner: .item(item))
        let second = try await f.plan(.pathC, owner: .item(item))

        #expect(item.liquidationState?.plans.count == 2)
        #expect(!first.isActive)
        #expect(second.isActive)
        #expect(LiquidationWorkflow.activePlan(item.liquidationState) === second)
        #expect(item.selectedLiquidationPath == .pathC)
        #expect(LiquidationWorkflow.checklist(of: second)?.context?.wasRecommended == false)
    }

    @Test func confirmationTextStatesWhatWillNotCarryOver() async throws {
        let f = try Fixture()
        let item = f.item()
        try f.newBrief(owner: .item(item))
        let plan = try await f.plan(owner: .item(item))

        let fresh = LiquidationWorkflow.replacementMessage(current: plan, newPlanTitle: "Quick Sale Plan")
        #expect(fresh.contains("No steps in your current Plan have been completed yet."))
        #expect(fresh.contains("The current Plan stays until the new one is ready."))

        try LiquidationWorkflow.setStep(plan.planRecordIdStep(0), completed: true, in: plan, owner: .item(item), context: f.context)
        try LiquidationWorkflow.setStep(plan.planRecordIdStep(1), completed: true, in: plan, owner: .item(item), context: f.context)
        try LiquidationWorkflow.saveOutcome(outcome(.didNotSell), in: plan, owner: .item(item), context: f.context)
        let withProgress = LiquidationWorkflow.replacementMessage(current: plan, newPlanTitle: "Quick Sale Plan")
        #expect(withProgress.contains("The 2 of 3 completed steps and the recorded outcome in your current Plan will not carry over."))

        let pending = LiquidationPendingChange.replace(.pathC)
        #expect(pending.title(currentPlanTitle: "Consignment Plan") == "Replace your Consignment Plan?")
        #expect(pending.isDestructive)
        #expect(!LiquidationPendingChange.updateBrief.isDestructive)
    }
}

// MARK: - Progress, status, and relaunch

@MainActor
struct LiquidationPlanProgressTests {

    @Test func progressPersistsAcrossARelaunch() async throws {
        let f = try Fixture()
        let item = f.item()
        try f.newBrief(owner: .item(item))
        let plan = try await f.plan(owner: .item(item))
        try LiquidationWorkflow.setStep(plan.planRecordIdStep(1), completed: true, in: plan, owner: .item(item), context: f.context)

        // A fresh context reads only what was saved.
        let relaunched = ModelContext(f.container)
        let reread = try #require(try relaunched.fetch(FetchDescriptor<LiquidationPlanRecord>()).first)
        let checklist = try #require(LiquidationWorkflow.checklist(of: reread))
        #expect(checklist.items.map(\.isCompleted) == [false, true, false])
        #expect(checklist.items[0].action == "findSpecialtyHelp")
        #expect(checklist.items[0].detail == "Why 1")
        #expect(checklist.context?.approachName == "Consignment")
        #expect(reread.status == .inProgress)
        #expect(LiquidationWorkflow.progress(checklist).summary == "1 of 3 steps done")
    }

    @Test func tickedBoxesDoNotFinishAPlanV2ButKeepLegacyBehavior() {
        var v2 = LiquidationPlanAssembler.withContext(generatedPlan(steps: 2), chosenPath: .pathB, brief: brief(), briefRecordId: nil)
        #expect(LiquidationWorkflow.planStatus(for: v2) == .notStarted)
        v2.items[0].isCompleted = true
        #expect(LiquidationWorkflow.planStatus(for: v2) == .inProgress)
        v2.items[1].isCompleted = true
        #expect(LiquidationWorkflow.progress(v2).allDone)
        #expect(LiquidationWorkflow.planStatus(for: v2) == .inProgress)  // outcome still needed

        // App 1.2 Plans (no context): all steps done still means Completed.
        var legacy = generatedPlan(steps: 2)
        legacy.items[0].isCompleted = true
        legacy.items[1].isCompleted = true
        #expect(LiquidationWorkflow.planStatus(for: legacy) == .completed)
    }

    @Test func ownerStatusFollowsPlanStatus() {
        #expect(LiquidationWorkflow.ownerStatus(for: .notStarted) == .inProgress)
        #expect(LiquidationWorkflow.ownerStatus(for: .inProgress) == .inProgress)
        #expect(LiquidationWorkflow.ownerStatus(for: .completed) == .completed)
        #expect(LiquidationWorkflow.ownerStatus(for: .onHold) == .onHold)
    }
}

// MARK: - Outcomes

@MainActor
struct LiquidationOutcomeTests {

    @Test func everyOutcomeMapsToTheApprovedStatus() async throws {
        let expected: [(LiquidationOutcomeResult, PlanStatus, LiquidationStatus)] = [
            (.sold, .completed, .completed),
            (.donated, .completed, .completed),
            (.consigned, .inProgress, .inProgress),
            (.kept, .onHold, .onHold),
            (.didNotSell, .onHold, .onHold),
        ]
        let f = try Fixture()
        let item = f.item()
        try f.newBrief(owner: .item(item))
        let plan = try await f.plan(owner: .item(item))

        // Recording, then editing to each result in turn.
        for (result, planStatus, ownerStatus) in expected {
            try LiquidationWorkflow.saveOutcome(outcome(result), in: plan, owner: .item(item), context: f.context)
            #expect(plan.status == planStatus, "\(result)")
            #expect(item.liquidationStatus == ownerStatus, "\(result)")
            #expect(item.liquidationState?.status == ownerStatus, "\(result)")
            #expect(LiquidationWorkflow.checklist(of: plan)?.outcome?.result == result)
        }
        // The inventory itself is untouched by an outcome.
        #expect(item.value == 1800)
        #expect(item.disposition == .liquidate)
    }

    @Test func formCleansTheOutcomeAndKeepsFirstRecordedTime() {
        let first = LiquidationPlanOutcomeDTO.fromForm(
            result: .sold, amount: 1249.6, currencyCode: "USD", counterparty: "  Camera shop ",
            date: .now, notes: "  ", previous: nil, now: Date(timeIntervalSince1970: 100))
        #expect(first.amountReceived == 1250)
        #expect(first.counterparty == "Camera shop")
        #expect(first.notes == nil)
        #expect(first.recordedAt == Date(timeIntervalSince1970: 100))

        let edited = LiquidationPlanOutcomeDTO.fromForm(
            result: .donated, amount: 500, currencyCode: "USD", counterparty: "Goodwill",
            date: .now, notes: "Receipt in folder", previous: first, now: Date(timeIntervalSince1970: 200))
        #expect(edited.amountReceived == nil)          // no amount for a donation
        #expect(edited.currencyCode == nil)
        #expect(edited.recordedAt == first.recordedAt)
        #expect(edited.updatedAt == Date(timeIntervalSince1970: 200))

        let kept = LiquidationPlanOutcomeDTO.fromForm(
            result: .kept, amount: nil, currencyCode: "USD", counterparty: "Someone",
            date: .now, notes: "", previous: nil)
        #expect(kept.counterparty == nil)
        #expect(LiquidationPlanOutcomeDTO.fromForm(result: .consigned, amount: -5, currencyCode: "USD",
                                                   counterparty: "", date: .now, notes: "", previous: nil)
            .amountReceived == 0)
    }

    @Test func outcomeIsNeverADuplicatedStepAndSurvivesToggles() async throws {
        let f = try Fixture()
        let item = f.item()
        try f.newBrief(owner: .item(item))
        let plan = try await f.plan(owner: .item(item))
        try LiquidationWorkflow.saveOutcome(outcome(.consigned), in: plan, owner: .item(item), context: f.context)

        for _ in 0..<5 {
            try LiquidationWorkflow.setStep(plan.planRecordIdStep(2), completed: true, in: plan, owner: .item(item), context: f.context)
            try LiquidationWorkflow.setStep(plan.planRecordIdStep(2), completed: false, in: plan, owner: .item(item), context: f.context)
        }
        let checklist = try #require(LiquidationWorkflow.checklist(of: plan))
        #expect(checklist.items.count == 3)
        #expect(!checklist.items.contains(where: { $0.action == LiquidationStepAction.recordOutcome.rawValue }))
        #expect(checklist.outcome?.result == .consigned)
        #expect(checklist.outcome?.amountReceived == 900)
        #expect(checklist.context?.approachName == "Consignment")
        #expect(plan.status == .inProgress)  // outcome, not checkboxes, decides
    }

    @Test func legacyOutcomeFieldsAndUnknownResultsAreSafe() throws {
        let json = """
        {"schemaVersion": 1, "createdAt": "2026-09-01T00:00:00Z",
         "items": [{"order": 1, "text": "Do it", "isCompleted": true}],
         "outcome": {"result": "auctioned", "date": "2026-09-02T00:00:00Z"}}
        """
        let plan = try #require(LiquidationJSONCoding.tryDecode(LiquidationPlanChecklistDTO.self, from: Data(json.utf8)))
        #expect(plan.outcome == nil)           // unknown result is dropped, not fatal
        #expect(plan.items[0].isCompleted)
        #expect(LiquidationWorkflow.planStatus(for: plan) == .completed)  // legacy rule preserved
    }
}

// MARK: - Brief updates

@MainActor
struct LiquidationBriefUpdateTests {

    @Test func newBriefKeepsPlanProgressAndStatus() async throws {
        let f = try Fixture()
        let item = f.item()
        let firstBrief = try f.newBrief(owner: .item(item))
        let plan = try await f.plan(owner: .item(item))
        try LiquidationWorkflow.setStep(plan.planRecordIdStep(0), completed: true, in: plan, owner: .item(item), context: f.context)
        try LiquidationWorkflow.saveOutcome(outcome(.sold), in: plan, owner: .item(item), context: f.context)
        let before = plan.payloadJSON

        try f.newBrief(brief(recommended: .donate), owner: .item(item))

        #expect(plan.isActive)
        #expect(plan.payloadJSON == before)
        #expect(item.liquidationStatus == .completed)    // not reset to "Brief ready"
        #expect(item.selectedLiquidationPath == .pathB)  // new recommendation not adopted
        #expect(LiquidationWorkflow.isBasedOnEarlierBrief(plan, activeBrief: LiquidationWorkflow.activeBrief(item.liquidationState)))
        #expect(LiquidationWorkflow.earlierBriefDate(for: plan, in: item.liquidationState) == firstBrief.createdAt)
    }

    @Test func keepThisPlanSilencesTheNoticeUntilTheNextBrief() async throws {
        let f = try Fixture()
        let item = f.item()
        try f.newBrief(owner: .item(item))
        let plan = try await f.plan(owner: .item(item))
        let second = try f.newBrief(owner: .item(item))

        try LiquidationWorkflow.keepPlan(plan, with: second, context: f.context)
        #expect(!LiquidationWorkflow.isBasedOnEarlierBrief(plan, activeBrief: second))
        #expect(LiquidationWorkflow.earlierBriefDate(for: plan, in: item.liquidationState) == nil)

        let third = try f.newBrief(owner: .item(item))
        #expect(LiquidationWorkflow.isBasedOnEarlierBrief(plan, activeBrief: third))
    }

    @Test func plansWithoutBriefProvenanceNeverWarn() throws {
        let f = try Fixture()
        let item = f.item()
        let state = item.liquidationState ?? LiquidationOwner.item(item).ensureState(in: f.context)
        // An app 1.2 Plan: no originating Brief recorded anywhere.
        let legacy = LiquidationPlanRecord(chosenPath: .pathB, payloadJSON: try LiquidationJSONCoding.encode(generatedPlan()))
        legacy.state = state
        f.context.insert(legacy)
        state.plans.append(legacy)
        let newBrief = try f.newBrief(owner: .item(item))
        #expect(!LiquidationWorkflow.isBasedOnEarlierBrief(legacy, activeBrief: newBrief))
    }

    @Test func firstBriefWithoutAPlanReadsBriefReady() throws {
        let f = try Fixture()
        let set = f.itemSet()
        try f.newBrief(owner: .itemSet(set))
        #expect(set.liquidationState?.status == .hasBrief)
    }
}

// MARK: - Actions, Find Help, and Sets

@MainActor
struct LiquidationPlanActionTests {

    @Test func stepActionsParseSafely() {
        func step(_ action: String?) -> LiquidationChecklistItemDTO { .init(order: 1, text: "x", action: action) }
        #expect(LiquidationStepAction(step: step("findHelp")) == .findHelp)
        #expect(LiquidationStepAction(step: step("findSpecialtyHelp"))?.title == "Find Help")
        #expect(LiquidationStepAction(step: step("viewBrief")) == .viewBrief)
        #expect(LiquidationStepAction(step: step("recordOutcome")) == .recordOutcome)
        #expect(LiquidationStepAction(step: step("phoneThem")) == nil)
        #expect(LiquidationStepAction(step: step(nil)) == nil)
    }

    @Test func findHelpRequestCarriesThePlanContextForInitiativeB() async throws {
        let f = try Fixture()
        let set = f.itemSet()
        try f.newBrief(owner: .itemSet(set))
        var generated = generatedPlan()
        generated.items[0].group = "luxury"
        let plan = try await f.plan(owner: .itemSet(set), generated: generated)
        let step = try #require(LiquidationWorkflow.checklist(of: plan)?.items[0])

        let request = LiquidationWorkflow.findHelpRequest(plan: plan, step: step, action: .findSpecialtyHelp)
        #expect(request.planRecordId == plan.planRecordId)
        #expect(request.stepID == step.id)
        #expect(request.wantsSpecialist)
        #expect(request.group == "luxury")
        #expect(request.approach == .pathB_delegateConsign)
        #expect(request.specificRecommendation == "Specialist camera consignment")

        // Opening Find Help changes nothing about the step.
        #expect(LiquidationWorkflow.checklist(of: plan)?.items[0].isCompleted == false)
    }

    @Test func setPlansFollowTheSameRules() async throws {
        let f = try Fixture()
        let set = f.itemSet()
        try f.newBrief(owner: .itemSet(set))
        let plan = try await f.plan(owner: .itemSet(set))
        #expect(set.liquidationState?.status == .inProgress)

        try LiquidationWorkflow.setStep(plan.planRecordIdStep(0), completed: true, in: plan, owner: .itemSet(set), context: f.context)
        #expect(plan.status == .inProgress)
        try LiquidationWorkflow.saveOutcome(outcome(.donated), in: plan, owner: .itemSet(set), context: f.context)
        #expect(plan.status == .completed)
        #expect(set.liquidationState?.status == .completed)
    }

    @Test func closetLotPilesUseExplicitGroupsThenLegacyKeywords() {
        let explicit = LiquidationPlanChecklistDTO(items: [
            .init(order: 1, text: "Split the lot", group: "other"),
            .init(order: 2, text: "Mail designer pieces", group: "luxury"),
            .init(order: 3, text: "Bag the rest", group: "charity"),   // unknown pile
        ])
        #expect(LiquidationWorkflow.executionGroups(for: explicit, isClosetLot: true)
                == ["other": [0, 2], "luxury": [1]])

        let legacy = LiquidationPlanChecklistDTO(items: [
            .init(order: 1, text: "Ship designer items to the hub"),
            .init(order: 2, text: "List contemporary pieces on Poshmark"),
            .init(order: 3, text: "Drop everyday clothes at a thrift store"),
            .init(order: 4, text: "Recycle stained items"),
            .init(order: 5, text: "Take a break"),
        ])
        #expect(LiquidationWorkflow.executionGroups(for: legacy, isClosetLot: true)
                == ["luxury": [0], "contemporary": [1], "donate": [2], "discard": [3], "other": [4]])
        #expect(LiquidationWorkflow.executionGroups(for: legacy, isClosetLot: false) == ["other": [0, 1, 2, 3, 4]])
    }

    @Test func basicPlansWorkThroughTheSameWorkflow() async throws {
        let f = try Fixture()
        let item = f.item()
        try f.newBrief(owner: .item(item))
        let plan = try await f.plan(owner: .item(item), generated: generatedPlan(provider: LocalLiquidationPlanGenerator.providerName))
        let checklist = try #require(LiquidationWorkflow.checklist(of: plan))
        #expect(checklist.isBasicPlan)
        #expect(checklist.context?.generator == LiquidationPlanContextDTO.basicGenerator)
        try LiquidationWorkflow.saveOutcome(outcome(.sold), in: plan, owner: .item(item), context: f.context)
        #expect(plan.status == .completed)
    }
}

// MARK: - Related fixes

@MainActor
struct LiquidationRelatedFixTests {

    @Test func offlineBriefFallbackNowTriggersForNormalizedNetworkErrors() {
        #expect(LiquidationAIService.allowsBasicBriefFallback(for: AIError.offline(requestID: "r")))
        #expect(LiquidationAIService.allowsBasicBriefFallback(for: AIError.timeout(requestID: "r")))
        #expect(LiquidationAIService.allowsBasicBriefFallback(for: URLError(.notConnectedToInternet)))
        #expect(!LiquidationAIService.allowsBasicBriefFallback(for: AIError.serviceUnavailable(requestID: "r")))
        #expect(!LiquidationAIService.allowsBasicBriefFallback(for: AIError.unexpectedResponse(requestID: "r")))
        #expect(!LiquidationAIService.allowsBasicBriefFallback(for: AIError.rateLimited(requestID: "r")))
    }

    @Test func offlineBriefIsLabeledAndPlainlyWorded() {
        let req = LiquidationBriefRequest(scope: .item, title: "Mantel clock", category: "Decor", quantity: 1, unitValue: 400)
        let dto = LocalLiquidationBriefGenerator().generate(from: req)
        let p = LiquidationBriefPresentation(dto: dto)
        #expect(p.isBasicBrief)
        #expect(!p.reasoning.contains("fallback"))
        #expect(!p.reasoning.contains("—"))
        #expect(!LiquidationBriefPresentation(dto: brief()).isBasicBrief)
    }

    @Test func setPlanRequestsIncludeMemberPhotoCounts() throws {
        let f = try Fixture()
        let set = LTCItemSet(name: "Noritake china", setType: .china)
        let plate = LTCItem(name: "Dinner plate", itemDescription: "", category: "China & Crystal", value: 15, quantity: 12)
        f.context.insert(set)
        f.context.insert(plate)
        plate.images.append(ItemImage(filePath: "a.jpg"))
        plate.images.append(ItemImage(filePath: "b.jpg"))
        let m = LTCItemSetMembership()
        f.context.insert(m)
        m.item = plate
        m.itemSet = set

        let req = try LiquidationRequestBuilder.buildPlanRequest(for: set, chosenPath: .pathB, brief: brief())
        #expect(req.setContext?.memberSummaries.first?.photoCount == 2)
        let body = String(decoding: try JSONEncoder().encode(req), as: UTF8.self)
        #expect(!body.contains("a.jpg"))
    }
}

// MARK: - Helpers

private extension LiquidationPlanRecord {
    /// The ID of the step at `index` in this Plan's saved checklist.
    func planRecordIdStep(_ index: Int) -> UUID {
        LiquidationWorkflow.checklist(of: self)!.items.sorted(by: { $0.order < $1.order })[index].id
    }
}
