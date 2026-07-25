import Foundation

/// `backend/app/services/stt_filters.py` 포팅. 상수·로직 그대로 — 임계값 변경 금지.
public enum SttFiltersConstants {
    public static let noSpeechProbThreshold = 0.6
    public static let avgLogprobThreshold = -1.0
    public static let compressionRatioThreshold = 2.4
    public static let dedupeSimilarityThreshold = 0.9
}

public struct SttSegment: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var text: String
    public var noSpeechProb: Double?
    public var avgLogprob: Double?
    public var compressionRatio: Double?

    public init(
        start: Double,
        end: Double,
        text: String,
        noSpeechProb: Double? = nil,
        avgLogprob: Double? = nil,
        compressionRatio: Double? = nil
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.noSpeechProb = noSpeechProb
        self.avgLogprob = avgLogprob
        self.compressionRatio = compressionRatio
    }
}

public struct FilterStats: Sendable, Equatable {
    public var total = 0
    public var droppedNoSpeech = 0
    public var droppedLogprob = 0
    public var droppedCompression = 0
    public var droppedRepeat = 0
    public var droppedEmpty = 0
    public var kept = 0
}

/// 비교용 정규화: 소문자화 + 한글/영숫자 외 문자 제거. `[^0-9a-z가-힣]+` 그대로.
public func normalizeText(_ value: String?) -> String {
    let lowered = (value ?? "").lowercased()
    return lowered.unicodeScalars
        .filter { scalar in
            (scalar.value >= 0x30 && scalar.value <= 0x39) ||   // 0-9
            (scalar.value >= 0x61 && scalar.value <= 0x7A) ||   // a-z
            (scalar.value >= 0xAC00 && scalar.value <= 0xD7A3)  // 가-힣
        }
        .map { Character($0) }
        .reduce(into: "") { $0.append($1) }
}

private func similarity(_ a: String, _ b: String) -> Double {
    guard !a.isEmpty, !b.isEmpty else { return 0.0 }
    var matcher = SequenceMatcher(a, b)
    return matcher.ratio()
}

/// 환청 의심 세그먼트를 제거하고 (통과 세그먼트, 통계)를 반환한다.
/// 제거 규칙 순서: 빈 텍스트 → compression_ratio → avg_logprob → no_speech_prob → 반복 dedupe.
public func filterHallucinatedSegments(
    _ segments: [SttSegment],
    noSpeechThreshold: Double = SttFiltersConstants.noSpeechProbThreshold,
    logprobThreshold: Double = SttFiltersConstants.avgLogprobThreshold,
    compressionRatioThreshold: Double = SttFiltersConstants.compressionRatioThreshold,
    dedupeSimilarity: Double = SttFiltersConstants.dedupeSimilarityThreshold
) -> (kept: [SttSegment], stats: FilterStats) {
    var stats = FilterStats(total: segments.count)
    var kept: [SttSegment] = []
    var prevNorm = ""

    for seg in segments {
        let norm = normalizeText(seg.text)
        if norm.isEmpty {
            stats.droppedEmpty += 1
            continue
        }

        if let cr = seg.compressionRatio, cr > compressionRatioThreshold {
            stats.droppedCompression += 1
            continue
        }

        if let lp = seg.avgLogprob, lp < logprobThreshold {
            stats.droppedLogprob += 1
            continue
        }

        if let nsp = seg.noSpeechProb, nsp > noSpeechThreshold {
            stats.droppedNoSpeech += 1
            continue
        }

        if !prevNorm.isEmpty,
           norm == prevNorm || similarity(norm, prevNorm) >= dedupeSimilarity {
            stats.droppedRepeat += 1
            continue
        }

        kept.append(seg)
        prevNorm = norm
    }

    stats.kept = kept.count
    return (kept, stats)
}

/// 세그먼트 목록을 '[시작초~종료초] 텍스트' 라인 포맷으로 직렬화.
public func segmentsToTranscriptText(_ segments: [SttSegment]) -> String {
    segments
        .map { seg in
            String(format: "[%.1f~%.1f] %@", seg.start, seg.end, seg.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .joined(separator: "\n")
}
