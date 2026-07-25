import Foundation

/// STT 엔진 추상화. WhisperKit 등 실제 구현은 앱 타깃에 둔다(TennisCore는
/// 무거운 온디바이스 모델 의존성 없이 파이프라인 로직만 단위 테스트 가능해야 함).
public protocol SttEngine: Sendable {
    func transcribe(audioURL: URL, language: String, prompt: String?) async throws -> [SttSegment]
}
