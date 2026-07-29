import Foundation
import TennisCore

/// Lesson(SwiftData) + Report(디코딩)을 UI에서 쓰기 쉬운 형태로 묶는 헬퍼.
extension Lesson {
    var decodedReport: Report? {
        guard let json = reportJSON else { return nil }
        return try? Report.decode(fromJSON: json)
    }

    var displayTitle: String { videoTitle ?? "제목 없는 레슨" }

    var tags: [String] {
        (lessonType ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var tagLine: String { tags.joined(separator: " · ") }

    /// 표시·정렬에 쓰는 날짜(사용자 지정 우선, 없으면 분석 시각).
    var displayDate: Date { lessonDate ?? createdAt }

    var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: displayDate)
    }

    /// "32:18" / "1:02:18" 형태의 길이 문자열. 없으면 nil.
    var durationString: String? {
        guard let s = durationSec, s > 0 else { return nil }
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// 이 레슨이 오늘 날짜인지(그룹 헤더용).
    var isToday: Bool { Calendar.current.isDateInToday(displayDate) }

    var isYouTube: Bool { sourceType == "youtube" }

    /// 코칭 구간(타임스탬프) 개수.
    var cueCount: Int { decodedReport?.timestamps.count ?? 0 }
}
