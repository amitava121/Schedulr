import Foundation

/// Routes natural-language parsing through a cloud proxy first, then falls back
/// to the local parser when network/proxy parsing is unavailable or too slow.
actor NLPScheduleRouter {
    static let shared = NLPScheduleRouter()

    enum ParseSource {
        case cloud
        case localFallback
    }

    struct ParseResult {
        let parsed: NLPScheduleParser.ParsedSchedule
        let source: ParseSource
        let internetUnavailable: Bool
    }

    private enum RouterError: Error {
        case missingProxyURL
        case invalidResponse
        case badStatus(Int)
        case decodingFailed
        case timeout
    }

    private struct CloudRequestBody: Encodable {
        let text: String
        let locale: String
        let timeZone: String
    }

    private struct GeminiRequestBody: Encodable {
        struct Content: Encodable {
            struct Part: Encodable {
                let text: String
            }

            let parts: [Part]
        }

        struct GenerationConfig: Encodable {
            struct ThinkingConfig: Encodable {
                let thinkingBudget: Int
            }

            let temperature: Double
            let maxOutputTokens: Int
            let thinkingConfig: ThinkingConfig?
        }

        let contents: [Content]
        let generationConfig: GenerationConfig
    }

    /// This mirrors the local ParsedSchedule schema so the saving pipeline
    /// does not care which parser produced it.
    private struct CloudResponseBody: Decodable {
        let title: String?
        let dateISO8601: String?
        let hasTime: Bool?
        let priority: String?
        let tags: [String]?
        let repeatPattern: String?
        let deliveryOption: String?
        let earlyReminderMinutes: Int?

        enum CodingKeys: String, CodingKey {
            case title
            case dateISO8601
            case hasTime
            case priority
            case tags
            case repeatPattern
            case deliveryOption
            case earlyReminderMinutes
        }
    }

    private struct GeminiResponseBody: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]?
            }

            let content: Content?
        }

        let candidates: [Candidate]?
    }

    private let requestTimeoutSeconds: TimeInterval = 1.5
    private let geminiModelName = "gemini-flash-latest"

    func parse(_ input: String) async -> ParseResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let emptyParsed = await MainActor.run { NLPScheduleParser.ParsedSchedule() }
            return ParseResult(
                parsed: emptyParsed,
                source: .localFallback,
                internetUnavailable: false
            )
        }

        do {
            let parsed = try await parseViaCloud(trimmed)
            return ParseResult(parsed: parsed, source: .cloud, internetUnavailable: false)
        } catch {
            let fallbackParsed = await MainActor.run { NLPScheduleParser.parse(trimmed) }
            return ParseResult(
                parsed: fallbackParsed,
                source: .localFallback,
                internetUnavailable: isInternetUnavailable(error)
            )
        }
    }

    private func parseViaCloud(_ input: String) async throws -> NLPScheduleParser.ParsedSchedule {
        if let endpointURL = resolveProxyURL() {
            return try await parseViaProxy(input, endpointURL: endpointURL)
        }

        if let geminiAPIKey = resolveGeminiAPIKey() {
            return try await parseViaGemini(input, apiKey: geminiAPIKey)
        }

        throw RouterError.missingProxyURL
    }

    private func parseViaProxy(_ input: String, endpointURL: URL) async throws -> NLPScheduleParser.ParsedSchedule {

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = CloudRequestBody(
            text: input,
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeoutSeconds
        configuration.timeoutIntervalForResource = requestTimeoutSeconds + 0.5
        let session = URLSession(configuration: configuration)

        let data = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                let (responseData, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw RouterError.invalidResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw RouterError.badStatus(httpResponse.statusCode)
                }
                return responseData
            }

            group.addTask {
                try await Task.sleep(for: .seconds(self.requestTimeoutSeconds))
                throw RouterError.timeout
            }

            guard let firstResult = try await group.next() else {
                throw RouterError.invalidResponse
            }
            group.cancelAll()
            return firstResult
        }

        let decoded = try decodeCloudResponse(data)
        return await mapCloudResponse(decoded)
    }

    private func parseViaGemini(_ input: String, apiKey: String) async throws -> NLPScheduleParser.ParsedSchedule {
        guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModelName):generateContent?key=\(apiKey)") else {
            throw RouterError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Extract scheduling details from user text and return ONLY valid JSON object with keys:
        title (string), dateISO8601 (string|null), hasTime (boolean), priority (none|low|medium|high), tags (string[]), repeatPattern (never|daily|weekly|biweekly|monthly|yearly|weekdays), deliveryOption (push|alarm|null), earlyReminderMinutes (number|null).
        Locale: \(Locale.current.identifier)
        TimeZone: \(TimeZone.current.identifier)
        Input: \(input)
        """

        let payload = GeminiRequestBody(
            contents: [
                .init(parts: [.init(text: prompt)])
            ],
            generationConfig: .init(
                temperature: 0,
                maxOutputTokens: 900,
                thinkingConfig: .init(thinkingBudget: 0)
            )
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeoutSeconds
        configuration.timeoutIntervalForResource = requestTimeoutSeconds + 0.5
        let session = URLSession(configuration: configuration)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RouterError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RouterError.badStatus(httpResponse.statusCode)
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponseBody.self, from: data)
        guard let content = geminiResponse.candidates?.first?.content?.parts?.first?.text,
              let jsonData = extractJSONObjectData(from: content)
        else {
            throw RouterError.decodingFailed
        }

        let decoded = try decodeCloudResponse(jsonData)
        return await mapCloudResponse(decoded)
    }

    private func resolveProxyURL() -> URL? {
        let defaults = UserDefaults.standard
        if let configured = defaults.string(forKey: "settings.nlpProxyEndpoint")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty,
           let url = URL(string: configured)
        {
            return url
        }

        if let plistValue = Bundle.main.object(forInfoDictionaryKey: "NLPProxyURL") as? String,
           let url = URL(string: plistValue),
           !plistValue.isEmpty
        {
            return url
        }

        return nil
    }

    private func resolveGeminiAPIKey() -> String? {
        let defaults = UserDefaults.standard
        if let configured = defaults.string(forKey: "settings.nlpGeminiAPIKey")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty
        {
            return configured
        }

        if let plistValue = Bundle.main.object(forInfoDictionaryKey: "NLPGeminiAPIKey") as? String,
           !plistValue.isEmpty
        {
            return plistValue
        }

        if let envValue = ProcessInfo.processInfo.environment["NLP_GEMINI_API_KEY"],
           !envValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return envValue
        }

        return nil
    }

    private func decodeCloudResponse(_ data: Data) throws -> CloudResponseBody {
        do {
            return try JSONDecoder().decode(CloudResponseBody.self, from: data)
        } catch {
            throw RouterError.decodingFailed
        }
    }

    private func mapCloudResponse(_ response: CloudResponseBody) async -> NLPScheduleParser.ParsedSchedule {
        var parsed = await MainActor.run { NLPScheduleParser.ParsedSchedule() }
        parsed.title = response.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let dateText = response.dateISO8601,
           let parsedDate = parseISO8601(dateText)
        {
            parsed.date = parsedDate
        }

        parsed.hasTime = response.hasTime ?? false
        parsed.priority = parsePriority(response.priority)
        parsed.tags = response.tags ?? []
        parsed.repeatPattern = parseRepeatPattern(response.repeatPattern)
        parsed.deliveryOption = parseDeliveryOption(response.deliveryOption)
        parsed.earlyReminderMinutes = response.earlyReminderMinutes

        return parsed
    }

    private func parseISO8601(_ value: String) -> Date? {
        let primary = ISO8601DateFormatter()
        primary.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = primary.date(from: value) {
            return date
        }

        let secondary = ISO8601DateFormatter()
        secondary.formatOptions = [.withInternetDateTime]
        return secondary.date(from: value)
    }

    private func parsePriority(_ raw: String?) -> SchedulePriority {
        switch raw?.lowercased() {
        case "high": return .high
        case "medium": return .medium
        case "low": return .low
        default: return .none
        }
    }

    private func parseRepeatPattern(_ raw: String?) -> RepeatPattern {
        switch raw?.lowercased() {
        case "daily": return .daily
        case "weekly": return .weekly
        case "biweekly": return .biweekly
        case "monthly": return .monthly
        case "yearly": return .yearly
        case "weekdays": return .weekdays
        default: return .never
        }
    }

    private func parseDeliveryOption(_ raw: String?) -> AlertDeliveryOption? {
        guard let raw = raw?.lowercased() else { return nil }
        return AlertDeliveryOption(rawValue: raw)
    }

    private func extractJSONObjectData(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil
        {
            return data
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}")
        else {
            return nil
        }
        let candidate = String(trimmed[start...end])
        guard let data = candidate.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else {
            return nil
        }
        return data
    }

    private func isInternetUnavailable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .internationalRoamingOff,
             .dataNotAllowed,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
