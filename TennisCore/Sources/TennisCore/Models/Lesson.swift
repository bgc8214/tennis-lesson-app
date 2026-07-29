import Foundation
import SwiftData

@Model
public final class Lesson {
    @Attribute(.unique) public var id: UUID
    public var sourceType: String
    public var videoTitle: String?
    public var status: String
    public var createdAt: Date
    public var reportJSON: String?
    public var localVideoRef: String?
    public var lessonType: String?
    /// 13문서 대체카드 — 별점 대신 즉석 반응만 남긴다. 웹의 ReactionsMap과 동일하게
    /// 카드/타임스탬프 등 항목(targetKey)별로 "up"/"down"을 담은 JSON 딕셔너리
    /// ([String: String])을 직렬화해서 저장한다(레슨 전체가 아니라 항목 단위).
    public var reactionsJSON: String?
    public var userNote: String?
    /// 실제 레슨 날짜(사용자가 수정 가능). nil이면 createdAt(분석 시각)을 쓴다 —
    /// 옛날 영상을 나중에 분석해도 실제 날짜로 기록·정렬할 수 있게.
    public var lessonDate: Date?
    /// 원본 영상 길이(초). 카드·상세에 "32:18"처럼 표시.
    public var durationSec: Int?

    public init(
        id: UUID = UUID(),
        sourceType: String,
        videoTitle: String? = nil,
        status: String = "PENDING",
        createdAt: Date = .now,
        reportJSON: String? = nil,
        localVideoRef: String? = nil,
        lessonType: String? = nil,
        reactionsJSON: String? = nil,
        userNote: String? = nil,
        lessonDate: Date? = nil,
        durationSec: Int? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.videoTitle = videoTitle
        self.status = status
        self.createdAt = createdAt
        self.reportJSON = reportJSON
        self.localVideoRef = localVideoRef
        self.lessonType = lessonType
        self.reactionsJSON = reactionsJSON
        self.userNote = userNote
        self.lessonDate = lessonDate
        self.durationSec = durationSec
    }
}
