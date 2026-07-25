import SwiftUI
import SwiftData
import TennisCore

@main
struct TennisLessonApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .modelContainer(for: Lesson.self)
    }
}
