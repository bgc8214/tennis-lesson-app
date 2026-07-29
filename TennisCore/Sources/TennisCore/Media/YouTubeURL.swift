import Foundation

/// YouTube URL 형태(watch?v=, youtu.be/, shorts/, embed/)에서 video ID만 뽑아내는 순수 로직.
/// 실제 스트림 해석은 플랫폼별로 다르다 — macOS는 yt-dlp 프로세스, iOS는
/// TennisLesson/Platform/YouTubeWebResolver(WKWebView 기반)를 쓴다(TennisCore는
/// UI 프레임워크 의존을 두지 않는다는 원칙 때문에 여기 두지 않음).
public enum YouTubeURL {
    public static func videoID(from urlString: String) -> String? {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 스킴 없이 붙여넣은 경우(youtu.be/xxx, www.youtube.com/... 등) 보정.
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }

        if let components = URLComponents(string: trimmed) {
            let host = components.host?.lowercased() ?? ""
            // youtu.be 단축 링크: 첫 경로 세그먼트가 video ID.
            if host.contains("youtu.be") {
                if let first = components.path.split(separator: "/").first {
                    return sanitize(String(first))
                }
            }
            // youtube.com / m.youtube.com / music.youtube.com …
            if host.contains("youtube.com") {
                if let v = components.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                    return sanitize(v)
                }
                let segments = components.path.split(separator: "/").map(String.init)
                // /shorts/<id>, /embed/<id>, /live/<id>, /v/<id>
                if let idx = segments.firstIndex(where: { ["shorts", "embed", "live", "v"].contains($0) }),
                   segments.count > idx + 1 {
                    return sanitize(segments[idx + 1])
                }
            }
        }

        // 최후 폴백: 문자열 어디서든 11자리 YouTube video ID 패턴을 찾는다.
        if let id = firstVideoIDMatch(in: trimmed) { return id }
        return nil
    }

    /// video ID는 `[A-Za-z0-9_-]` 11자. 뒤에 붙은 파라미터/조각을 잘라낸다.
    private static func sanitize(_ raw: String) -> String? {
        let cut = raw.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let id = String(cut)
        return id.count == 11 ? id : (id.isEmpty ? nil : id)
    }

    private static func firstVideoIDMatch(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{11}(?![A-Za-z0-9_-])") else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        return String(text[r])
    }
}
