import Foundation

/// 레슨 영상을 앱 Documents 아래 영구 보관해 타임스탬프 점프 재생에 쓴다.
/// 이미 우리 샌드박스 안으로 복사한 파일이라 보안 스코프 북마크가 필요 없다 —
/// `Lesson.localVideoRef`에는 Documents 기준 상대 경로만 저장(재설치돼도 앱
/// 컨테이너 UUID만 바뀌므로 절대경로 대신 상대경로라야 안전).
enum LessonVideoStorage {
    private static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func persist(sourceURL: URL, lessonID: UUID) throws -> String {
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let dir = documentsURL().appendingPathComponent("Lessons").appendingPathComponent(lessonID.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("source").appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return "Lessons/\(lessonID.uuidString)/source.\(ext)"
    }

    static func resolve(relativePath: String?) -> URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        let url = documentsURL().appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(relativePath: String?) {
        guard let url = resolve(relativePath: relativePath) else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
