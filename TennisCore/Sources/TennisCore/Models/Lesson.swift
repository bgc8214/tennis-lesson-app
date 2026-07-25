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
    /// "up" | "down" | nil(무응답). 13문서 대체카드 — 별점 대신 즉석 반응만 남긴다.
    public var userReaction: String?
    public var userNote: String?

    public init(
        id: UUID = UUID(),
        sourceType: String,
        videoTitle: String? = nil,
        status: String = "PENDING",
        createdAt: Date = .now,
        reportJSON: String? = nil,
        localVideoRef: String? = nil,
        lessonType: String? = nil,
        userReaction: String? = nil,
        userNote: String? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.videoTitle = videoTitle
        self.status = status
        self.createdAt = createdAt
        self.reportJSON = reportJSON
        self.localVideoRef = localVideoRef
        self.lessonType = lessonType
        self.userReaction = userReaction
        self.userNote = userNote
    }
}
