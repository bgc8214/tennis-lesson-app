import SwiftUI

/// 웹 버전의 ToastProvider(Toast.tsx)와 동일한 역할 — 삭제/저장 등 조용히 지나가기
/// 쉬운 동작에 짧은 피드백을 준다. 앱 전역 싱글턴이라 어느 화면에서 호출해도 된다.
@Observable
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()
    private init() {}

    struct ToastItem: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    private(set) var current: ToastItem?

    func show(_ message: String) {
        let item = ToastItem(message: message)
        current = item
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if current?.id == item.id { current = nil }
        }
    }
}

/// 화면 루트(예: DashboardView)의 `.overlay`로 붙여서 쓴다.
struct ToastOverlay: View {
    @State private var center = ToastCenter.shared

    var body: some View {
        VStack {
            if let toast = center.current {
                Text(toast.message)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
            Spacer()
        }
        .animation(.spring(duration: 0.3), value: center.current)
        .allowsHitTesting(false)
    }
}
