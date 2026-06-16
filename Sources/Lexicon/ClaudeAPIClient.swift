import Foundation

enum APIError: Error, CustomStringConvertible {
    case noKey
    case badStatus(Int, String)
    case noText
    case parse(String)

    var description: String {
        switch self {
        case .noKey: return "no API key configured"
        case .badStatus(let c, let body): return "HTTP \(c): \(body.prefix(200))"
        case .noText: return "response had no text block"
        case .parse(let m): return "parse error: \(m)"
        }
    }
}

/// Thin async client for the Anthropic Messages API. Instructs the model to
/// return ONLY JSON conforming to `AnalysisResult` and decodes it. No sampling
/// params or thinking config are sent — these models reject `temperature` and
/// `thinking.budget_tokens`, and the hot path wants minimal latency.
struct ClaudeAPIClient {

    func analyze(text: String, caret: Int, model: String) async throws -> AnalysisResult {
        guard let key = AppConfig.apiKey else { throw APIError.noKey }

        var request = URLRequest(url: URL(string: AppConfig.apiBaseURL)!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(AppConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let system = """
        You are a writing-intent analyzer for a real-time, system-wide writing \
        assistant. Given the user's in-progress text, infer their communicative \
        goal and propose higher-precision vocabulary or phrasing that better \
        expresses that goal.
        Respond with ONLY a JSON object — no prose, no markdown, no code fences — \
        matching exactly this shape:
        {"goalId":"kebab-slug","goalLabel":"Human readable goal","confidence":0.0,\
        "suggestions":[{"kind":"vocabulary|syntax|cadence",\
        "original":"span being improved or empty string if additive",\
        "replacement":"better word or phrase (empty for cadence-only commentary)",\
        "rationale":"one line: why it serves the goal"}]}
        Rules: suggestions ranked best-first, at most 6; confidence is between 0 and 1; \
        classify each item as vocabulary (word choice), syntax (grammar/structure), or \
        cadence (flow/rhythm observation — may have empty replacement and is not inserted); \
        vocabulary and syntax replacements must be directly insertable at the caret.
        """
        let userText = "The caret is at character offset \(caret).\n\nText:\n\(text)"

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 600,
            "system": system,
            "messages": [["role": "user", "content": userText]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatus(-1, "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw APIError.parse("unexpected response envelope")
        }
        let textOut = content.compactMap { $0["text"] as? String }.joined()
        guard !textOut.isEmpty else { throw APIError.noText }

        let json = Self.extractJSON(textOut)
        guard let jsonData = json.data(using: .utf8) else { throw APIError.parse("utf8") }
        do {
            return try JSONDecoder().decode(AnalysisResult.self, from: jsonData)
        } catch {
            throw APIError.parse("\(error) — raw: \(textOut.prefix(160))")
        }
    }

    /// Pulls a JSON object out of a model response, tolerating stray prose or
    /// ```json fences by slicing from the first `{` to the last `}`.
    static func extractJSON(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = trimmed.firstIndex(of: "{"),
           let close = trimmed.lastIndex(of: "}"),
           open <= close {
            return String(trimmed[open...close])
        }
        return trimmed
    }
}
