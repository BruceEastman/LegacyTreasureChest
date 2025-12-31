//
//  BackendAIProvider.swift
//  LegacyTreasureChest
//
//  Concrete AIProvider implementation that talks to the Legacy Treasure Chest
//  backend AI gateway instead of directly to Gemini.
//  The backend holds the Gemini API key in an environment variable and exposes
//  safe HTTP endpoints like /ai/analyze-item-photo.
//

import Foundation

struct BackendAIProvider: AIProvider {

    // MARK: - Configuration

    private let baseURL: URL
    private let urlSession: URLSession

    /// Default backend base URL:
    /// - Simulator: 127.0.0.1 points to your Mac host
    /// - Physical iPhone: must use your Mac's LAN IP
    private static var defaultBaseURL: URL {
        #if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8000")!
        #else
        return URL(string: "http://192.168.4.27:8000")!
        #endif
    }

    init(
        // For now, we hard-code a dev URL so we are not dependent on AppConfig.
        // This should match your local FastAPI server:
        //   uvicorn main:app --reload --host 0.0.0.0 --port 8000
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

    func estimateValue(
        for item: ItemValueInput
    ) async throws -> ValueRange {
        // TODO: Wire to backend endpoint when implemented.
        throw AIError.notImplementedYet("Value estimation via backend is not yet implemented.")
    }

    func draftPersonalMessage(
        from input: MessageDraftInput
    ) async throws -> DraftMessageResult {
        // TODO: Wire to backend endpoint when implemented.
        throw AIError.notImplementedYet("Message drafting via backend is not yet implemented.")
    }

    func suggestBeneficiaries(
        from input: BeneficiarySuggestionInput
    ) async throws -> [BeneficiarySuggestion] {
        // TODO: Wire to backend endpoint when implemented.
        throw AIError.notImplementedYet("Beneficiary suggestions via backend are not yet implemented.")
    }

    // MARK: - Internal Networking Helpers

    /// Generic JSON POST helper.
    private func postJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody
    ) async throws -> ResponseBody {

        // Normalize path to avoid accidental double slashes.
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = baseURL.appendingPathComponent(trimmedPath)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse("No HTTPURLResponse received from backend.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
            throw AIError.invalidResponse(
                "Backend error HTTP \(httpResponse.statusCode). Body: \(bodyPreview)"
            )
        }

        // Helpful for the “missing data” decoder case
        if data.isEmpty {
            throw AIError.invalidResponse(
                "Backend returned HTTP \(httpResponse.statusCode) with EMPTY body for \(path)."
            )
        }

        let decoder = makeLenientISO8601Decoder()

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
            throw AIError.decodingFailed(
                "Failed to decode backend AI response into \(ResponseBody.self): \(error.localizedDescription). Body: \(bodyPreview)"
            )
        }
    }

    /// Decoder that accepts ISO8601 with or without fractional seconds and with Z / timezone offsets.
    private func makeLenientISO8601Decoder() -> JSONDecoder {
        let decoder = JSONDecoder()

        // Use a custom date decoding strategy:
        // - Tries ISO8601 with fractional seconds
        // - Falls back to ISO8601 without fractional seconds
        decoder.dateDecodingStrategy = .custom { dec -> Date in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)

            // 1) ISO8601 with fractional seconds
            let fmtFrac = ISO8601DateFormatter()
            fmtFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = fmtFrac.date(from: str) { return d }

            // 2) ISO8601 without fractional seconds
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

/// Request payload sent from the iOS app to the backend for photo analysis.
private struct AnalyzeItemPhotoRequest: Encodable {
    /// JPEG image data encoded as Base64.
    let imageJpegBase64: String

    /// Optional hints to help the model; directly reuses your ItemAIHints type.
    let hints: ItemAIHints?
}
