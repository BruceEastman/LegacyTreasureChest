//
//  LiquidationPlanV2Tests.swift
//  LegacyTreasureChestTests
//
//  A2: Plan v2 persistence (old Plans, new fields surviving checkbox toggles),
//  saved strategy context, Plan request contents, Create a Plan Anyway, the
//  basic offline Plan, and when it may be used.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

// MARK: - Fixtures

/// A Plan exactly as app 1.2 saved it, with some progress.
private let legacyPlanJSON = """
{
  "schemaVersion": 1,
  "createdAt": "2026-09-01T12:00:00Z",
  "items": [
    {"id": "AAAAAAAA-0000-0000-0000-000000000001", "order": 1, "text": "Identify 1–3 consignors",
     "isCompleted": true, "completedAt": "2026-09-02T09:00:00Z"},
    {"id": "AAAAAAAA-0000-0000-0000-000000000002", "order": 2, "text": "Prepare intake packet",
     "isCompleted": false},
    {"id": "AAAAAAAA-0000-0000-0000-000000000003", "order": 3, "text": "AI recommended: pathB_delegateConsign.",
     "isCompleted": false, "userNotes": "Called Tuesday"}
  ]
}
"""

/// A Plan as the A2 Gateway returns it (fractional seconds, explicit nulls).
private let gatewayPlanJSON = """
{
  "schemaVersion": 2,
  "createdAt": "2026-10-16T18:04:05.123456Z",
  "focus": "Sell through a camera specialist after confirming the shutter works.",
  "aiProvider": "gemini",
  "aiModel": "gemini-2.5-flash",
  "items": [
    {"order": 1, "text": "Fire the shutter at several speeds", "detail": "Specialists ask about shutter accuracy.",
     "action": null, "group": null, "isCompleted": false, "completedAt": null, "userNotes": null},
    {"order": 2, "text": "Shortlist two camera consignors", "detail": null,
     "action": "findSpecialtyHelp", "group": null, "isCompleted": false, "completedAt": null, "userNotes": null}
  ]
}
"""

private func decodeGateway<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { dec in
        let s = try dec.singleValueContainer().decode(String.self)
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: s) { return d }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: s))
    }
    return try decoder.decode(type, from: Data(json.utf8))
}

/// What the Item and Set screens do on a checkbox tap: decode, edit, re-encode.
private func toggled(_ data: Data, stepID: UUID, to value: Bool) throws -> Data {
    var checklist = try #require(LiquidationJSONCoding.tryDecode(LiquidationPlanChecklistDTO.self, from: data))
    let idx = try #require(checklist.items.firstIndex(where: { $0.id == stepID }))
    checklist.items[idx].isCompleted = value
    checklist.items[idx].completedAt = value ? .now : nil
    return try LiquidationJSONCoding.encode(checklist)
}

private func cameraBrief(recommended: LiquidationPathDTO = .pathB_delegateConsign) -> LiquidationBriefDTO {
    LiquidationBriefDTO(
        scope: .item,
        generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
        recommendedPath: recommended,
        reasoning: "Collectors pay more through camera specialists.",
        pathOptions: [
            .init(path: .pathA_maximizePrice, label: "Sell online yourself", effort: .high),
            .init(path: .pathB_delegateConsign, label: "Specialist camera consignment",
                  netProceeds: MoneyRangeDTO(low: 1100, likely: 1300, high: 1500), effort: .medium,
                  timeEstimate: "3 to 8 weeks", risks: ["Commission", "Payout delays", "Grading", "Shipping"]),
            .init(path: .pathC_quickExit, label: "Sell to a local camera shop", effort: .low),
        ],
        actionSteps: [],
        missingDetails: ["Whether the shutter fires accurately"],
        specialty: LiquidationSpecialtyDTO(itemKind: "film camera", brand: "Leica", model: "M3", isSpecialistItem: true)
    )
}

// MARK: - Persistence

struct LiquidationPlanPersistenceTests {

    @Test func legacyPlanDecodesAndKeepsProgressThroughToggles() throws {
        let data = Data(legacyPlanJSON.utf8)
        let plan = try #require(LiquidationJSONCoding.tryDecode(LiquidationPlanChecklistDTO.self, from: data))
        #expect(plan.context == nil)
        #expect(plan.focus == nil)
        #expect(!plan.isBasicPlan)
        #expect(plan.items.map(\.isCompleted) == [true, false, false])

        let step2 = plan.items[1].id
        let after = try #require(LiquidationJSONCoding.tryDecode(
            LiquidationPlanChecklistDTO.self, from: try toggled(data, stepID: step2, to: true)))
        #expect(after.items.map(\.isCompleted) == [true, true, false])
        #expect(after.items[0].completedAt == plan.items[0].completedAt)
        #expect(after.items[2].userNotes == "Called Tuesday")
        #expect(after.items.map(\.id) == plan.items.map(\.id))
    }

    @Test func planV2FieldsSurviveCheckboxTogglesAndReopening() throws {
        let generated = try decodeGateway(LiquidationPlanChecklistDTO.self, gatewayPlanJSON)
        let withContext = LiquidationPlanAssembler.withContext(
            generated, chosenPath: .pathB, brief: cameraBrief(), briefRecordId: UUID())
        let saved = try LiquidationJSONCoding.encode(withContext)

        // Check, uncheck, check again: what a homeowner does in the checklist.
        let id = withContext.items[1].id
        var data = try toggled(saved, stepID: id, to: true)
        data = try toggled(data, stepID: id, to: false)
        data = try toggled(data, stepID: id, to: true)

        let reopened = try #require(LiquidationJSONCoding.tryDecode(LiquidationPlanChecklistDTO.self, from: data))
        #expect(reopened.items[1].isCompleted)
        #expect(reopened.focus == withContext.focus)
        #expect(reopened.aiProvider == "gemini")
        #expect(reopened.context == withContext.context)
        for (a, b) in zip(reopened.items, withContext.items) {
            #expect(a.id == b.id)
            #expect(a.detail == b.detail)
            #expect(a.action == b.action)
            #expect(a.group == b.group)
        }
        #expect(reopened.items[0].detail == "Specialists ask about shutter accuracy.")
        #expect(reopened.items[1].action == "findSpecialtyHelp")
    }

    @Test func closetLotGroupsSurviveToggles() throws {
        let plan = LiquidationPlanChecklistDTO(schemaVersion: 2, items: [
            .init(order: 1, text: "Split the lot into piles", group: "other"),
            .init(order: 2, text: "Mail designer pieces to a luxury consignor", group: "luxury"),
        ])
        let data = try toggled(try LiquidationJSONCoding.encode(plan), stepID: plan.items[1].id, to: true)
        let reopened = try #require(LiquidationJSONCoding.tryDecode(LiquidationPlanChecklistDTO.self, from: data))
        #expect(reopened.items.map(\.group) == ["other", "luxury"])
    }

    @Test func malformedOptionalFieldsNeverMakeAPlanUnreadable() throws {
        let json = """
        {"schemaVersion": "two", "createdAt": "2026-10-16T00:00:00Z", "focus": 7, "context": "camera",
         "items": [{"order": 1, "text": "Shortlist consignors", "detail": ["x"], "action": 5, "group": false}]}
        """
        let plan = try #require(LiquidationJSONCoding.tryDecode(LiquidationPlanChecklistDTO.self, from: Data(json.utf8)))
        #expect(plan.schemaVersion == 1)
        #expect(plan.focus == nil)
        #expect(plan.context == nil)
        #expect(plan.items[0].text == "Shortlist consignors")
        #expect(plan.items[0].detail == nil && plan.items[0].action == nil && plan.items[0].group == nil)
    }
}

// MARK: - Saved strategy context

struct LiquidationPlanContextTests {

    @Test func chosenStrategyNotRecommendationIsSaved() throws {
        let plan = LiquidationPlanChecklistDTO(items: [.init(order: 1, text: "Post it locally")], aiProvider: "gemini")
        let briefID = UUID()
        let ctx = try #require(LiquidationPlanAssembler.withContext(
            plan, chosenPath: .pathC, brief: cameraBrief(), briefRecordId: briefID).context)

        #expect(ctx.chosenPath == .pathC_quickExit)
        #expect(ctx.approachName == "Quick Sale")
        #expect(ctx.specificRecommendation == "Sell to a local camera shop")
        #expect(!ctx.wasRecommended)
        #expect(ctx.recommendedPath == .pathB_delegateConsign)
        #expect(!ctx.isProvisional)
        #expect(ctx.briefRecordId == briefID)
        #expect(ctx.generator == LiquidationPlanContextDTO.aiGenerator)
        #expect(LiquidationPlanContextHeader.choiceNote(ctx) == "Your choice (the Brief recommended Consignment).")
    }

    @Test func specialtyAndSpecificRecommendationSurviveReopening() throws {
        let plan = LiquidationPlanChecklistDTO(items: [.init(order: 1, text: "Shortlist consignors")])
        let withCtx = LiquidationPlanAssembler.withContext(plan, chosenPath: .pathB, brief: cameraBrief(), briefRecordId: nil)
        let reopened = try #require(LiquidationJSONCoding.tryDecode(
            LiquidationPlanChecklistDTO.self, from: try LiquidationJSONCoding.encode(withCtx)))
        let ctx = try #require(reopened.context)
        #expect(ctx.specificRecommendation == "Specialist camera consignment")
        #expect(ctx.wasRecommended)
        #expect(ctx.specialty?.brand == "Leica")
        #expect(ctx.estimatedNet == MoneyRangeDTO(low: 1100, likely: 1300, high: 1500))
        #expect(ctx.keyRisks == ["Commission", "Payout delays", "Grading"])
        #expect(LiquidationPlanContextHeader.choiceNote(ctx) == nil)
    }

    @Test func contextIsStableWhenALaterBriefChanges() throws {
        let plan = LiquidationPlanAssembler.withContext(
            LiquidationPlanChecklistDTO(items: [.init(order: 1, text: "Shortlist consignors")]),
            chosenPath: .pathB, brief: cameraBrief(), briefRecordId: nil)
        // A new Brief recommending Donation does not touch the saved Plan JSON.
        _ = cameraBrief(recommended: .donate)
        #expect(plan.context?.recommendedPath == .pathB_delegateConsign)
        #expect(plan.context?.approachName == "Consignment")
    }
}

// MARK: - Plan requests

@MainActor
struct LiquidationPlanRequestTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(for: LTCItem.self, LTCItemSet.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func itemRequestCarriesContextButNoFiles() throws {
        let container = try container()
        let item = LTCItem(name: "Leica M3 camera", itemDescription: "Leica M3 with 50mm lens. Maker: Leica.",
                           category: "Electronics", value: 1800)
        container.mainContext.insert(item)
        item.valuation = ItemValuation(valueLow: 1400, estimatedValue: 1800, valueHigh: 2200,
                                       aiNotes: "Recent M3 sales.")
        item.images.append(ItemImage(filePath: "a.jpg"))
        item.images.append(ItemImage(filePath: "b.jpg"))
        item.documents.append(Document(filePath: "r.pdf", documentType: "Receipt"))

        let req = try LiquidationRequestBuilder.buildPlanRequest(for: item, chosenPath: .pathB, brief: cameraBrief())
        #expect(req.schemaVersion == 2)
        #expect(req.chosenPath == .pathB_delegateConsign)
        #expect(req.selectedOption?.label == "Specialist camera consignment")
        #expect(req.isRecommended == true)
        let ctx = try #require(req.itemContext)
        #expect(ctx.description == "Leica M3 with 50mm lens. Maker: Leica.")
        #expect(ctx.photoCount == 2)
        #expect(ctx.documentCount == 1)
        #expect(ctx.documentTypes == ["Receipt"])
        #expect(ctx.hasAudioStory == false)
        #expect(ctx.valuationLow == 1400 && ctx.valuationHigh == 2200)
        #expect(ctx.valuationNotes == "Recent M3 sales.")

        // Only metadata is sent: no file paths or image data.
        let body = String(decoding: try JSONEncoder().encode(req), as: UTF8.self)
        #expect(!body.contains("a.jpg") && !body.contains("r.pdf") && !body.contains("photoJpegBase64"))
        #expect(body.contains("\"specialty\""))
    }

    @Test func staleValuationRangeIsNotSent() throws {
        let container = try container()
        let item = LTCItem(name: "Clock", itemDescription: "", category: "Decor", value: 900)
        container.mainContext.insert(item)
        item.valuation = ItemValuation(valueLow: 100, estimatedValue: 150, valueHigh: 200, aiNotes: "Old estimate")
        let ctx = try #require(try LiquidationRequestBuilder.buildPlanRequest(
            for: item, chosenPath: .pathC, brief: cameraBrief()).itemContext)
        #expect(ctx.unitValue == 900)
        #expect(ctx.valuationLow == nil && ctx.valuationHigh == nil && ctx.valuationNotes == nil)
        #expect(ctx.description == nil)
    }

    @Test func setRequestCarriesSetContext() throws {
        let container = try container()
        let set = LTCItemSet(name: "Noritake china", setType: .china)
        let plate = LTCItem(name: "Dinner plate", itemDescription: "", category: "China & Crystal", value: 15, quantity: 12)
        container.mainContext.insert(set)
        container.mainContext.insert(plate)
        let m = LTCItemSetMembership()
        container.mainContext.insert(m)
        m.item = plate
        m.itemSet = set

        let req = try LiquidationRequestBuilder.buildPlanRequest(for: set, chosenPath: .pathB, brief: cameraBrief())
        #expect(req.scope == .set)
        #expect(req.itemContext == nil)
        let ctx = try #require(req.setContext)
        #expect(ctx.setType == SetType.china.rawValue)
        #expect(ctx.memberSummaries.map(\.title) == ["Dinner plate"])
    }

    @Test func needsInfoIsNeverSentAsTheChosenApproach() throws {
        let container = try container()
        let item = LTCItem(name: "Figurine", itemDescription: "", category: "Decor")
        container.mainContext.insert(item)
        #expect(throws: LiquidationRequestBuilder.PlanRequestError.self) {
            _ = try LiquidationRequestBuilder.buildPlanRequest(for: item, chosenPath: .needsInfo, brief: cameraBrief())
        }
    }

    @Test func createAPlanAnywayKeepsTheChosenApproachAndIsProvisional() throws {
        let container = try container()
        let item = LTCItem(name: "Figurine", itemDescription: "", category: "Decor")
        container.mainContext.insert(item)
        let brief = cameraBrief(recommended: .needsInfo)

        // All four approaches stay available, none marked recommended.
        #expect(LiquidationBriefPresentation.selectableApproaches(recommended: .needsInfo) == [.pathA, .pathB, .pathC, .donate])

        let req = try LiquidationRequestBuilder.buildPlanRequest(for: item, chosenPath: .donate, brief: brief)
        #expect(req.chosenPath == .donate)
        #expect(req.isRecommended == false)

        let ctx = try #require(LiquidationPlanAssembler.withContext(
            LiquidationPlanChecklistDTO(items: [.init(order: 1, text: "Find a donation center")]),
            chosenPath: .donate, brief: brief, briefRecordId: nil).context)
        #expect(ctx.isProvisional)
        #expect(ctx.chosenPath == .donate)
        #expect(LiquidationPlanContextHeader.choiceNote(ctx) == UserFacingTerms.Liquidation.provisionalPlanNotice)
    }
}

// MARK: - Basic offline Plan

struct LiquidationBasicPlanTests {

    private func request(_ path: LiquidationPathDTO, brief: LiquidationBriefDTO = cameraBrief()) -> LiquidationPlanRequest {
        LiquidationPlanRequest(schemaVersion: 2, scope: .item, chosenPath: path, brief: brief,
                               title: "Leica M3 camera", category: "Electronics",
                               selectedOption: brief.pathOptions.first(where: { $0.path == path }))
    }

    @Test func basicPlansAreShortSpecificAndLabeled() {
        for path in [LiquidationPathDTO.pathA_maximizePrice, .pathB_delegateConsign, .pathC_quickExit, .donate] {
            let plan = LocalLiquidationPlanGenerator().generate(from: request(path))
            #expect((3...4).contains(plan.items.count), "\(path)")
            #expect(plan.items.map(\.order) == Array(1...plan.items.count))
            #expect(plan.aiProvider == LocalLiquidationPlanGenerator.providerName)
            for step in plan.items {
                #expect(!step.text.contains("path") && !step.text.contains("AI recommended"), "\(step.text)")
            }
            let ctx = LiquidationPlanAssembler.withContext(plan, chosenPath: path.appPath,
                                                           brief: cameraBrief(), briefRecordId: nil)
            #expect(ctx.isBasicPlan)
            #expect(ctx.context?.generator == LiquidationPlanContextDTO.basicGenerator)
        }
        let consign = LocalLiquidationPlanGenerator().generate(from: request(.pathB_delegateConsign))
        #expect(consign.items[0].action == "findSpecialtyHelp")
        #expect(consign.items[0].detail == "The Brief suggests: Specialist camera consignment.")
    }

    @Test func provisionalBasicPlanStartsWithTheMissingDetail() {
        let plan = LocalLiquidationPlanGenerator().generate(from: request(.donate, brief: cameraBrief(recommended: .needsInfo)))
        #expect(plan.items.first?.text == "Confirm the key missing detail: Whether the shutter fires accurately")
    }

    @Test func basicPlanOnlyForConnectivityOrTemporaryUnavailability() {
        let allowed: [Error] = [AIError.offline(requestID: "r"), AIError.timeout(requestID: "r"),
                                AIError.temporarilyUnavailable(requestID: "r"),
                                AIError.serviceUnavailable(requestID: "r"), URLError(.notConnectedToInternet)]
        let refused: [Error] = [AIError.unexpectedResponse(requestID: "r"), AIError.rateLimited(requestID: "r"),
                                AIError.consentRequired, AIError.invalidRequest("x"),
                                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad")),
                                LiquidationRequestBuilder.PlanRequestError.noApproachChosen]
        for e in allowed { #expect(LiquidationAIService.allowsBasicPlanFallback(for: e), "\(e)") }
        for e in refused { #expect(!LiquidationAIService.allowsBasicPlanFallback(for: e), "\(e)") }
    }
}
