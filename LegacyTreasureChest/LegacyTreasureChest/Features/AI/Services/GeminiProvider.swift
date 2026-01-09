//
//  GeminiProvider.swift
//  LegacyTreasureChest
//
//  Concrete AIProvider implementation backed by the Gemini HTTP API.
//  Uses Info.plist keys for configuration:
//
//  - GEMINI_API_KEY    (required)
//  - GEMINI_MODEL_NAME (optional, default: "gemini-1.5-flash")
//

import Foundation

struct GeminiProvider: AIProvider {

    // MARK: - Configuration

    /// API key loaded from Info.plist (GEMINI_API_KEY).
    private let apiKey: String?

    /// Model name loaded from Info.plist (GEMINI_MODEL_NAME) or a sensible default.
    private let modelName: String

    /// Base URL for the Gemini generateContent endpoint.
    private var endpointURL: URL? {
        guard let apiKey, !apiKey.isEmpty else { return nil }

        let urlString =
            "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"

        return URL(string: urlString)
    }

    init(
        apiKey: String? = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
        modelName: String? = Bundle.main.object(forInfoDictionaryKey: "GEMINI_MODEL_NAME") as? String
    ) {
        self.apiKey = apiKey
        self.modelName = modelName?.isEmpty == false
            ? modelName!
            : "gemini-1.5-flash"
    }

    // MARK: - AIProvider

    func analyzeItemPhoto(
        imageData: Data,
        hints: ItemAIHints?
    ) async throws -> ItemAnalysis {
        guard let url = endpointURL else {
            throw AIError.providerNotConfigured
        }

        let base64Image = imageData.base64EncodedString()
        let prompt = buildItemAnalysisPrompt(hints: hints)

        let requestBody = GeminiGenerateContentRequest(
            contents: [
                .init(parts: [
                    .init(text: prompt),
                    .init(
                        inlineData: .init(
                            mimeType: "image/jpeg",
                            data: base64Image
                        )
                    )
                ])
            ],
            generationConfig: .init(
                temperature: 0.2,
                responseMimeType: "application/json"
            )
        )

        return try await performRequest(url: url, requestBody: requestBody)
    }

    /// ✅ New required method: Text-only item analysis (no image).
    func analyzeItemText(
        hints: ItemAIHints
    ) async throws -> ItemAnalysis {
        guard let url = endpointURL else {
            throw AIError.providerNotConfigured
        }

        let prompt = buildItemTextOnlyAnalysisPrompt(hints: hints)

        let requestBody = GeminiGenerateContentRequest(
            contents: [
                .init(parts: [
                    .init(text: prompt)
                ])
            ],
            generationConfig: .init(
                temperature: 0.2,
                responseMimeType: "application/json"
            )
        )

        return try await performRequest(url: url, requestBody: requestBody)
    }

    func estimateValue(
        for item: ItemValueInput
    ) async throws -> ValueRange {
        throw AIError.notImplementedYet("Value estimation is not yet implemented.")
    }

    func draftPersonalMessage(
        from input: MessageDraftInput
    ) async throws -> DraftMessageResult {
        throw AIError.notImplementedYet("Message drafting is not yet implemented.")
    }

    func suggestBeneficiaries(
        from input: BeneficiarySuggestionInput
    ) async throws -> [BeneficiarySuggestion] {
        throw AIError.notImplementedYet("Beneficiary suggestions are not yet implemented.")
    }

    // MARK: - Shared request/response handling

    private func performRequest(
        url: URL,
        requestBody: GeminiGenerateContentRequest
    ) async throws -> ItemAnalysis {
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
            throw AIError.invalidResponse("HTTP \(status). Body: \(bodyPreview)")
        }

        // Decode Gemini response → extract text → decode ItemAnalysis JSON.
        let decoder = JSONDecoder()
        let geminiResponse = try decoder.decode(GeminiGenerateContentResponse.self, from: data)

        guard
            let candidate = geminiResponse.candidates.first,
            let rawText = candidate.content.parts.first(where: { $0.text != nil })?.text
        else {
            throw AIError.invalidResponse("Gemini response contained no text candidate.")
        }

        // Strip possible ```json fences and whitespace.
        let cleanedText = cleanJSONText(rawText)

        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw AIError.decodingFailed("Unable to convert Gemini text to UTF-8 data.")
        }

        let aiDecoder = JSONDecoder()

        do {
            return try aiDecoder.decode(ItemAnalysis.self, from: jsonData)
        } catch {
            print("❌ Gemini ItemAnalysis decode error: \(error)")
            print("Raw Gemini JSON text:\n\(cleanedText)")
            throw AIError.decodingFailed("Failed to decode ItemAnalysis JSON: \(error.localizedDescription)")
        }
    }

    // MARK: - Prompt Construction

    /// Builds the system + user prompt for item analysis from a photo.
    private func buildItemAnalysisPrompt(hints: ItemAIHints?) -> String {
        var lines: [String] = []

        lines.append("""
        You are helping a family catalog household items for a legacy and estate planning app.
        Analyze the attached photo of a single item. The item may be a rug, piece of furniture,
        luggage, leather goods, sewing machine, appliance, or other household object.

        Your goal is to produce a concise but information-rich JSON description that could be
        used by a human to quickly understand what this item is, what it is made of, its style,
        and roughly how valuable it might be.
        """)

        lines.append(baseJSONSchemaInstructions())

        if let hints {
            lines.append(userHintsBlock(hints))
        }

        lines.append(commonGuidelines())

        return lines.joined(separator: "\n\n")
    }

    /// Builds the system + user prompt for item analysis from TEXT ONLY (no photo).
    private func buildItemTextOnlyAnalysisPrompt(hints: ItemAIHints) -> String {
        var lines: [String] = []

        lines.append("""
        You are helping a family catalog household items for a legacy and estate planning app.
        You will NOT receive a photo.

        Use ONLY the provided text (title/description/category and any extra owner details) to:
        - Suggest a clearer marketplace-style title
        - Suggest a better category
        - Provide a concise summary
        - Provide a reasonable resale value estimate range IF possible
        - List missing details that would improve confidence (especially photos)
        """)

        lines.append(baseJSONSchemaInstructions())
        lines.append(userHintsBlock(hints))

        lines.append("""
        Additional constraints for text-only mode:
        - If you cannot estimate value from text alone, set valueHints to null.
        - Confidence should generally be LOWER without a photo unless the text is very specific.
        - In missingDetails, include photo-related requests (e.g., “Add a clear photo of labels/stamps/overall condition”).
        """)

        lines.append(commonGuidelines())

        return lines.joined(separator: "\n\n")
    }

    private func baseJSONSchemaInstructions() -> String {
        """
        Respond ONLY with valid JSON and NO extra commentary or explanation.

        The JSON must match this structure exactly (all fields other than title/summary/category may be null):

        {
          "title": String,
          "summary": String,
          "category": String,
          "tags": [String] | null,
          "confidence": Double | null,
          "valueHints": {
            "low": Double,
            "high": Double,
            "currencyCode": String,
            "confidence": Double | null,
            "sources": [String],
            "lastUpdated": String | null
          } | null,
          "extractedText": String | null,
          "brand": String | null,
          "modelNumber": String | null,
          "maker": String | null,
          "materials": [String] | null,
          "style": String | null,
          "origin": String | null,
          "condition": String | null,
          "dimensions": String | null,
          "eraOrYear": String | null,
          "features": [String] | null
        }
        """
    }

    private func userHintsBlock(_ hints: ItemAIHints) -> String {
        var hintLines: [String] = []

        if let title = hints.userWrittenTitle, !title.isEmpty {
            hintLines.append("User-provided working title: \"\(title)\".")
        }
        if let description = hints.userWrittenDescription, !description.isEmpty {
            hintLines.append("User description:\n\(description)")
        }
        if let category = hints.knownCategory, !category.isEmpty {
            hintLines.append("Known category: \(category)")
        }

        if hintLines.isEmpty {
            return "No user text was provided."
        }

        return """
        Additional context from the user:
        \(hintLines.joined(separator: "\n"))
        """
    }

    private func commonGuidelines() -> String {
        """
        Guidelines:

        - "title": short marketplace-style name (brand + item + key detail).
        - "summary": 1–3 sentences with key details a family member would care about.
        - "category": choose a reasonable household category (e.g., "Furniture", "Decor", "Rug", "Electronics", etc.).
        - "tags": short keywords about style, use, brand, or pattern.

        - For "valueHints":
          - If you estimate value, use USD for "currencyCode" and return a reasonable low/high resale range
            based on typical used item markets (not new retail).
          - Use an ISO-8601-like string for "lastUpdated" (e.g., "2025-01-22T00:00:00Z").
        """
    }

    /// Strip common Markdown fences and trim whitespace.
    private func cleanJSONText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Gemini REST DTOs

/// Request payload for the Gemini generateContent API.
private struct GeminiGenerateContentRequest: Codable {
    struct Content: Codable {
        var parts: [Part]
    }

    struct Part: Codable {
        var text: String?
        var inlineData: InlineData?

        init(text: String) {
            self.text = text
            self.inlineData = nil
        }

        init(inlineData: InlineData) {
            self.text = nil
            self.inlineData = inlineData
        }
    }

    struct InlineData: Codable {
        var mimeType: String
        var data: String
    }

    struct GenerationConfig: Codable {
        var temperature: Double?
        var responseMimeType: String?
    }

    var contents: [Content]
    var generationConfig: GenerationConfig?
}

/// Subset of the Gemini generateContent response we care about.
private struct GeminiGenerateContentResponse: Codable {
    struct Candidate: Codable {
        struct Content: Codable {
            struct Part: Codable {
                var text: String?
            }

            var parts: [Part]
        }

        var content: Content
    }

    var candidates: [Candidate]
}
