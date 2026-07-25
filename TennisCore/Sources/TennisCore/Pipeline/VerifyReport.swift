import Foundation

public struct VerifyStats: Sendable, Equatable {
    public var matchThreshold: Double
    public var timestampsTotal = 0
    public var timestampsVerified = 0
    public var timestampsDropped = 0
    public var cardsDropped: [String] = []
}

/// `verify_report` 포팅. LLM 리포트를 전사 원문과 대조해 검증된 사본과 통계를 반환한다.
/// 원본 parsed는 수정하지 않는다(Swift는 값 타입이라 자동으로 보장됨).
public func verifyReport(
    _ parsed: [String: JSONValue],
    segments: [SttSegment],
    threshold: Double = QuoteVerifierConstants.defaultMatchThreshold
) -> (result: [String: JSONValue], stats: VerifyStats) {
    var result = parsed
    var stats = VerifyStats(matchThreshold: threshold)

    // 1) timestamps 검증
    var verifiedTs: [[String: JSONValue]] = []
    let rawTs = parsed["timestamps"]?.arrayValue ?? []
    for item in rawTs {
        guard let itemObj = item.objectValue else { continue }
        stats.timestampsTotal += 1

        let quote = itemObj["quote"]?.stringValue ?? ""
        let hintSec = itemObj["sec"]?.doubleValue

        guard let match = findQuoteMatch(quote, segments: segments, threshold: threshold, hintSec: hintSec) else {
            stats.timestampsDropped += 1
            continue
        }

        var verified = itemObj
        verified["sec"] = .int(Int(match.startSec))
        verified["match_score"] = .double((match.score * 1000).rounded() / 1000)
        verifiedTs.append(verified)
        stats.timestampsVerified += 1
    }

    verifiedTs.sort { lhs, rhs in
        let l = lhs["sec"]?.doubleValue ?? 0
        let r = rhs["sec"]?.doubleValue ?? 0
        return l < r
    }
    result["timestamps"] = .array(verifiedTs.map { .object($0) })

    // 2) 카드 근거 검증
    for key in ["card1_problem", "card2_cueing", "card3_action"] {
        let evidenceKey = key.split(separator: "_").first.map { "\($0)_evidence" } ?? ""
        let cardValue = parsed[key]?.stringValue ?? ""
        if cardValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

        let evidence = parsed[evidenceKey]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if findQuoteMatch(evidence, segments: segments, threshold: threshold) == nil {
            result[key] = .null
            stats.cardsDropped.append(key)
        }
    }

    return (result, stats)
}
