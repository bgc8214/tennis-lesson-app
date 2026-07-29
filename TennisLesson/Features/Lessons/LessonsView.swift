import SwiftUI
import SwiftData
import TennisCore

struct LessonsView: View {
    @Binding var selectedTab: AppTab
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Lesson.createdAt, order: .reverse) private var lessons: [Lesson]

    @State private var tracker = AnalysisTracker.shared
    @State private var selectedCategory: String = "전체"
    @State private var showAnalyzeSheet = false
    @State private var thumbnails: [UUID: Image] = [:]
    @State private var renameTarget: Lesson?
    @State private var renameText = ""
    @State private var deleteTarget: Lesson?

    private var categories: [String] {
        var set = Set<String>()
        for l in lessons { l.tags.forEach { set.insert($0) } }
        return ["전체"] + set.sorted()
    }

    private var filtered: [Lesson] {
        selectedCategory == "전체" ? lessons : lessons.filter { $0.tags.contains(selectedCategory) }
    }

    private var todayLessons: [Lesson] { filtered.filter(\.isToday) }
    private var pastLessons: [Lesson] { filtered.filter { !$0.isToday } }
    private var totalCueCount: Int { lessons.reduce(0) { $0 + $1.cueCount } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if lessons.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if categories.count > 1 { categoryChips }
                        if !filtered.isEmpty { featuredSection }
                        if !todayLessons.isEmpty { group("오늘", todayLessons) }
                        if !pastLessons.isEmpty { group("지난 레슨", pastLessons) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .background(DS.pageBackground.ignoresSafeArea())
            .hideNavBar()
            .navigationDestination(for: Lesson.self) { LessonDetailView(lesson: $0) }
            .navigationDestination(for: LessonRoute.self) { r in LessonDetailView(lesson: r.lesson, initialSeekSec: r.seekSec) }
            .navigationDestination(for: KeywordRoute.self) { r in KeywordInsightView(keyword: r.keyword, lessons: lessons) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if !tracker.jobs.isEmpty { JobsBanner(tracker: tracker) }
                    TennisTabBar(selection: $selectedTab)
                }
            }
        }
        .sheet(isPresented: $showAnalyzeSheet) { AnalyzeSheet() }
        .overlay { ToastOverlay() }
        .alert("이름 수정", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("제목", text: $renameText)
            Button("취소", role: .cancel) { renameTarget = nil }
            Button("저장") {
                if let target = renameTarget {
                    let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { target.videoTitle = t; try? modelContext.save() }
                }
                renameTarget = nil
            }
        }
        .alert("레슨을 삭제할까요?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("취소", role: .cancel) { deleteTarget = nil }
            Button("삭제", role: .destructive) {
                if let target = deleteTarget { delete(target) }
                deleteTarget = nil
            }
        } message: {
            Text("삭제하면 복구할 수 없습니다.")
        }
    }

    @ViewBuilder
    private func lessonMenu(_ lesson: Lesson) -> some View {
        Button {
            renameText = lesson.displayTitle
            renameTarget = lesson
        } label: { Label("이름 수정", systemImage: "pencil") }
        Button(role: .destructive) {
            deleteTarget = lesson
        } label: { Label("삭제", systemImage: "trash") }
    }

    private func delete(_ lesson: Lesson) {
        LessonVideoStorage.delete(relativePath: lesson.localVideoRef)
        modelContext.delete(lesson)
        try? modelContext.save()
        ToastCenter.shared.show("레슨을 삭제했습니다.")
    }

    // MARK: 헤더
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 브랜드 줄: 테니스공 + "오늘의 테니스"
            HStack(spacing: 8) {
                Circle().fill(DS.brandBall).frame(width: 20, height: 20)
                    .overlay(Circle().stroke(DS.primary.opacity(0.25), lineWidth: 1))
                Text("오늘의 테니스")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.primary)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("레슨 기록")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(DS.labelStrong)
                    Text("\(lessons.count)개 레슨 · 코칭 구간 \(totalCueCount)개")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.labelAlternative)
                }
                Spacer()
                Button { showAnalyzeSheet = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                        Text("분석").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(DS.primary, in: Capsule())
                    .shadow(color: DS.primary.opacity(0.3), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    // MARK: 카테고리 칩 (활성=그린 채움 / 비활성=흰 pill)
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories, id: \.self) { cat in
                    let active = selectedCategory == cat
                    Button { selectedCategory = cat } label: {
                        Text(cat)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(active ? .white : DS.labelNormal)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(active ? DS.primary : DS.card, in: Capsule())
                            .overlay(active ? nil : Capsule().stroke(DS.lineNormal, lineWidth: 1))
                            .shadow(color: active ? DS.primary.opacity(0.25) : DS.cardShadow, radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: 최근 분석 (가로 카드)
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 분석")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.labelAlternative)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(filtered.prefix(5))) { lesson in
                        NavigationLink(value: lesson) { featuredCard(lesson) }
                            .buttonStyle(.plain)
                            .contextMenu { lessonMenu(lesson) }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
        }
    }

    private func featuredCard(_ lesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail(lesson, corner: 0)
                .frame(width: 240, height: 135)
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(lesson.displayTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.labelStrong)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(lesson.dateString + (lesson.durationString.map { " · \($0)" } ?? ""))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.labelAlternative)
                    .lineLimit(1)
            }
            .frame(width: 240, alignment: .leading)
            .padding(12)
        }
        .frame(width: 240, alignment: .leading)
        .dsCard(radius: 18)
    }

    // MARK: 그룹 리스트
    private func group(_ label: String, _ items: [Lesson]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.labelAlternative)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, lesson in
                    NavigationLink(value: lesson) { row(lesson) }
                        .buttonStyle(.plain)
                        .contextMenu { lessonMenu(lesson) }
                    if idx < items.count - 1 {
                        Rectangle().fill(DS.lineNormal).frame(height: 0.5).padding(.leading, 78)
                    }
                }
            }
            .dsCard(radius: 16)
        }
    }

    private func row(_ lesson: Lesson) -> some View {
        HStack(spacing: 12) {
            thumbnail(lesson, corner: 12)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.labelStrong)
                    .lineLimit(1)
                Text(rowSubtitle(lesson))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.labelAssistive)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.labelAssistive)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func rowSubtitle(_ lesson: Lesson) -> String {
        var parts: [String] = []
        if !lesson.tagLine.isEmpty { parts.append(lesson.tagLine) } else { parts.append(lesson.dateString) }
        if let d = lesson.durationString { parts.append(d) }
        return parts.joined(separator: " · ")
    }

    // MARK: 썸네일
    @ViewBuilder
    private func thumbnail(_ lesson: Lesson, corner: CGFloat) -> some View {
        ZStack {
            DS.fillNormal
            if let img = thumbnails[lesson.id] {
                img.resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: lesson.isYouTube ? "play.rectangle.fill" : "figure.tennis")
                    .font(.system(size: corner > 0 ? 20 : 30))
                    .foregroundStyle(DS.labelAssistive)
            }
        }
        .task(id: lesson.id) { await loadThumbnail(lesson) }
    }

    private func loadThumbnail(_ lesson: Lesson) async {
        guard thumbnails[lesson.id] == nil,
              let url = LessonVideoStorage.resolve(relativePath: lesson.localVideoRef) else { return }
        if let image = await ThumbnailCache.shared.thumbnail(for: lesson.id, videoURL: url) {
            thumbnails[lesson.id] = image
        }
    }

    // MARK: 빈 상태
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 120)
            Image(systemName: "figure.tennis")
                .font(.system(size: 44))
                .foregroundStyle(DS.labelAssistive)
            Text("아직 레슨이 없어요")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DS.labelStrong)
            Text("영상을 선택해서 첫 레슨을 분석해보세요.")
                .font(.system(size: 14))
                .foregroundStyle(DS.labelAlternative)
            Button { showAnalyzeSheet = true } label: {
                Text("레슨 분석 시작")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(DS.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
}

/// 분석 큐 배너(하단 탭바 위) — 진행 중 + 대기 + 실패 작업을 스택으로 보여준다.
struct JobsBanner: View {
    var tracker: AnalysisTracker

    var body: some View {
        VStack(spacing: 6) {
            ForEach(tracker.jobs.prefix(4)) { job in
                JobRow(job: job, tracker: tracker)
            }
            if tracker.jobs.count > 4 {
                Text("+\(tracker.jobs.count - 4)개 더")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.labelAlternative)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

private struct JobRow: View {
    let job: AnalysisJob
    var tracker: AnalysisTracker

    var body: some View {
        HStack(spacing: 10) {
            leadingIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.labelNormal).lineLimit(1)
                Text(message).font(.system(size: 11)).foregroundStyle(job.isFailed ? DS.negative : DS.labelAlternative).lineLimit(1)
                if let f = fraction {
                    ProgressView(value: f).tint(DS.primary)
                }
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: DS.cardShadow, radius: 6, y: 2)
    }

    @ViewBuilder private var leadingIcon: some View {
        switch job.phase {
        case .queued:
            Image(systemName: "clock").font(.system(size: 14)).foregroundStyle(DS.labelAssistive)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14)).foregroundStyle(DS.negative)
        default:
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder private var trailing: some View {
        if job.isFailed {
            Button { tracker.retry(job) } label: {
                Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(DS.primary)
            }.buttonStyle(.plain)
            Button { tracker.dismiss(job) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(DS.labelAssistive)
            }.buttonStyle(.plain)
        } else {
            Button { tracker.cancel(job) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(DS.labelAssistive)
            }.buttonStyle(.plain)
        }
    }

    private var fraction: Double? {
        if case .running(_, let f) = job.phase { return f }
        return nil
    }

    private var message: String {
        switch job.phase {
        case .queued: return "대기 중"
        case .importingFromPhotos: return "불러오는 중..."
        case .downloadingYouTube: return "YouTube 다운로드 중..."
        case .extractingAudio: return "오디오 추출 중..."
        case .running(let m, let f): return f != nil ? "\(m) \(Int((f ?? 0) * 100))%" : m
        case .failed(let msg): return "실패: \(msg)"
        default: return "진행 중..."
        }
    }
}
