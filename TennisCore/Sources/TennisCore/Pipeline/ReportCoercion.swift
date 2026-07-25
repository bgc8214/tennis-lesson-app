import Foundation

/// `gemini_service.py`의 `_coerce_*`/`_compact_timestamps`/`_is_near_duplicate`/
/// `_timestamp_score` 포팅. LLM 원시 출력을 안전한 구조로 정제하는 로직 그대로.
public enum ReportCoercion {
    static let maxTimelineItems = 45
    static let timelineDedupWindowSec = 25
    static let timelineMinGapSec = 35

    public static func coerceKeywords(_ value: JSONValue?) -> [String] {
        guard let arr = value?.arrayValue else { return [] }
        return Array(arr.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3))
    }

    public static func coerceLessonType(_ value: JSONValue?) -> [String] {
        guard let arr = value?.arrayValue else { return [] }
        var out: [String] = []
        for item in arr {
            guard let s = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            if Prompts.allowedLessonTypes.contains(s) && !out.contains(s) {
                out.append(s)
            }
        }
        return Array(out.prefix(3))
    }

    public static func coerceSteps(_ value: JSONValue?) -> [String] {
        guard let arr = value?.arrayValue else { return [] }
        return Array(arr.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(6))
    }

    public static func coerceScenarios(_ value: JSONValue?) -> [[String: String]] {
        guard let arr = value?.arrayValue else { return [] }
        var out: [[String: String]] = []
        for item in arr {
            guard let obj = item.objectValue else { continue }
            let condition = obj["condition"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let action = obj["action"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !condition.isEmpty && !action.isEmpty {
                out.append(["condition": condition, "action": action])
            }
        }
        return Array(out.prefix(4))
    }

    public static func coerceAiContext(_ value: JSONValue?) -> [[String: String]] {
        guard let arr = value?.arrayValue else { return [] }
        var out: [[String: String]] = []
        for item in arr {
            guard let obj = item.objectValue else { continue }
            let title = obj["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let note = obj["note"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty && !note.isEmpty {
                out.append(["title": String(title.prefix(20)), "note": String(note.prefix(200))])
            }
        }
        return Array(out.prefix(3))
    }

    static func normalizeImportance(_ value: JSONValue?) -> String {
        let s = (value?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["high", "medium", "low"].contains(s) ? s : "medium"
    }

    static func normalizeTextForDedupe(_ value: String?) -> String {
        normalizeText(value)
    }

    static func isEmptyish(_ value: String?) -> Bool {
        let n = normalizeTextForDedupe(value)
        return n.isEmpty || n == "none" || n == "null" || n == "없음"
    }

    static let progressWords = [
        "시작", "준비", "하나둘", "세개", "다시", "오케이",
        "좋아", "그렇지", "자", "아기핸드폰",
    ]

    static func isProgressOnlyFeedback(_ item: [String: JSONValue]) -> Bool {
        let text = ["label", "quote", "problem", "fix"]
            .map { item[$0]?.stringValue ?? "" }
            .joined(separator: " ")
        let normalized = normalizeTextForDedupe(text)
        guard progressWords.contains(where: { normalized.contains($0) }) else { return false }
        let type = item["type"]?.stringValue
        let importance = item["importance"]?.stringValue
        return type == "드릴" || importance == "low"
    }

    static func timestampScore(_ item: [String: JSONValue]) -> Double {
        var score = 0.0
        let importance = normalizeImportance(item["importance"])
        if importance == "high" { score += 3.0 }
        else if importance == "medium" { score += 1.5 }

        if item["type"]?.stringValue == "교정" { score += 1.0 }
        else if item["type"]?.stringValue == "전술" { score += 0.8 }

        score += item["confidence"]?.doubleValue ?? 0.0

        if !isEmptyish(item["problem"]?.stringValue) { score += 0.8 }
        if !isEmptyish(item["fix"]?.stringValue) { score += 0.5 }

        if isProgressOnlyFeedback(item) { score -= 4.0 }
        if importance == "low" { score -= 2.0 }
        return score
    }

    static func isNearDuplicate(_ a: [String: JSONValue], _ b: [String: JSONValue]) -> Bool {
        let secA = Int(a["sec"]?.doubleValue ?? 0)
        let secB = Int(b["sec"]?.doubleValue ?? 0)
        if abs(secA - secB) > timelineDedupWindowSec { return false }

        for key in ["quote", "label", "problem", "fix"] {
            let av = normalizeTextForDedupe(a[key]?.stringValue)
            let bv = normalizeTextForDedupe(b[key]?.stringValue)
            if !av.isEmpty && !bv.isEmpty && av == bv { return true }
        }

        return normalizeTextForDedupe(a["category"]?.stringValue) == normalizeTextForDedupe(b["category"]?.stringValue)
            && normalizeTextForDedupe(a["label"]?.stringValue) == normalizeTextForDedupe(b["label"]?.stringValue)
    }

    /// Dense chunk feedbacks를 복기용 핵심 타임라인으로 압축한다.
    public static func compactTimestamps(_ timestamps: [[String: JSONValue]]) -> [[String: JSONValue]] {
        guard !timestamps.isEmpty else { return [] }

        let ordered = timestamps.sorted { Int($0["sec"]?.doubleValue ?? 0) < Int($1["sec"]?.doubleValue ?? 0) }
        var deduped: [[String: JSONValue]] = []
        for item in ordered {
            if isProgressOnlyFeedback(item) && normalizeImportance(item["importance"]) != "high" {
                continue
            }
            if let dupIdx = deduped.firstIndex(where: { isNearDuplicate(item, $0) }) {
                if timestampScore(item) > timestampScore(deduped[dupIdx]) {
                    deduped[dupIdx] = item
                }
            } else {
                deduped.append(item)
            }
        }

        if deduped.count <= maxTimelineItems {
            return deduped.sorted { Int($0["sec"]?.doubleValue ?? 0) < Int($1["sec"]?.doubleValue ?? 0) }
        }

        let ranked = deduped.enumerated().sorted { timestampScore($0.element) > timestampScore($1.element) }
        var selected: [(offset: Int, element: [String: JSONValue])] = []
        for entry in ranked {
            let sec = Int(entry.element["sec"]?.doubleValue ?? 0)
            let tooClose = selected.contains { abs(sec - Int($0.element["sec"]?.doubleValue ?? 0)) < timelineMinGapSec }
            if tooClose { continue }
            selected.append(entry)
            if selected.count >= maxTimelineItems { break }
        }
        if selected.count < maxTimelineItems {
            var selectedOffsets = Set(selected.map(\.offset))
            for entry in ranked {
                if selectedOffsets.contains(entry.offset) { continue }
                selected.append(entry)
                selectedOffsets.insert(entry.offset)
                if selected.count >= maxTimelineItems { break }
            }
        }

        return selected.map(\.element).sorted { Int($0["sec"]?.doubleValue ?? 0) < Int($1["sec"]?.doubleValue ?? 0) }
    }

    public static func coerceTimestamps(_ value: JSONValue?) -> [[String: JSONValue]] {
        guard let arr = value?.arrayValue else { return [] }
        var out: [[String: JSONValue]] = []
        for item in arr {
            guard let obj = item.objectValue, let secRaw = obj["sec"]?.doubleValue else { continue }
            let sec = Int(secRaw)
            if sec < 0 { continue }

            var tsType = obj["type"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !["교정", "드릴", "전술"].contains(tsType) { tsType = "교정" }

            var coerced: [String: JSONValue] = [
                "sec": .int(sec),
                "type": .string(tsType),
                "category": obj["category"]?.stringValue.map { .string($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? .null,
                "label": .string(obj["label"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? obj["label"]!.stringValue!.trimmingCharacters(in: .whitespacesAndNewlines) : "주요 지적"),
                "quote": obj["quote"]?.stringValue.map { .string($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? .null,
                "problem": obj["problem"]?.stringValue.map { .string($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? .null,
                "fix": obj["fix"]?.stringValue.map { .string($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? .null,
                "importance": .string(normalizeImportance(obj["importance"])),
            ]
            if let confidence = obj["confidence"]?.doubleValue {
                coerced["confidence"] = .double((min(max(confidence, 0.0), 1.0) * 100).rounded() / 100)
            } else {
                coerced["confidence"] = .null
            }
            if let matchScore = obj["match_score"]?.doubleValue {
                coerced["match_score"] = .double((min(max(matchScore, 0.0), 1.0) * 1000).rounded() / 1000)
            }
            out.append(coerced)
        }
        return out
    }
}
