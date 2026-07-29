import Foundation
import CryptoKit

/// 이미 배포돼 있는 Cloud Run 백엔드(`cursor/tennis-lesson/backend`, FastAPI)를 호출한다.
/// 온디바이스 WhisperKit large-v3가 실기기에서 5분 영상 11분에도 15%밖에 못 가는
/// 수준으로 느려(2026-07-27 실측), STT를 서버(Groq whisper-large-v3-turbo 등)로 옮긴다.
///
/// - 영상은 기기에 남고, **추출한 오디오만** 업로드된다(백엔드 `/analyze-upload`는
///   애초에 오디오만 받는 계약). 서버가 STT→필터→Pass A/B→리포트까지 수행하고,
///   앱은 완료된 리포트만 받아 로컬 SwiftData에 저장한다.
/// - 인증: 토큰 없이 호출하면 서버가 익명 사용자로 처리하므로(개인 앱) 로그인 불필요.
public struct BackendClient: Sendable {
    public struct Resolved: Sendable {
        public let reportJSON: String
        public let lessonType: [String]
        public let title: String?
    }

    public enum BackendError: Error, CustomStringConvertible {
        case requestFailed(String)
        case analysisFailed(String)
        case timedOut

        public var description: String {
            switch self {
            case .requestFailed(let m): return "서버 요청 실패: \(m)"
            case .analysisFailed(let m): return "서버 분석 실패: \(m)"
            case .timedOut: return "서버 분석이 시간 내에 끝나지 않았습니다"
            }
        }
    }

    // 배포된 백엔드(공개 엔드포인트, 비밀 아님). 필요 시 교체.
    public static let defaultBaseURL = URL(string: "https://tennis-lesson-api-598483148792.asia-northeast3.run.app")!

    private let baseURL: URL

    public init(baseURL: URL = BackendClient.defaultBaseURL) {
        self.baseURL = baseURL
    }

    /// 추출한 오디오를 업로드해 분석을 큐잉하고, 완료될 때까지 폴링해 리포트를 돌려준다.
    public func analyzeUpload(
        audioURL: URL,
        durationSec: Int,
        title: String?,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> Resolved {
        onStatus?("서버로 오디오 업로드 중...")
        let audioData = try Data(contentsOf: audioURL)
        let fileHash = SHA256.hash(data: audioData).map { String(format: "%02x", $0) }.joined()

        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/lessons/analyze-upload"))
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        let body = Self.multipartBody(
            boundary: boundary,
            audioData: audioData,
            audioFilename: audioURL.lastPathComponent,
            fields: [
                "duration_sec": String(durationSec),
                "file_hash": fileHash,
                "title": title ?? "",
            ]
        )

        // -1005("network connection was lost")는 iOS URLSession의 HTTP/2 연결
        // 재사용/유휴 후 첫 요청에서 흔히 나는 일시 오류라 재시도로 넘긴다. 업로드는
        // httpBody 대신 upload(for:from:)를 써야 스트리밍/재시도가 안정적이다.
        let (data, response) = try await performRequest(request, uploadBody: body, onStatus: onStatus)
        guard let http = response as? HTTPURLResponse else { throw BackendError.requestFailed("응답 없음") }

        let parsed = try JSONParsing.parseObject(String(data: data, encoding: .utf8) ?? "{}")
        let lessonID: String
        if http.statusCode == 409 {
            // 같은 오디오를 이미 분석함 — 기존 레슨을 재사용.
            guard let existing = parsed["error"]?.objectValue?["details"]?.objectValue?["existing_lesson_id"]?.stringValue else {
                throw BackendError.requestFailed("중복인데 기존 lesson_id를 못 찾음")
            }
            lessonID = existing
        } else if (200..<300).contains(http.statusCode) {
            guard let id = parsed["data"]?.objectValue?["lesson_id"]?.stringValue else {
                throw BackendError.requestFailed("lesson_id 없음")
            }
            lessonID = id
        } else {
            let msg = parsed["error"]?.objectValue?["message"]?.stringValue ?? "HTTP \(http.statusCode)"
            throw BackendError.requestFailed(msg)
        }

        return try await pollUntilDone(lessonID: lessonID, onStatus: onStatus)
    }

    /// YouTube URL을 서버에 넘겨 분석(서버가 yt-dlp 다운로드+STT까지 처리)하고 폴링한다.
    public func analyzeYouTube(
        urlString: String,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> Resolved {
        onStatus?("서버에 YouTube 분석 요청 중...")
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/lessons/analyze"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: JSONValue] = ["youtube_url": .string(urlString)]
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        request.timeoutInterval = 60

        let (data, response) = try await performRequest(request, uploadBody: nil, onStatus: onStatus)
        guard let http = response as? HTTPURLResponse else { throw BackendError.requestFailed("응답 없음") }
        let parsed = try JSONParsing.parseObject(String(data: data, encoding: .utf8) ?? "{}")

        let lessonID: String
        if http.statusCode == 409,
           let existing = parsed["error"]?.objectValue?["details"]?.objectValue?["existing_lesson_id"]?.stringValue {
            lessonID = existing
        } else if (200..<300).contains(http.statusCode),
                  let id = parsed["data"]?.objectValue?["lesson_id"]?.stringValue {
            lessonID = id
        } else {
            let msg = parsed["error"]?.objectValue?["message"]?.stringValue ?? "HTTP \(http.statusCode)"
            throw BackendError.requestFailed(msg)
        }
        return try await pollUntilDone(lessonID: lessonID, onStatus: onStatus)
    }

    /// 레슨 상세를 주기적으로 조회해 DONE(리포트)·FAILED가 될 때까지 대기한다.
    private func pollUntilDone(
        lessonID: String,
        onStatus: (@Sendable (String) -> Void)?,
        timeout: TimeInterval = 600
    ) async throws -> Resolved {
        onStatus?("서버에서 분석 중...")
        let deadline = Date().addingTimeInterval(timeout)
        let detailURL = baseURL.appendingPathComponent("api/v1/lessons/\(lessonID)")

        while Date() < deadline {
            var request = URLRequest(url: detailURL)
            request.timeoutInterval = 30
            // 폴링 중 일시 네트워크 오류는 실패로 던지지 말고 다음 틱에 재시도.
            guard let (data, response) = try? await performRequest(request, uploadBody: nil, onStatus: nil) else {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                let parsed = try JSONParsing.parseObject(String(data: data, encoding: .utf8) ?? "{}")
                let dataObj = parsed["data"]?.objectValue ?? [:]
                let status = dataObj["processing_status"]?.stringValue ?? "PENDING"

                if status == "DONE" {
                    let reportValue = dataObj["report"] ?? .null
                    let reportData = try JSONEncoder().encode(reportValue)
                    let reportJSON = String(data: reportData, encoding: .utf8) ?? "{}"
                    let lessonType = dataObj["lesson_type"]?.arrayValue?.compactMap { $0.stringValue } ?? []
                    let title = dataObj["title"]?.stringValue
                    return Resolved(reportJSON: reportJSON, lessonType: lessonType, title: title)
                } else if status == "FAILED" {
                    let msg = dataObj["report"]?.objectValue?["error_message"]?.stringValue ?? "서버가 분석에 실패했습니다"
                    throw BackendError.analysisFailed(msg)
                }
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw BackendError.timedOut
    }

    /// 일시적 네트워크 오류(-1005 연결 끊김, 타임아웃 등)는 몇 번 재시도한다.
    /// uploadBody가 있으면 업로드 전용 API(upload(for:from:))를 쓴다(대용량 바디에
    /// httpBody+data(for:)보다 안정적).
    private func performRequest(
        _ request: URLRequest,
        uploadBody: Data?,
        onStatus: (@Sendable (String) -> Void)?,
        attempts: Int = 3
    ) async throws -> (Data, URLResponse) {
        var lastError: Error = BackendError.requestFailed("네트워크")
        for attempt in 0..<attempts {
            do {
                if let uploadBody {
                    return try await URLSession.shared.upload(for: request, from: uploadBody)
                } else {
                    return try await URLSession.shared.data(for: request)
                }
            } catch let error as URLError where Self.isTransient(error) {
                lastError = error
                if attempt < attempts - 1 {
                    onStatus?("네트워크 재시도 중... (\(attempt + 2)/\(attempts))")
                    try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_500_000_000)
                    continue
                }
            }
        }
        throw lastError
    }

    private static func isTransient(_ e: URLError) -> Bool {
        switch e.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .notConnectedToInternet, .dnsLookupFailed, .cannotFindHost,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private static func multipartBody(
        boundary: String,
        audioData: Data,
        audioFilename: String,
        fields: [String: String]
    ) -> Data {
        var body = Data()
        let boundaryLine = "--\(boundary)\r\n"
        for (key, value) in fields {
            body.append(Data(boundaryLine.utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data(boundaryLine.utf8))
        body.append(Data("Content-Disposition: form-data; name=\"audio\"; filename=\"\(audioFilename)\"\r\n".utf8))
        body.append(Data("Content-Type: audio/m4a\r\n\r\n".utf8))
        body.append(audioData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
