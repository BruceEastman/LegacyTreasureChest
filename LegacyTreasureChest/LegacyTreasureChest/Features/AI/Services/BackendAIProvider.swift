//
//  BackendAIProvider.swift
//  LegacyTreasureChest
//
//  Concrete AIProvider implementation that talks to the Legacy Treasure Chest
//  backend AI gateway instead of directly to Gemini.
//

import Foundation

struct BackendAIProvider: AIProvider {

    // MARK: - Configuration

    let baseURL: URL
    private let urlSession: URLSession

    /// Cloud Run base URL (Release/TestFlight default)
    private static var cloudBaseURL: URL {
        URL(string: "https://ltc-ai-gateway-530541590215.us-west1.run.app")!
    }

    /// Local dev base URL (Debug default)
    private static var localDevBaseURL: URL {
        #if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8000")!
        #else
        // Your Mac on the LAN when running FastAPI locally
        return URL(string: "http://192.168.4.27:8000")!
        #endif
    }

    /// Default selection:
    /// - Debug: local dev server (simulator/device)
    /// - Release: Cloud Run
    private static var defaultBaseURL: URL {
        #if DEBUG
        return localDevBaseURL
        #else
        return cloudBaseURL
        #endif
    }

    init(
        baseURL: URL = BackendAIProvider.defaultBaseURL,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    // MARK: - AIProvider

    func analyzeItemPhoto(
        imageData: Data,
        hints: ItemAIHints?
    ) async throws -> ItemAnalysis {
        let base64 = imageData.base64EncodedString()

        let requestBody = AnalyzeItemPhotoRequest(
            imageJpegBase64: base64,
            hints: hints
        )

        let response: ItemAnalysis = try await postJSON(
            path: "/ai/analyze-item-photo",
            body: requestBody
        )

        return response
    }

    func analyzeItemText(
        hints: ItemAIHints
    ) async throws -> ItemAnalysis {
        let requestBody = AnalyzeItemTextRequest(hints: hints)

        let response: ItemAnalysis = try await postJSON(
            path: "/ai/analyze-item-text",
            body: requestBody
        )

        return response
    }

    // MARK: - Liquidation

    func generateLiquidationBrief(
        request: LiquidationBriefRequest
    ) async throws -> LiquidationBriefDTO {
        let response: LiquidationBriefDTO = try await postJSON(
            path: "/ai/generate-liquidation-brief",
            body: request
        )
        return response
    }

    func generateLiquidationPlan(
        request: LiquidationPlanRequest
    ) async throws -> LiquidationPlanChecklistDTO {
        let response: LiquidationPlanChecklistDTO = try await postJSON(
            path: "/ai/generate-liquidation-plan",
            body: request
        )
        return response
    }

    // MARK: - Disposition Engine v1

    func dispositionPartnersSearch(
        request: DispositionPartnersSearchRequest
    ) async throws -> DispositionPartnersSearchResponse {
        let response: DispositionPartnersSearchResponse = try await postJSON(
            path: "/ai/disposition/partners/search",
            body: request
        )
        return response
    }

    func estimateValue(
        for item: ItemValueInput
    ) async throws -> ValueRange {
        throw AIError.notImplementedYet("Value estimation via backend is not yet implemented.")
    }

    func draftPersonalMessage(
        from input: MessageDraftInput
    ) async throws -> DraftMessageResult {
        throw AIError.notImplementedYet("Message drafting via backend is not yet implemented.")
    }

    func suggestBeneficiaries(
        from input: BeneficiarySuggestionInput
    ) async throws -> [BeneficiarySuggestion] {
        throw AIError.notImplementedYet("Beneficiary suggestions via backend is not yet implemented.")
    }

    // MARK: - Internal Networking Helpers

    private func postJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody
    ) async throws -> ResponseBody {

        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = baseURL.appendingPathComponent(trimmedPath)

        let requestID = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 35  // predictable, conservative
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Headers discipline
        request.setValue(LTCDeviceIdentity.deviceID(), forHTTPHeaderField: "X-LTC-Device-ID")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        // Conservative retry policy: at most 1 retry on transient failures.
        let maxAttempts = 2
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await urlSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIError.unexpectedResponse(requestID: requestID)
                }

                let responseRequestID =
                    httpResponse.value(forHTTPHeaderField: "X-Request-ID") ??
                    httpResponse.value(forHTTPHeaderField: "x-request-id") ??
                    requestID

                if (200..<300).contains(httpResponse.statusCode) {
                    guard !data.isEmpty else {
                        throw AIError.unexpectedResponse(requestID: responseRequestID)
                    }

                    let decoder = makeLenientISO8601Decoder()
                    do {
                        return try decoder.decode(ResponseBody.self, from: data)
                    } catch {
                        // No raw body leakage to user
                        #if DEBUG
                        let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                        print("⚠️ Backend decode failed [\(responseRequestID)] \(url.absoluteString)\n\(bodyPreview)")
                        #endif
                        throw AIError.unexpectedResponse(requestID: responseRequestID)
                    }
                }

                // Non-2xx handling (normalized)
                let status = httpResponse.statusCode

                // Try to detect a structured server error (best-effort, not required)
                let envelope = decodeErrorEnvelope(from: data)

                // Kill switch / temporarily disabled (server-side)
                if status == 503 {
                    throw AIError.temporarilyUnavailable(requestID: responseRequestID)
                }

                if status == 429 {
                    throw AIError.rateLimited(requestID: responseRequestID)
                }

                // Transient backend errors: allow retry on 502/503 only
                if (status == 502 || status == 503),
                   attempt < maxAttempts {
                    try await backoffSleep(forAttempt: attempt)
                    continue
                }

                // Other cases: map to “service unavailable” (calm, non-technical)
                #if DEBUG
                if let env = envelope {
                    print("⚠️ Backend error [\(responseRequestID)] HTTP \(status): \(env.debugSummary)")
                } else {
                    let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                    print("⚠️ Backend error [\(responseRequestID)] HTTP \(status)\n\(bodyPreview)")
                }
                #endif

                throw AIError.serviceUnavailable(requestID: responseRequestID)

            } catch {
                lastError = error

                // If already normalized, do not wrap
                if let ai = error as? AIError { throw ai }

                // Transport error normalization
                if let urlError = error as? URLError {
                    // Offline: never retry
                    if urlError.code == .notConnectedToInternet {
                        throw AIError.offline(requestID: requestID)
                    }

                    // Timeout: one retry max
                    if urlError.code == .timedOut {
                        if attempt < maxAttempts {
                            try await backoffSleep(forAttempt: attempt)
                            continue
                        }
                        throw AIError.timeout(requestID: requestID)
                    }

                    // Other transient network conditions: one retry max
                    if isRetryableTransportError(urlError),
                       attempt < maxAttempts {
                        try await backoffSleep(forAttempt: attempt)
                        continue
                    }

                    // Default: treat as unavailable (calm)
                    throw AIError.serviceUnavailable(requestID: requestID)
                }

                // Any other unexpected failure: calm response
                throw AIError.serviceUnavailable(requestID: requestID)
            }
        }

        // Should not normally reach here
        #if DEBUG
        if let lastError {
            print("⚠️ Backend request failed after retries [\(requestID)]: \(lastError)")
        }
        #endif
        throw AIError.serviceUnavailable(requestID: requestID)
    }

    private func isRetryableTransportError(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed,
             .secureConnectionFailed,
             .cannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }

    private func backoffSleep(forAttempt attempt: Int) async throws {
        // Simple, predictable backoff: ~0.6s then ~1.2s (we only do 2 attempts anyway)
        let base: UInt64 = (attempt == 1) ? 600_000_000 : 1_200_000_000
        try await Task.sleep(nanoseconds: base)
    }

    private func decodeErrorEnvelope(from data: Data) -> BackendErrorEnvelope? {
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(BackendErrorEnvelope.self, from: data)
        } catch {
            return nil
        }
    }

    private func makeLenientISO8601Decoder() -> JSONDecoder {
        let decoder = JSONDecoder()

        decoder.dateDecodingStrategy = .custom { dec -> Date in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)

            let fmtFrac = ISO8601DateFormatter()
            fmtFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = fmtFrac.date(from: str) { return d }

            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime]
            if let d = fmt.date(from: str) { return d }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(str)"
            )
        }

        return decoder
    }
}

// MARK: - Backend DTOs

private struct AnalyzeItemPhotoRequest: Encodable {
    let imageJpegBase64: String
    let hints: ItemAIHints?
}

private struct AnalyzeItemTextRequest: Encodable {
    let hints: ItemAIHints
}

// MARK: - Error Envelope (best-effort)

private struct BackendErrorEnvelope: Decodable {
    // Common patterns: FastAPI often uses "detail"
    let detail: String?
    let message: String?
    let error: String?
    let requestId: String?
    let request_id: String?

    var debugSummary: String {
        let parts = [error, message, detail].compactMap { $0 }.joined(separator: " | ")
        return parts.isEmpty ? "<no message>" : parts
    }
}
