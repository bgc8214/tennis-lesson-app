import SwiftUI
import TennisCore

/// 대시보드 키워드 칩을 눌렀을 때 이동하는 경로 — 어떤 키워드인지만 담는다.
struct KeywordRoute: Hashable {
    let keyword: String
}

/// 레슨 상세로 이동하되, 특정 타임스탬프로 바로 시크하고 싶을 때 쓰는 경로.
/// 일반 목록에서의 이동(`.navigationDestination(for: Lesson.self)`)과 구분한다.
struct LessonRoute: Hashable {
    let lesson: Lesson
    let seekSec: Int?
}

/// 웹 버전의 `/insights?keyword=` — 특정 키워드(고질병)가 나온 모든 레슨과
/// 그 순간의 타임스탬프를 한 화면에 모아, 눌러서 바로 그 순간으로 이동한다.
struct KeywordInsightView: View {
    let keyword: String
    let lessons: [Lesson]

    private struct Entry: Identifiable {
        let lesson: Lesson
        let report: Report
        var id: UUID { lesson.id }
    }

    private var entries: [Entry] {
        lessons.compactMap { lesson in
            guard let json = lesson.reportJSON, let report = try? Report.decode(fromJSON: json) else { return nil }
            guard report.keywords.contains(keyword) else { return nil }
            return Entry(lesson: lesson, report: report)
        }
        .sorted { $0.lesson.createdAt > $1.lesson.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if entries.isEmpty {
                    ContentUnavailableView("관련 레슨을 찾을 수 없습니다", systemImage: "magnifyingglass")
                        .padding(.top, 40)
                } else {
                    Text("\(entries.count)개 레슨에서 반복")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(entries) { entry in
                        entrySection(entry)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("#\(keyword)")
    }

    @ViewBuilder
    private func entrySection(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: LessonRoute(lesson: entry.lesson, seekSec: nil)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.lesson.videoTitle ?? "제목 없음").font(.headline)
                    Text(entry.lesson.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if entry.report.timestamps.isEmpty {
                Text("이 레슨엔 타임스탬프가 없어요").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entry.report.timestamps) { ts in
                    NavigationLink(value: LessonRoute(lesson: entry.lesson, seekSec: ts.sec)) {
                        timestampRow(ts, quality: entry.report.transcriptQuality)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func timestampRow(_ item: Report.TimestampItem, quality: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timeString(item.sec))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label).font(.subheadline)
                // 15문서 2-A: high가 아니면(이 앱은 항상 low) quote 원문 노출 안 함.
                if quality == "high", let quote = item.quote, !quote.isEmpty {
                    Text("“\(quote)”").font(.caption).foregroundStyle(.secondary)
                }
                if let fix = item.fix, !fix.isEmpty {
                    Text(fix).font(.caption).foregroundStyle(.blue)
                }
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func timeString(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
}
