import SwiftUI

enum AppTab { case lessons, report }

struct RootTabView: View {
    @State private var selectedTab: AppTab = .lessons

    var body: some View {
        Group {
            switch selectedTab {
            case .lessons: LessonsView(selectedTab: $selectedTab)
            case .report:  InsightsReportView(selectedTab: $selectedTab)
            }
        }
        .background(DS.pageBackground.ignoresSafeArea())
    }
}

/// 하단 커스텀 탭바(레슨 / 리포트) — 목업 스타일.
struct TennisTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            tab(.lessons, label: "레슨") {
                VStack(spacing: 3.5) {
                    RoundedRectangle(cornerRadius: 1).frame(width: 16, height: 3)
                    RoundedRectangle(cornerRadius: 1).frame(width: 16, height: 3)
                    RoundedRectangle(cornerRadius: 1).frame(width: 10, height: 3).frame(width: 16, alignment: .leading)
                }
            }
            tab(.report, label: "리포트") {
                HStack(alignment: .bottom, spacing: 3) {
                    RoundedRectangle(cornerRadius: 1).frame(width: 4, height: 8)
                    RoundedRectangle(cornerRadius: 1).frame(width: 4, height: 13)
                    RoundedRectangle(cornerRadius: 1).frame(width: 4, height: 17)
                }
                .frame(height: 18, alignment: .bottom)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(DS.lineNormal).frame(height: 0.5) }
    }

    private func tab<Icon: View>(_ tab: AppTab, label: String, @ViewBuilder icon: () -> Icon) -> some View {
        let active = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                icon().frame(height: 22)
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(active ? DS.primary : DS.labelAssistive)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
