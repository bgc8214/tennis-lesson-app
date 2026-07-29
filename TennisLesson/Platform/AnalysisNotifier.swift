import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// 분석 완료/실패를 알린다: 앱을 보고 있으면 햅틱, 백그라운드면 로컬 알림.
/// (분석이 수 분 걸릴 수 있어, 다른 앱을 보고 있어도 끝난 걸 알 수 있게.)
@MainActor
enum AnalysisNotifier {
    private static var authRequested = false

    /// 앱 시작 시 한 번 알림 권한을 요청(거부해도 햅틱은 동작).
    static func requestAuthorizationIfNeeded() {
        guard !authRequested else { return }
        authRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyDone(title: String) {
        #if os(iOS)
        if UIApplication.shared.applicationState == .active {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            post(title: "분석 완료", body: title)
        }
        #else
        post(title: "분석 완료", body: title)
        #endif
    }

    static func notifyFailed(title: String) {
        #if os(iOS)
        if UIApplication.shared.applicationState == .active {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } else {
            post(title: "분석 실패", body: title)
        }
        #else
        post(title: "분석 실패", body: title)
        #endif
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
