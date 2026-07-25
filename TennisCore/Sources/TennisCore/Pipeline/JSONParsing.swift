import Foundation

/// `gemini_service.py`의 `_strip_fence`/`_parse_json` 포팅. LLM 응답이 마크다운 펜스로
/// 감싸져 있거나 뒤에 잡담이 붙는 경우까지 서버와 동일하게 방어한다.
public enum JSONParsing {
    public static func stripFence(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }

        if let firstNewline = t.firstIndex(of: "\n") {
            t = String(t[t.index(after: firstNewline)...])
        } else {
            t = ""
        }
        if t.hasSuffix("```") {
            t = String(t.dropLast(3))
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 정상 파싱 실패 시 첫 완전한 `{...}` 블록을 문자열 이스케이프까지 고려해 추출한다.
    public static func parseObject(_ raw: String) throws -> [String: JSONValue] {
        let stripped = stripFence(raw)

        if let data = stripped.data(using: .utf8),
           let obj = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
            return obj
        }

        guard let startIdx = stripped.firstIndex(of: "{") else {
            throw JSONParsingError.failed(String(stripped.prefix(200)))
        }

        let chars = Array(stripped[startIdx...])
        var depth = 0
        var inString = false
        var escape = false

        for (i, ch) in chars.enumerated() {
            if escape { escape = false; continue }
            if ch == "\\" && inString { escape = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let candidate = String(chars[0...i])
                    if let data = candidate.data(using: .utf8),
                       let obj = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
                        return obj
                    }
                    break
                }
            }
        }

        throw JSONParsingError.failed(String(stripped.prefix(200)))
    }
}

public enum JSONParsingError: Error, CustomStringConvertible {
    case failed(String)

    public var description: String {
        switch self {
        case .failed(let snippet): return "JSON 파싱 실패: \(snippet)"
        }
    }
}
