import SwiftUI
import SwiftData
import TennisCore

@main
struct TennisLessonApp: App {
    init() {
        // BGContinuedProcessingTask launch handler는 앱이 실행을 마치기 전에
        // 등록해야 한다(등록 자체는 iOS 26에서 지연 등록 예외지만, 가장 안전한
        // 시점은 여전히 init). 같은 식별자를 두 번 등록하면 시스템이 앱을 강제
        // 종료하므로 AnalysisTracker 내부에서 1회 가드한다.
        #if os(iOS)
        AnalysisTracker.shared.registerBackgroundTask()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task { AnalysisNotifier.requestAuthorizationIfNeeded() }
        }
        .modelContainer(for: Lesson.self)
    }
}
