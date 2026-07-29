import Foundation

/// 순수 Swift/URLSession으로 YouTube에서 재생 가능한(오디오+영상 병합, progressive)
/// 직접 다운로드 URL을 받는다. 서버·외부 프로세스·WebKit 불필요.
///
/// 2026-07-26 실기기+curl로 검증된 순서:
/// 1) watch 페이지를 데스크톱 UA로 GET → 페이지 안의 `visitorData`(방문자 세션 토큰) 추출.
///    이 단계 없이 바로 innertube를 두드리면 "Sign in to confirm you're not a bot"로 막힘
///    (TLS 지문 문제가 아니라 단순히 유효한 세션 토큰이 없어서였음 — 이전 결론 정정).
/// 2) 그 visitorData를 실어 **ANDROID_VR** 클라이언트로 innertube player API 호출.
///    `web`/`web_safari` 클라이언트는 2026년 현재 SABR(전용 스트리밍 프로토콜, 단순
///    GET으로 못 받음)만 주지만, android_vr은 여전히 서명 없는 progressive URL을 준다.
/// 3) 받은 URL 중 progressive itag(오디오+영상 병합)를 골라 그대로 다운로드.
///
/// 화질은 itag 18 기준 360p로 제한적이지만, 이 앱은 STT(오디오)와 타임스탬프 점프
/// 재생용이라 화질 자체는 중요하지 않다.
public enum YouTubeDirectClient {
    public struct ResolvedFormat: Sendable {
        public let title: String
        public let url: URL
        public let itag: Int
        public let mimeType: String
    }

    public enum ResolveError: Error, CustomStringConvertible {
        case invalidVideoID
        case visitorDataNotFound
        case requestFailed(String)
        case notPlayable(String)
        case noProgressiveFormat

        public var description: String {
            switch self {
            case .invalidVideoID: return "올바른 YouTube URL이 아닙니다"
            case .visitorDataNotFound: return "YouTube 방문자 세션을 가져오지 못했습니다(페이지 구조 변경 가능성)"
            case .requestFailed(let msg): return "YouTube 요청 실패: \(msg)"
            case .notPlayable(let reason): return "재생할 수 없는 영상입니다: \(reason)"
            case .noProgressiveFormat: return "재생 가능한(오디오+영상 병합) 스트림을 찾지 못했습니다"
            }
        }
    }

    /// itag → 오디오+영상이 한 파일에 병합된 progressive 포맷(별도 뮤엑싱 불필요).
    private static let progressiveItags: Set<Int> = [18, 22, 37, 38, 43, 44, 45, 46]

    private static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"
    private static let vrClientVersion = "1.65.10"
    private static let vrUserAgent = "com.google.android.apps.youtube.vr.oculus/\(vrClientVersion) "
        + "(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"

    public static func resolve(urlString: String) async throws -> ResolvedFormat {
        guard let videoID = YouTubeURL.videoID(from: urlString) else { throw ResolveError.invalidVideoID }

        let watchHTML = try await fetchWatchPage(videoID: videoID)
        guard let visitorData = extractVisitorData(from: watchHTML) else {
            throw ResolveError.visitorDataNotFound
        }
        let fallbackTitle = extractTitle(from: watchHTML) ?? "YouTube 레슨"

        let parsed = try await fetchPlayerResponse(videoID: videoID, visitorData: visitorData)

        if let status = parsed["playabilityStatus"]?.objectValue?["status"]?.stringValue, status != "OK" {
            let reason = parsed["playabilityStatus"]?.objectValue?["reason"]?.stringValue ?? status
            throw ResolveError.notPlayable(reason)
        }

        let formats = parsed["streamingData"]?.objectValue?["formats"]?.arrayValue?.compactMap { $0.objectValue } ?? []
        let playable = formats.filter { fmt in
            guard let itag = fmt["itag"]?.intValue, progressiveItags.contains(itag) else { return false }
            return fmt["url"]?.stringValue != nil
        }
        guard let best = playable.max(by: { ($0["itag"]?.intValue ?? 0) < ($1["itag"]?.intValue ?? 0) }),
              let urlString = best["url"]?.stringValue,
              let url = URL(string: urlString),
              let itag = best["itag"]?.intValue else {
            throw ResolveError.noProgressiveFormat
        }

        let title = parsed["videoDetails"]?.objectValue?["title"]?.stringValue ?? fallbackTitle
        let mime = best["mimeType"]?.stringValue ?? ""
        return ResolvedFormat(title: title, url: url, itag: itag, mimeType: mime)
    }

    public static func download(_ resolved: ResolvedFormat, to destinationDir: URL) async throws -> URL {
        var request = URLRequest(url: resolved.url)
        request.setValue(vrUserAgent, forHTTPHeaderField: "User-Agent")
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ResolveError.requestFailed("다운로드 HTTP 오류")
        }
        let ext = resolved.mimeType.contains("webm") ? "webm" : "mp4"
        let destination = destinationDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    private static func fetchWatchPage(videoID: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(videoID)&bpctr=9999999999&has_verified=1")!)
        request.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ResolveError.requestFailed("watch 페이지 HTTP 오류")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func fetchPlayerResponse(videoID: String, visitorData: String) async throws -> [String: JSONValue] {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(vrUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        request.setValue("28", forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(vrClientVersion, forHTTPHeaderField: "X-Youtube-Client-Version")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")

        let body: [String: JSONValue] = [
            "context": .object([
                "client": .object([
                    "clientName": .string("ANDROID_VR"),
                    "clientVersion": .string(vrClientVersion),
                    "deviceMake": .string("Oculus"),
                    "deviceModel": .string("Quest 3"),
                    "androidSdkVersion": .int(32),
                    "osName": .string("Android"),
                    "osVersion": .string("12L"),
                    "userAgent": .string(vrUserAgent),
                    "hl": .string("en"),
                    "gl": .string("US"),
                    "visitorData": .string(visitorData),
                ])
            ]),
            "videoId": .string(videoID),
            "playbackContext": .object([
                "contentPlaybackContext": .object([
                    "html5Preference": .string("HTML5_PREF_WANTS")
                ])
            ]),
            "contentCheckOk": .bool(true),
            "racyCheckOk": .bool(true),
        ]
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ResolveError.requestFailed("player API HTTP 오류")
        }
        return try JSONParsing.parseObject(String(data: data, encoding: .utf8) ?? "{}")
    }

    private static func extractVisitorData(from html: String) -> String? {
        guard let range = html.range(of: "\"visitorData\":\"") else { return nil }
        let after = html[range.upperBound...]
        guard let endRange = after.range(of: "\"") else { return nil }
        return String(after[..<endRange.lowerBound])
    }

    private static func extractTitle(from html: String) -> String? {
        guard let range = html.range(of: "<title>") else { return nil }
        let after = html[range.upperBound...]
        guard let endRange = after.range(of: "</title>") else { return nil }
        return String(after[..<endRange.lowerBound]).replacingOccurrences(of: " - YouTube", with: "")
    }
}

private extension JSONValue {
    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(v)
        default: return nil
        }
    }
}
