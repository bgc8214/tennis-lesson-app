import Testing
@testable import TennisCore

@Test func lessonDefaultsToPending() {
    let lesson = Lesson(sourceType: "upload")
    #expect(lesson.status == "PENDING")
}
