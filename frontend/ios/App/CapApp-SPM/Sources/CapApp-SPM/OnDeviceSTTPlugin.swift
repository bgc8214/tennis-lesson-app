import Foundation
import Capacitor
import AVFoundation
import Speech

/**
 * iOS 26 SpeechAnalyzer(온디바이스)로 로컬 오디오 파일을 전사한다.
 *
 * 실측 결과(2026-07-25, 골든셋 대조): 이 도메인(소음 많은 한국어 테니스 코칭)에서
 * 정확도가 낮게 나왔다(29건 중 2건 매칭). 프로덕션 STT 경로로 쓰라는 뜻이 아니라
 * "온디바이스로 돌려보고 싶다"는 요청에 따른 실험용 플러그인이다.
 */
@objc(OnDeviceSTTPlugin)
public class OnDeviceSTTPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "OnDeviceSTTPlugin"
    public let jsName = "OnDeviceSTT"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "transcribe", returnType: CAPPluginReturnPromise)
    ]

    @objc func isAvailable(_ call: CAPPluginCall) {
        if #available(iOS 26.0, *) {
            call.resolve(["available": true])
        } else {
            call.resolve(["available": false, "reason": "iOS 26 이상 필요"])
        }
    }

    @objc func transcribe(_ call: CAPPluginCall) {
        guard let pathOrUri = call.getString("path") else {
            call.reject("path 파라미터가 필요합니다")
            return
        }
        let localeId = call.getString("language") ?? "ko-KR"

        guard #available(iOS 26.0, *) else {
            call.reject("iOS 26 이상에서만 지원됩니다")
            return
        }

        Task {
            do {
                SFSpeechRecognizer.requestAuthorization { _ in }

                let fileURL = Self.resolveURL(pathOrUri)
                let result = try await Self.runTranscription(fileURL: fileURL, localeId: localeId)
                call.resolve(result)
            } catch {
                call.reject("전사 실패: \(error.localizedDescription)")
            }
        }
    }

    private static func resolveURL(_ pathOrUri: String) -> URL {
        if pathOrUri.hasPrefix("file://") {
            return URL(string: pathOrUri) ?? URL(fileURLWithPath: pathOrUri)
        }
        return URL(fileURLWithPath: pathOrUri)
    }

    @available(iOS 26.0, *)
    private static func runTranscription(fileURL: URL, localeId: String) async throws -> [String: Any] {
        let requested = Locale(identifier: localeId)
        guard let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw NSError(domain: "OnDeviceSTT", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "locale \(localeId) not supported"
            ])
        }

        let transcriber = SpeechTranscriber(
            locale: resolvedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )

        let status = await AssetInventory.status(forModules: [transcriber])
        if status != .installed {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }
        _ = try await AssetInventory.reserve(locale: resolvedLocale)
        defer {
            Task { _ = await AssetInventory.release(reservedLocale: resolvedLocale) }
        }

        let audioFile = try AVAudioFile(forReading: fileURL)

        var segments: [[String: Any]] = []
        let resultsTask = Task {
            for try await result in transcriber.results {
                let range = result.range
                segments.append([
                    "startSec": range.start.seconds,
                    "endSec": range.end.seconds,
                    "text": String(result.text.characters)
                ])
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        _ = try await analyzer.analyzeSequence(from: audioFile)
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await resultsTask.value

        let fullText = segments.compactMap { $0["text"] as? String }.joined(separator: " ")
        return [
            "locale": resolvedLocale.identifier,
            "segments": segments,
            "fullText": fullText
        ]
    }
}
