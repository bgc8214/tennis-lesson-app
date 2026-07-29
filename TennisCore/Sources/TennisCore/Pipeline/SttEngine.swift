import Foundation

/// STT 엔진 추상화. WhisperKit 등 실제 구현은 앱 타깃에 둔다(TennisCore는
/// 무거운 온디바이스 모델 의존성 없이 파이프라인 로직만 단위 테스트 가능해야 함).
///
/// `onProgress`: 온디바이스 전사는 수 분 걸리므로, 전체 오디오 대비 진행률(0~1)을
/// 주기적으로 알려 UI/백그라운드 작업 진행률을 갱신하게 한다(nil이면 미보고).
public protocol SttEngine: Sendable {
    func transcribe(
        audioURL: URL,
        language: String,
        prompt: String?,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> [SttSegment]
}
