import Foundation

/// `backend/app/services/verification.py` 포팅. 임계값·로직 그대로 — 변경 금지.
public enum QuoteVerifierConstants {
    public static let defaultMatchThreshold = 0.75
    public static let maxWindow = 3
    public static let minQuoteChars = 4
}

public struct QuoteMatch: Sendable, Equatable {
    public var startSec: Double
    public var endSec: Double
    public var score: Double
    public var segmentIndex: Int
    public var windowSize: Int
}

private func ratio(_ a: String, _ b: String) -> Double {
    guard !a.isEmpty, !b.isEmpty else { return 0.0 }
    var matcher = SequenceMatcher(a, b)
    // quick_ratio 프리필터로 대량 비교 비용 절감 (원본과 동일)
    if matcher.quickRatio() < 0.5 { return 0.0 }
    return matcher.ratio()
}

/// 인용 vs 세그먼트 창 유사도. 부분 문자열 포함이면 1.0.
private func windowScore(_ normQuote: String, _ normWindow: String) -> Double {
    guard !normQuote.isEmpty, !normWindow.isEmpty else { return 0.0 }
    if normWindow.contains(normQuote) { return 1.0 }

    let windowChars = Array(normWindow)
    let quoteChars = Array(normQuote)
    if windowChars.count > quoteChars.count {
        var best = ratio(normQuote, normWindow)
        let qlen = quoteChars.count
        let step = max(1, qlen / 4)
        var i = 0
        while i <= windowChars.count - qlen {
            let sub = String(windowChars[i..<(i + qlen)])
            best = max(best, ratio(normQuote, sub))
            if best >= 0.999 { break }
            i += step
        }
        return best
    }
    return ratio(normQuote, normWindow)
}

/// 인용문을 전사 세그먼트(연속 창 포함)와 대조해 최적 매칭을 찾는다.
public func findQuoteMatch(
    _ quote: String,
    segments: [SttSegment],
    threshold: Double = QuoteVerifierConstants.defaultMatchThreshold,
    hintSec: Double? = nil,
    maxWindow: Int = QuoteVerifierConstants.maxWindow
) -> QuoteMatch? {
    let normQuote = normalizeText(quote)
    guard normQuote.count >= QuoteVerifierConstants.minQuoteChars, !segments.isEmpty else {
        return nil
    }

    let norms = segments.map { normalizeText($0.text) }
    var candidates: [QuoteMatch] = []

    for i in 0..<segments.count {
        var windowText = ""
        for w in 0..<maxWindow {
            let j = i + w
            if j >= segments.count { break }
            windowText += norms[j]
            if w > 0 && windowText.count > normQuote.count * 3 { break }

            let score = windowScore(normQuote, windowText)
            if score >= threshold {
                if w > 0 {
                    let tailText = String(Array(windowText)[norms[i].count...])
                    if windowScore(normQuote, tailText) >= score {
                        break
                    }
                }
                candidates.append(QuoteMatch(
                    startSec: segments[i].start,
                    endSec: segments[j].end,
                    score: score,
                    segmentIndex: i,
                    windowSize: w + 1
                ))
                break
            }
        }
    }

    guard !candidates.isEmpty else { return nil }

    if let hintSec {
        let bestScore = candidates.map(\.score).max()!
        let nearBest = candidates.filter { $0.score >= bestScore - 0.05 }
        return nearBest.min { abs($0.startSec - hintSec) < abs($1.startSec - hintSec) }
    }

    return candidates.max { $0.score < $1.score }
}
