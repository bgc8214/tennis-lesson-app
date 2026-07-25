import Foundation

/// `gemini_service.py`의 `_generate_report_from_audio_path` 포팅.
/// STT 전사 → 환청 필터 → Pass A(피드백 추출) → 코드 레벨 인용 검증 →
/// Pass B(카드 종합) → 최종 리포트 dict. WHISPER_PASS_A_WINDOW_SEC가 서버에서도
/// 항상 24시간(사실상 단일 창)으로 고정돼 있으므로, 창 분할 없이 단일 Pass A
/// 호출로 단순화했다(서버의 실제 런타임 동작과 동일).
public struct ReportBuilder: Sendable {
    private let sttEngine: any SttEngine
    private let gemini: GeminiClient
    private let sttLanguage: String
    private let sttPrompt: String?

    public init(sttEngine: any SttEngine, gemini: GeminiClient, sttLanguage: String = "ko", sttPrompt: String? = nil) {
        self.sttEngine = sttEngine
        self.gemini = gemini
        self.sttLanguage = sttLanguage
        self.sttPrompt = sttPrompt
    }

    public enum BuildError: Error, CustomStringConvertible {
        case emptyTranscript
        case noVerifiedFeedback

        public var description: String {
            switch self {
            case .emptyTranscript: return "전사 결과가 비어 있습니다 (발화 없음 또는 전부 환청 필터링됨)"
            case .noVerifiedFeedback: return "검증을 통과한 피드백이 없습니다 (전사에 실제 코치 발언이 없거나 추출 실패)"
            }
        }
    }

    public func build(
        audioURL: URL,
        modelName: String,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> [String: JSONValue] {
        onProgress?("음성 인식 중...")
        let rawSegments = try await sttEngine.transcribe(audioURL: audioURL, language: sttLanguage, prompt: sttPrompt)
        let (segments, filterStats) = filterHallucinatedSegments(rawSegments)
        guard !segments.isEmpty else { throw BuildError.emptyTranscript }

        let transcriptText = segmentsToTranscriptText(segments)

        onProgress?("오답노트 정리 중...")
        let windowMinutes = max(1, Int((segments.last!.end / 60).rounded()))
        let minCount = max(1, Int((Double(Prompts.passAMinPer10Min) * Double(windowMinutes) / 10).rounded()))
        let maxCount = max(minCount, Int((Double(Prompts.passAMaxPer10Min) * Double(windowMinutes) / 10).rounded()))

        let passAPrompt = Prompts.passATemplate
            .replacingOccurrences(of: "{window_label}", with: "0~\(windowMinutes)분")
            .replacingOccurrences(of: "{transcript}", with: transcriptText)
            .replacingOccurrences(of: "{window_minutes}", with: "\(windowMinutes)")
            .replacingOccurrences(of: "{min_count}", with: "\(minCount)")
            .replacingOccurrences(of: "{max_count}", with: "\(maxCount)")

        var rawFeedbacks: [JSONValue] = []
        do {
            let responseText = try await gemini.generateContent(prompt: passAPrompt)
            let parsed = try JSONParsing.parseObject(responseText)
            rawFeedbacks = parsed["feedbacks"]?.arrayValue ?? []
        } catch {
            // 서버와 동일하게 Pass A 실패는 빈 피드백으로 처리(전체 실패시키지 않음)
            rawFeedbacks = []
        }

        // 4) 코드 레벨 인용 검증
        let pseudoReport: [String: JSONValue] = ["timestamps": .array(rawFeedbacks)]
        let (verifiedA, verifyStats) = verifyReport(pseudoReport, segments: segments)
        let verifiedFeedbacks = verifiedA["timestamps"]?.arrayValue?.compactMap { $0.objectValue } ?? []
        guard !verifiedFeedbacks.isEmpty else { throw BuildError.noVerifiedFeedback }

        // 5) Pass B — 검증된 피드백만 종합
        var categoryCounts: [String: Int] = [:]
        for fb in verifiedFeedbacks {
            if let cat = fb["category"]?.stringValue, !cat.isEmpty {
                categoryCounts[cat, default: 0] += 1
            }
        }

        let feedbackLines = verifiedFeedbacks.map { fb -> String in
            let cat = fb["category"]?.stringValue ?? ""
            let countNote = (categoryCounts[cat] ?? 0) > 1 ? " (\(categoryCounts[cat]!)회 중 하나)" : ""
            let sec = Int(fb["sec"]?.doubleValue ?? 0)
            let type = fb["type"]?.stringValue ?? ""
            let label = fb["label"]?.stringValue ?? ""
            let quote = fb["quote"]?.stringValue ?? ""
            let problem = fb["problem"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? "(없음)"
            let fix = fb["fix"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? "(없음)"
            return """
            - [\(sec)초][\(type)][\(cat)\(countNote)] \(label)
              quote(이 줄 전체를 그대로 복사할 것): "\(quote)"
              문제: \(problem) / 교정: \(fix)
            """
        }
        let verifiedFeedbacksText = feedbackLines.joined(separator: "\n")

        let passBPrompt = Prompts.passBTemplate.replacingOccurrences(of: "{verified_feedbacks}", with: verifiedFeedbacksText)
        let passBResponseText = try await gemini.generateContent(prompt: passBPrompt)
        let parsedB = try JSONParsing.parseObject(passBResponseText)

        let pseudoCards: [String: JSONValue] = [
            "card1_problem": parsedB["card1_problem"] ?? .null,
            "card1_evidence": parsedB["card1_evidence"] ?? .null,
            "card2_cueing": parsedB["card2_cueing"] ?? .null,
            "card2_evidence": parsedB["card2_evidence"] ?? .null,
            "card3_action": parsedB["card3_action"] ?? .null,
            "card3_evidence": parsedB["card3_evidence"] ?? .null,
        ]
        let (verifiedB, cardVerifyStats) = verifyReport(pseudoCards, segments: segments)

        let combinedVerifyStats: [String: JSONValue] = [
            "match_threshold": .double(QuoteVerifierConstants.defaultMatchThreshold),
            "timestamps_total": .int(verifyStats.timestampsTotal),
            "timestamps_verified": .int(verifyStats.timestampsVerified),
            "timestamps_dropped": .int(verifyStats.timestampsDropped),
            "cards_dropped": .array(cardVerifyStats.cardsDropped.map { .string($0) }),
            "pass_a_windows": .int(1),
        ]

        let compactedTimestamps = ReportCoercion.compactTimestamps(
            ReportCoercion.coerceTimestamps(.array(verifiedFeedbacks.map { .object($0) }))
        )

        let result: [String: JSONValue] = [
            "card1_problem": .stringOrNull(verifiedB["card1_problem"]?.stringValue),
            "card1_evidence": .stringOrNull(verifiedB["card1_evidence"]?.stringValue),
            "card2_cueing": .stringOrNull(verifiedB["card2_cueing"]?.stringValue),
            "card2_evidence": .stringOrNull(verifiedB["card2_evidence"]?.stringValue),
            "card3_action": .stringOrNull(verifiedB["card3_action"]?.stringValue),
            "card3_evidence": .stringOrNull(verifiedB["card3_evidence"]?.stringValue),
            "full_summary": .stringOrNull(parsedB["full_summary"]?.stringValue),
            "keywords": .array(ReportCoercion.coerceKeywords(parsedB["keywords"]).map { .string($0) }),
            "lesson_type": .array(ReportCoercion.coerceLessonType(parsedB["lesson_type"]).map { .string($0) }),
            "steps": .array(ReportCoercion.coerceSteps(parsedB["steps"]).map { .string($0) }),
            "scenarios": .array(ReportCoercion.coerceScenarios(parsedB["scenarios"]).map { .object($0.mapValues { .string($0) }) }),
            "timestamps": .array(compactedTimestamps.map { .object($0) }),
            "gemini_model": .string(modelName),
            "transcript_text": .string(transcriptText),
            "ai_context": .array(ReportCoercion.coerceAiContext(parsedB["ai_context"]).map { .object($0.mapValues { .string($0) }) }),
            "transcript_quality": .string("low"),
            "stt_stats": .object([
                "provider": .string("on-device"),
                "total": .int(filterStats.total),
                "kept": .int(filterStats.kept),
                "dropped_no_speech": .int(filterStats.droppedNoSpeech),
                "dropped_logprob": .int(filterStats.droppedLogprob),
                "dropped_compression": .int(filterStats.droppedCompression),
                "dropped_repeat": .int(filterStats.droppedRepeat),
                "dropped_empty": .int(filterStats.droppedEmpty),
            ]),
            "verification": .object(combinedVerifyStats),
        ]

        return result
    }
}

private extension JSONValue {
    static func stringOrNull(_ value: String?) -> JSONValue {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return .null }
        return .string(v)
    }
}
