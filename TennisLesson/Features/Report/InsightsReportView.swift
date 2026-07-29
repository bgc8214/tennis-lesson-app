import SwiftUI
import SwiftData
import TennisCore

struct InsightsReportView: View {
    @Binding var selectedTab: AppTab
    @Query(sort: \Lesson.createdAt, order: .reverse) private var lessons: [Lesson]
    @State private var tracker = AnalysisTracker.shared

    private var totalCueCount: Int { lessons.reduce(0) { $0 + $1.cueCount } }

    private var topTag: String {
        var freq: [String: Int] = [:]
        for l in lessons { l.tags.forEach { freq[$0, default: 0] += 1 } }
        return freq.max { $0.value < $1.value }?.key ?? "-"
    }

    /// 키워드 빈도 상위(막대그래프용).
    private var topKeywords: [(text: String, count: Int, pct: Double)] {
        var counts: [String: Int] = [:]
        for l in lessons {
            guard let r = l.decodedReport else { continue }
            for kw in r.keywords { counts[kw, default: 0] += 1 }
        }
        let sorted = counts.sorted { $0.value > $1.value }.prefix(6)
        let maxV = Double(sorted.first?.value ?? 1)
        return sorted.map { ($0.key, $0.value, Double($0.value) / maxV) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statTiles
                    if !topKeywords.isEmpty { keywordChart }
                    if !lessons.isEmpty { recentActivity }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(DS.pageBackground.ignoresSafeArea())
            .hideNavBar()
            .navigationDestination(for: Lesson.self) { LessonDetailView(lesson: $0) }
            .navigationDestination(for: KeywordRoute.self) { r in KeywordInsightView(keyword: r.keyword, lessons: lessons) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if !tracker.jobs.isEmpty { JobsBanner(tracker: tracker) }
                    TennisTabBar(selection: $selectedTab)
                }
            }
        }
        .overlay { ToastOverlay() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("리포트")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(DS.labelStrong)
            Text("누적된 레슨 데이터로 만든 요약이에요")
                .font(.system(size: 14))
                .foregroundStyle(DS.labelAlternative)
        }
        .padding(.top, 8)
    }

    private var statTiles: some View {
        HStack(spacing: 10) {
            statTile("\(lessons.count)개", "분석된 레슨")
            statTile("\(totalCueCount)개", "코칭 구간")
            statTile(topTag, "최다 태그")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(DS.labelStrong).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 12)).foregroundStyle(DS.labelAlternative)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .dsCard()
    }

    private var keywordChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("자주 반복된 지적")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS.labelStrong)
            VStack(spacing: 14) {
                ForEach(topKeywords, id: \.text) { kw in
                    NavigationLink(value: KeywordRoute(keyword: kw.text)) {
                        VStack(spacing: 6) {
                            HStack {
                                Text(kw.text).font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.labelNormal)
                                Spacer()
                                Text("\(kw.count)회").font(.system(size: 13)).foregroundStyle(DS.labelAssistive)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(DS.fillNormal)
                                    Capsule().fill(DS.primary).frame(width: max(8, geo.size.width * kw.pct))
                                }
                            }
                            .frame(height: 7)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .dsCard()
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 활동")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS.labelStrong)
            VStack(spacing: 0) {
                let items = Array(lessons.prefix(5))
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, lesson in
                    NavigationLink(value: lesson) {
                        HStack {
                            Text(lesson.displayTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DS.labelStrong)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(lesson.dateString)
                                .font(.system(size: 12))
                                .foregroundStyle(DS.labelAssistive)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if idx < items.count - 1 {
                        Rectangle().fill(DS.lineNormal).frame(height: 0.5).padding(.horizontal, 14)
                    }
                }
            }
            .dsCard()
        }
    }
}
