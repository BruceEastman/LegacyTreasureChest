//
//  ItemAnalysisRequestTests.swift
//  LegacyTreasureChestTests
//
//  1.3 Stage 3: Improve with AI request context, transport and consent.
//  Requests go to a URLProtocol stub; nothing reaches the network.
//

import Foundation
import SwiftData
import Testing
@testable import LegacyTreasureChest

// MARK: - Context (source labels)

@MainActor
struct ItemAnalysisContextTests {

    private func item(description: String, llm: String?, notes: String? = nil, quantity: Int = 1) throws -> (LTCItem, ModelContext) {
        let context = ModelContext(try ModelContainer(for: LTCItem.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let item = LTCItem(name: "Stools", itemDescription: description, category: "Furniture", quantity: quantity)
        item.llmGeneratedDescription = llm
        if let notes { item.valuation = ItemValuation(userNotes: notes) }
        context.insert(item)
        return (item, context)
    }

    @Test func ownerWrittenDescription() throws {
        let (item, _) = try item(description: "My grandmother's stools.", llm: nil, notes: "  Stamp under seat. ", quantity: 4)
        let ctx = ItemAnalysisRequestBuilder.context(for: item)
        #expect(ctx.quantity == 4)
        #expect(ctx.ownerNotes == "Stamp under seat.")
        #expect(ctx.savedDescription == [.init(origin: .owner, text: "My grandmother's stools.")])
        #expect(ctx.priorAttributes == nil)
    }

    @Test func earlierAIParagraphIsLabeledAndAttributesMapped() throws {
        let description = "Cherry stool.\n\nBrand: Lexington • Era: 1990s • Materials: cherry\n\nBought in 2007."
        let (item, _) = try item(description: description, llm: "Cherry stool.")
        let ctx = ItemAnalysisRequestBuilder.context(for: item)
        #expect(ctx.savedDescription == [
            .init(origin: .priorAI, text: "Cherry stool."),
            .init(origin: .owner, text: "Bought in 2007."),
        ])
        #expect(ctx.priorAttributes == ["brand": "Lexington", "eraOrYear": "1990s", "materials": "cherry"])
    }

    @Test func editedAIDescriptionIsMixed() throws {
        let (item, _) = try item(description: "Cherry stool, recaned in 1985.", llm: "Cherry stool.")
        #expect(ItemAnalysisRequestBuilder.context(for: item).savedDescription == [
            .init(origin: .mixed, text: "Cherry stool, recaned in 1985."),
        ])
    }

    @Test func emptyDescriptionSendsNoParts() throws {
        let (item, _) = try item(description: "", llm: nil)
        let ctx = ItemAnalysisRequestBuilder.context(for: item)
        #expect(ctx.savedDescription.isEmpty)
        #expect(ctx.ownerNotes == nil)
        #expect(ctx.quantity == 1)
    }

    @Test func legacyHintsMatchLTC12() throws {
        let (item, _) = try item(description: "Base text", llm: nil, notes: "Owner note")
        let hints = ItemAnalysisRequestBuilder.legacyHints(for: item)
        #expect(hints.userWrittenTitle == "Stools")
        #expect(hints.userWrittenDescription == "Base text\n\nAdditional details from owner:\nOwner note")
        #expect(hints.knownCategory == "Furniture")
    }

    @Test func routing() {
        let ctx = ItemAnalysisContextDTO(quantity: 1, ownerNotes: nil, savedDescription: [], priorAttributes: nil)
        let text = ItemAnalysisRequest(hints: ItemAIHints(), context: ctx, primaryJPEG: nil, supplementary: [])
        #expect(!text.usesPhotoEndpoint && !text.carriesEvidence)
        let photo = ItemAnalysisRequest(hints: ItemAIHints(), context: ctx, primaryJPEG: Data([0xFF]), supplementary: [])
        #expect(photo.usesPhotoEndpoint && !photo.carriesEvidence)
        let docOnly = ItemAnalysisRequest(hints: ItemAIHints(), context: ctx, primaryJPEG: nil,
                                          supplementary: [.documentPage(Data([0xFF]), document: 1, page: 1, of: 1)])
        #expect(docOnly.usesPhotoEndpoint && docOnly.carriesEvidence)
    }
}

// MARK: - Consent versions

@MainActor
struct ConsentVersionTests {

    private func manager() -> (AICloudConsentManager, UserDefaults) {
        let suite = "consent-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AICloudConsentManager(defaults: defaults), defaults)
    }

    @Test func freshInstallHasNoConsent() {
        let (consent, _) = manager()
        #expect(consent.acceptedDisclosureVersion == 0)
        #expect(!consent.isOnlineProcessingAllowed)
        #expect(!consent.isEvidenceDisclosureAccepted)
    }

    @Test func ownerWhoConsentedBeforeVersioningHasVersionOne() {
        let (consent, defaults) = manager()
        defaults.set(AICloudConsentStatus.granted.rawValue, forKey: AppConstants.StorageKeys.aiCloudConsentStatus)
        #expect(consent.isOnlineProcessingAllowed)            // existing AI keeps working
        #expect(consent.acceptedDisclosureVersion == 1)
        #expect(!consent.isEvidenceDisclosureAccepted)        // must see the expanded text once
    }

    @Test func grantRecordsCurrentVersionAndDeclineOrResetClearsIt() {
        let (consent, defaults) = manager()
        consent.grant()
        #expect(consent.acceptedDisclosureVersion == AICloudConsentManager.currentDisclosureVersion)
        #expect(consent.isEvidenceDisclosureAccepted)
        consent.decline()
        #expect(consent.acceptedDisclosureVersion == 0)
        consent.grant()
        consent.reset()
        #expect(defaults.object(forKey: AppConstants.StorageKeys.aiCloudConsentDisclosureVersion) == nil)
        #expect(!consent.isOnlineProcessingAllowed)
    }

    @Test func gateShowsExpandedDisclosureOnlyForEvidence() async {
        let (consent, defaults) = manager()
        defaults.set(AICloudConsentStatus.granted.rawValue, forKey: AppConstants.StorageKeys.aiCloudConsentStatus)
        let gate = AIConsentGate(consent: consent)

        var ran = 0
        await gate.perform { ran += 1 }                        // single-photo / text: unchanged
        #expect(ran == 1)
        #expect(!gate.isPresentingConsent)

        await gate.perform(requiresEvidenceDisclosure: true) { ran += 1 }
        #expect(ran == 1)                                      // held until accepted
        #expect(gate.isPresentingConsent)
        #expect(gate.presentationMode == .evidenceUpdate)

        // "Not Now" in update mode: action dropped, existing consent kept.
        gate.handleDecision(.declined)
        #expect(consent.isOnlineProcessingAllowed)

        await gate.perform(requiresEvidenceDisclosure: true) { ran += 1 }
        consent.grant()                                        // "Continue"
        gate.handleDecision(.granted)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ran == 2)
        #expect(consent.isEvidenceDisclosureAccepted)
    }

    @Test func gateUsesStandardModeWithoutAnyConsent() async {
        let (consent, _) = manager()
        let gate = AIConsentGate(consent: consent)
        await gate.perform(requiresEvidenceDisclosure: true) { }
        #expect(gate.presentationMode == .standard)
    }
}

// MARK: - Transport (BackendAIProvider)

@MainActor
@Suite(.serialized)
struct EvidenceTransportTests {

    private let base = URL(string: "http://stub.local")!

    private func provider(consentVersion: Int) -> BackendAIProvider {
        let suite = "transport-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let consent = AICloudConsentManager(defaults: defaults)
        if consentVersion >= 2 {
            consent.grant()
        } else if consentVersion == 1 {
            defaults.set(AICloudConsentStatus.granted.rawValue, forKey: AppConstants.StorageKeys.aiCloudConsentStatus)
        }
        StubURLProtocol.reset()
        return BackendAIProvider(baseURL: base, urlSession: StubURLProtocol.session(), consent: consent)
    }

    private let ctx = ItemAnalysisContextDTO(quantity: 4, ownerNotes: "Stamp under seat",
                                             savedDescription: [.init(origin: .priorAI, text: "Cherry stool.")],
                                             priorAttributes: ["materials": "cherry"])
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x01])

    private func evidenceRequest() -> ItemAnalysisRequest {
        ItemAnalysisRequest(
            hints: ItemAIHints(userWrittenTitle: "Stools", knownCategory: "Furniture"),
            context: ctx,
            primaryJPEG: jpeg,
            supplementary: [.photo(jpeg), .documentPage(jpeg, document: 1, page: 1, of: 2),
                            .documentPage(jpeg, document: 1, page: 2, of: 2)]
        )
    }

    private func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @Test func evidenceNeedsExpandedDisclosureBeforeAnyRequest() async {
        let p = provider(consentVersion: 1)
        await #expect(throws: AIError.self) { try await p.analyzeItem(self.evidenceRequest()) }
        #expect(StubURLProtocol.recorded.isEmpty)
        do { _ = try await p.analyzeItem(evidenceRequest()) } catch let e as AIError {
            if case .consentRequired = e {} else { Issue.record("expected consentRequired, got \(e)") }
        } catch { Issue.record("\(error)") }
    }

    @Test func evidenceRequestShapeTimeoutAndReceipt() async throws {
        let p = provider(consentVersion: 2)
        StubURLProtocol.handler = { _, _ in (200, analysisResponseJSON(summary: summaryJSON(primary: true, photos: 1, pages: 2, quantity: 4))) }
        let result = try await p.analyzeItem(evidenceRequest())
        #expect(result.inputSummary?.documentPages == 2)

        let sent = StubURLProtocol.recorded
        #expect(sent.count == 1)
        #expect(sent[0].url.path == "/ai/analyze-item-photo")
        #expect(sent[0].timeout == 90)
        let body = json(sent[0].body)
        #expect(body["imageJpegBase64"] as? String == jpeg.base64EncodedString())
        let context = body["context"] as? [String: Any]
        #expect(context?["quantity"] as? Int == 4)
        #expect(context?["ownerNotes"] as? String == "Stamp under seat")
        let parts = context?["savedDescription"] as? [[String: Any]]
        #expect(parts?.first?["origin"] as? String == "priorAI")
        let supp = body["supplementary"] as? [[String: Any]] ?? []
        #expect(supp.map { $0["kind"] as? String } == ["photo", "documentPage", "documentPage"])
        #expect(supp.map { $0["page"] as? Int } == [nil, 1, 2])
        #expect(supp.allSatisfy { $0["mimeType"] as? String == "image/jpeg" && $0["dataBase64"] is String })
        // Legacy hints still travel for older gateways.
        #expect((body["hints"] as? [String: Any])?["userWrittenTitle"] as? String == "Stools")
    }

    @Test func evidenceRequestIsNeverResentAutomatically() async {
        let p = provider(consentVersion: 2)
        StubURLProtocol.handler = { _, _ in (502, Data()) }
        await #expect(throws: AIError.self) { try await p.analyzeItem(self.evidenceRequest()) }
        #expect(StubURLProtocol.recorded.count == 1)

        StubURLProtocol.reset()
        StubURLProtocol.handler = { _, _ in throw URLError(.timedOut) }
        do { _ = try await p.analyzeItem(evidenceRequest()); Issue.record("expected timeout") } catch let e as AIError {
            if case .timeout = e {} else { Issue.record("expected timeout, got \(e)") }
        } catch { Issue.record("\(error)") }
        #expect(StubURLProtocol.recorded.count == 1)
    }

    @Test func standardRequestKeepsExistingRetryAndTimeout() async {
        let p = provider(consentVersion: 2)
        StubURLProtocol.handler = { _, _ in (502, Data()) }
        let request = ItemAnalysisRequest(hints: ItemAIHints(), context: ctx, primaryJPEG: jpeg, supplementary: [])
        await #expect(throws: AIError.self) { try await p.analyzeItem(request) }
        #expect(StubURLProtocol.recorded.count == 2)
        #expect(StubURLProtocol.recorded[0].timeout == 35)
    }

    @Test func gatewayEvidenceErrorsAreMapped() async {
        let p = provider(consentVersion: 2)
        StubURLProtocol.handler = { _, _ in
            (400, Data(#"{"error":{"code":"EVIDENCE_TOO_MANY_PHOTOS","message":"x","requestId":"r","status":400}}"#.utf8))
        }
        do { _ = try await p.analyzeItem(evidenceRequest()); Issue.record("expected rejection") } catch let e as AIError {
            if case .evidenceRejected(let code, _) = e { #expect(code == "EVIDENCE_TOO_MANY_PHOTOS") } else { Issue.record("got \(e)") }
            #expect(e.localizedDescription.contains("Too many additional photos"))
        } catch { Issue.record("\(error)") }
        #expect(StubURLProtocol.recorded.count == 1)
    }

    @Test func missingOrMismatchedReceiptDiscardsResult() async {
        let p = provider(consentVersion: 2)
        StubURLProtocol.handler = { _, _ in (200, analysisResponseJSON()) }          // older gateway: no summary
        await expectNotProcessed { try await p.analyzeItem(self.evidenceRequest()) }

        StubURLProtocol.reset()
        StubURLProtocol.handler = { _, _ in (200, analysisResponseJSON(summary: summaryJSON(primary: true, photos: 1, pages: 1))) }
        await expectNotProcessed { try await p.analyzeItem(self.evidenceRequest()) }
    }

    private func expectNotProcessed(_ body: () async throws -> ItemAnalysis) async {
        do {
            _ = try await body()
            Issue.record("expected evidenceNotProcessed")
        } catch let error as AIError {
            if case .evidenceNotProcessed = error {} else { Issue.record("got \(error)") }
        } catch {
            Issue.record("\(error)")
        }
    }

    @Test func textOnlyRequestUsesTextEndpointAndToleratesOlderGateway() async throws {
        let p = provider(consentVersion: 1)                    // no expanded disclosure needed
        StubURLProtocol.handler = { _, _ in (200, analysisResponseJSON()) }
        let request = ItemAnalysisRequest(hints: ItemAIHints(userWrittenTitle: "Lamp"), context: ctx,
                                          primaryJPEG: nil, supplementary: [])
        _ = try await p.analyzeItem(request)
        #expect(StubURLProtocol.recorded.first?.url.path == "/ai/analyze-item-text")
        let body = json(StubURLProtocol.recorded[0].body)
        #expect(body["context"] != nil)
        #expect(body["supplementary"] == nil)
    }

    @Test func legacyPhotoRequestIsUnchanged() async throws {
        let p = provider(consentVersion: 1)
        StubURLProtocol.handler = { _, _ in (200, analysisResponseJSON()) }
        _ = try await p.analyzeItemPhoto(imageData: jpeg, hints: ItemAIHints(userWrittenTitle: "Vase"))
        let sent = StubURLProtocol.recorded
        #expect(sent.count == 1)
        #expect(sent[0].timeout == 35)
        #expect(Set(json(sent[0].body).keys) == ["imageJpegBase64", "hints"])
    }

    @Test func cancellingStopsWithoutRetrying() async {
        let p = provider(consentVersion: 2)
        StubURLProtocol.delay = 3
        StubURLProtocol.handler = { _, _ in (200, analysisResponseJSON(summary: summaryJSON(primary: true, photos: 1, pages: 2))) }
        let request = evidenceRequest()
        let task = Task { try await p.analyzeItem(request) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let result = await task.result
        if case .failure(let error) = result, let ai = error as? AIError, case .cancelled = ai {
            // expected
        } else {
            Issue.record("expected AIError.cancelled, got \(result)")
        }
        #expect(StubURLProtocol.recorded.count == 1)
    }
}
