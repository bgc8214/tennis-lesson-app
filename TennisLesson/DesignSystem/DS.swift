import SwiftUI

/// Wanted 디자인 시스템 토큰(Claude Design 목업)을 SwiftUI로 옮긴 것.
/// 목업이 라이트 모드 기준이라 라이트 값을 우선으로 하되, 다크에서도 읽히도록
/// 주요 색은 light/dark 동적 값으로 정의한다.
enum DS {
    // MARK: 색상 토큰 — 테니스 그린 테마
    static let primary = dynamic(light: rgb(80, 168, 96), dark: rgb(120, 200, 135))           // 메인 그린
    static let primaryStrong = dynamic(light: rgb(60, 140, 78), dark: rgb(140, 210, 155))
    /// 상단 브랜드 원(테니스공) — 밝은 라임.
    static let brandBall = dynamic(light: rgb(170, 214, 88), dark: rgb(180, 224, 100))

    static let labelStrong = dynamic(light: rgb(0, 0, 0), dark: rgb(255, 255, 255))           // --label-strong
    static let labelNormal = dynamic(light: rgb(23, 23, 23), dark: rgb(247, 247, 247))        // --label-normal
    static let labelAlternative = dynamic(light: rgba(55, 56, 60, 0.61), dark: rgba(174, 176, 182, 0.61)) // --label-alternative
    static let labelAssistive = dynamic(light: rgba(55, 56, 60, 0.28), dark: rgba(174, 176, 182, 0.28))   // --label-assistive

    static let fillNormal = dynamic(light: rgba(112, 115, 124, 0.08), dark: rgba(112, 115, 124, 0.22))    // --fill-normal
    static let fillStrong = dynamic(light: rgba(112, 115, 124, 0.16), dark: rgba(112, 115, 124, 0.28))    // --fill-strong
    static let lineNormal = dynamic(light: rgba(112, 115, 124, 0.22), dark: rgba(112, 115, 124, 0.32))    // --line-normal-normal

    /// 페이지 배경 — 민트빛 그린 톤(라이트) / 다크 대응.
    static let pageBackground = dynamic(light: rgb(233, 242, 229), dark: rgb(14, 17, 14))
    /// 카드 표면.
    static let card = dynamic(light: rgb(255, 255, 255), dark: rgb(30, 34, 30))

    // 인사이트 3색 (고질병 / 코치 큐잉 / 다음 액션)
    static let negative = dynamic(light: rgb(255, 66, 66), dark: rgb(255, 99, 99))            // --status-negative
    static let positive = dynamic(light: rgb(0, 191, 64), dark: rgb(30, 212, 90))             // --status-positive
    static let negativeBg = dynamic(light: rgb(254, 236, 236), dark: rgba(255, 66, 66, 0.16)) // --red-95
    static let primaryBg = dynamic(light: rgb(224, 240, 226), dark: rgba(80, 168, 96, 0.20))  // 연한 그린
    static let positiveBg = dynamic(light: rgb(217, 255, 230), dark: rgba(0, 191, 64, 0.16))  // --green-95
    static let greenAccent = dynamic(light: rgb(0, 150, 50), dark: rgb(30, 212, 90))          // --status-positive(파일 아이콘)

    // "코치 큐잉" 인사이트 카드는 3색 구분을 위해 primary(그린)와 별개의 파랑을 쓴다.
    static let info = dynamic(light: rgb(51, 102, 255), dark: rgb(91, 132, 255))
    static let infoBg = dynamic(light: rgb(234, 242, 254), dark: rgba(51, 102, 255, 0.18))

    // 카드 그림자
    static let cardShadow = Color.black.opacity(0.05)

    // MARK: 헬퍼
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
    }
    private static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    #if os(iOS)
    private static func dynamic(light: Color, dark: Color) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
    #else
    private static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
    }
    #endif
}

extension View {
    /// 목업의 흰 카드 스타일(둥근 모서리 + 옅은 그림자).
    func dsCard(radius: CGFloat = 16) -> some View {
        self
            .background(DS.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: DS.cardShadow, radius: 8, x: 0, y: 2)
    }

    /// 커스텀 헤더를 쓰므로 기본 내비게이션 바를 숨긴다(iOS 전용 API를 크로스플랫폼으로 감쌈).
    @ViewBuilder
    func hideNavBar() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
