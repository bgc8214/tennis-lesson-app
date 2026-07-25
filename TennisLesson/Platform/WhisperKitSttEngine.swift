import Foundation
import WhisperKit
import TennisCore

/// WhisperKit(온디바이스 large-v3)로 `SttEngine`을 구현한다.
///
/// 2026-07-25 실측(골든셋 29건 대조): Apple SpeechAnalyzer 6.9%, WhisperKit
/// medium(VAD 켬/끔 모두) 0~0%, WhisperKit large-v3 7.7% — 서버 local(medium)의
/// 17.2%에는 못 미치지만 온디바이스 후보 중 그나마 나은 옵션이라 large-v3로 확정.
/// `TENNIS_TERM_HINT` 프롬프트 주입은 large-v3에서 힌트 단어를 그대로 앵무새처럼
/// 반복하는 새로운 할루시네이션을 유발함이 실측으로 확인돼 사용하지 않는다.
/// `chunkingStrategy`는 기본값(nil, VAD 미사용)을 그대로 둔다 — VAD를 켜면 이
/// 도메인 오디오(라켓 타격음·원거리 마이크)에서 실제 발화 대부분을 침묵으로
/// 오판해 스킵하는 문제가 실측으로 확인됨.
public final class WhisperKitSttEngine: SttEngine, @unchecked Sendable {
    public static let modelName = "large-v3"

    private var pipe: WhisperKit?
    private let loadLock = NSLock()

    public init() {}

    private func ensureLoaded() async throws -> WhisperKit {
        if let pipe { return pipe }
        let config = WhisperKitConfig(
            model: Self.modelName,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            download: true
        )
        let loaded = try await WhisperKit(config)
        self.pipe = loaded
        return loaded
    }

    public func transcribe(audioURL: URL, language: String, prompt: String?) async throws -> [SttSegment] {
        let whisperKit = try await ensureLoaded()

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0
            // compressionRatioThreshold/logProbThreshold/noSpeechThreshold는
            // WhisperKit 기본값(2.4/-1.0/0.6)이 서버 임계값과 동일해 그대로 둔다.
        )

        let results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)

        var segments: [SttSegment] = []
        for result in results {
            for seg in result.segments {
                let text = Self.stripSpecialTokens(seg.text).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                segments.append(SttSegment(
                    start: Double(seg.start),
                    end: Double(seg.end),
                    text: text,
                    noSpeechProb: Double(seg.noSpeechProb),
                    avgLogprob: Double(seg.avgLogprob),
                    compressionRatio: Double(seg.compressionRatio)
                ))
            }
        }
        segments.sort { $0.start < $1.start }
        return segments
    }

    /// WhisperKit 세그먼트 텍스트에 `<|startoftranscript|>`, `<|ko|>`, `<|2.00|>` 같은
    /// 특수/타임스탬프 토큰이 그대로 섞여 나오는 경우가 있어 걷어낸다.
    private static func stripSpecialTokens(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<\\|[^|]*\\|>") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
