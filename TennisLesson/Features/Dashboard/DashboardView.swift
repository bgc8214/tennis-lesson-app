import SwiftUI
import SwiftData
import TennisCore

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Lesson.createdAt, order: .reverse) private var lessons: [Lesson]
    @State private var selectedType: String?

    private var availableTypes: [String] {
        let all = lessons.compactMap(\.lessonType).flatMap { $0.split(separator: ",").map(String.init) }
        return Array(Set(all)).sorted()
    }

    private var filteredLessons: [Lesson] {
        guard let selectedType else { return lessons }
        return lessons.filter { ($0.lessonType ?? "").contains(selectedType) }
    }

    /// 최근 레슨들의 keywords를 모아 빈도순으로 — 리포트 JSON을 다시 디코딩하는
    /// 비용이 들지만 개인용 앱 규모(레슨 수십 개)에서는 무시할 수준.
    private var topKeywords: [(word: String, count: Int)] {
        var counts: [String: Int] = [:]
        for lesson in lessons {
            guard let json = lesson.reportJSON, let report = try? Report.decode(fromJSON: json) else { continue }
            for kw in report.keywords { counts[kw, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if lessons.isEmpty {
                    ContentUnavailableView(
                        "아직 레슨이 없어요",
                        systemImage: "figure.tennis",
                        description: Text("영상을 선택해서 첫 레슨을 분석해보세요.")
                    )
                } else {
                    List {
                        if !availableTypes.isEmpty {
                            Section {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        filterChip(label: "전체", isSelected: selectedType == nil) { selectedType = nil }
                                        ForEach(availableTypes, id: \.self) { type in
                                            filterChip(label: type, isSelected: selectedType == type) { selectedType = type }
                                        }
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }

                        if !topKeywords.isEmpty {
                            Section("자주 나온 키워드") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(topKeywords, id: \.word) { item in
                                            Text("\(item.word) \(item.count)")
                                                .font(.caption)
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Color.gray.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }

                        Section("레슨 목록") {
                            ForEach(filteredLessons) { lesson in
                                NavigationLink(value: lesson) {
                                    lessonRow(lesson)
                                }
                            }
                            .onDelete(perform: deleteLessons)
                        }
                    }
                }
            }
            .navigationTitle("오늘의 테니스")
            .navigationDestination(for: Lesson.self) { lesson in
                ReportView(lesson: lesson)
            }
            .toolbar {
                if !lessons.isEmpty, let backupURL = makeBackupFile() {
                    ToolbarItem {
                        ShareLink(item: backupURL) {
                            Image(systemName: "square.and.arrow.up.on.square")
                        }
                    }
                }
                ToolbarItem {
                    NavigationLink("분석") { AnalyzeView() }
                }
            }
        }
    }

    /// R4 완화(무료 서명 7일 재서명 시 SwiftData 유실 대비) — 전체 레슨을 JSON으로
    /// 내보내 공유 시트(파일 앱/AirDrop 등)로 백업할 수 있게 한다.
    private func makeBackupFile() -> URL? {
        let items: [[String: String]] = lessons.map { lesson in
            [
                "id": lesson.id.uuidString,
                "sourceType": lesson.sourceType,
                "videoTitle": lesson.videoTitle ?? "",
                "status": lesson.status,
                "createdAt": ISO8601DateFormatter().string(from: lesson.createdAt),
                "lessonType": lesson.lessonType ?? "",
                "userReaction": lesson.userReaction ?? "",
                "userNote": lesson.userNote ?? "",
                "reportJSON": lesson.reportJSON ?? "",
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tennis-lesson-backup.json")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func lessonRow(_ lesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lesson.videoTitle ?? "제목 없음")
                .font(.headline)
            HStack(spacing: 8) {
                Text(lesson.createdAt, style: .date)
                statusBadge(lesson.status)
                if let types = lesson.lessonType, !types.isEmpty {
                    Text(types.split(separator: ",").joined(separator: " · "))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(status == "DONE" ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
            .clipShape(Capsule())
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func deleteLessons(at offsets: IndexSet) {
        for index in offsets {
            let lesson = filteredLessons[index]
            LessonVideoStorage.delete(relativePath: lesson.localVideoRef)
            modelContext.delete(lesson)
        }
        try? modelContext.save()
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: Lesson.self, inMemory: true)
}
