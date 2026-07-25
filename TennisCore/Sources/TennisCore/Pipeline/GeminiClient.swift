import Foundation

/// Gemini REST API(`generateContent`) 직접 호출. `gemini_service.py`의
/// `client.models.generate_content(temperature=0, max_output_tokens=8192,
/// thinking_config=ThinkingConfig(thinking_budget=0))` 설정을 그대로 재현한다.
public struct GeminiClient: Sendable {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public enum GeminiError: Error, CustomStringConvertible {
        case httpError(Int, String)
        case emptyResponse

        public var description: String {
            switch self {
            case .httpError(let code, let body): return "Gemini API 오류 (\(code)): \(body.prefix(300))"
            case .emptyResponse: return "Gemini 응답이 비어 있습니다"
            }
        }
    }

    public func generateContent(prompt: String) async throws -> String {
        var url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        url.append(queryItems: [URLQueryItem(name: "key", value: apiKey)])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.0,
                "maxOutputTokens": 8192,
                "thinkingConfig": ["thinkingBudget": 0],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw GeminiError.emptyResponse
        }
        return text
    }
}
