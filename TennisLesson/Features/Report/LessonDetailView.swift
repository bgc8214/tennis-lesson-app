import SwiftUI
import SwiftData
import AVKit
import TennisCore

enum DetailPanel: String, CaseIterable { case summary = "요약", cues = "코칭 구간", insights = "인사이트" }

struct LessonDetailView: View {
    @Bindable var lesson: Lesson
    var initialSeekSec: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var report: Report?
    @State private var player: AVPlayer?
    @State private var panel: DetailPanel = .summary
    @State private var didInitialSeek = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showDateEdit = false
    @State private var editDate = Date()
    @FocusState private var noteFocused: Bool

    private var showQuote: Bool { report?.transcriptQuality == "high" }
    private var hasVideo: Bool { LessonVideoStorage.resolve(relativePath: lesson.localVideoRef) != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topBar
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.displayTitle)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(DS.labelStrong)
                    Text(lesson.dateString + (lesson.durationString.map { " · \($0)" } ?? ""))
                        .font(.system(size: 13))
                        .foregroundStyle(DS.labelAlternative)
                }

                videoArea

                if hasVideo, let report, !report.timestamps.isEmpty {
                    cueNavBar(report)
                }

                if let report, !lesson.tags.isEmpty { tagChips(lesson.tags) }

                segment

                if let report {
                    switch panel {
                    case .summary:  summaryPanel(report)
                    case .cues:     cuesPanel(report)
                    case .insights: insightsPanel(report)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(DS.pageBackground.ignoresSafeArea())
        .hideNavBar()
        .task { decode() }
        .onDisappear(perform: save)
        .alert("이름 수정", isPresented: $showRename) {
            TextField("제목", text: $renameText)
            Button("취소", role: .cancel) {}
            Button("저장") {
                let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                lesson.videoTitle = t.isEmpty ? lesson.videoTitle : t
                save()
            }
        }
        .alert("레슨을 삭제할까요?", isPresented: $showDeleteConfirm) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) { deleteLesson() }
        } message: {
            Text("삭제하면 복구할 수 없습니다.")
        }
        .sheet(isPresented: $showDateEdit) {
            NavigationStack {
                DatePicker("레슨 날짜", selection: $editDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("날짜 수정")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("취소") { showDateEdit = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("저장") { lesson.lessonDate = editDate; save(); showDateEdit = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    private func deleteLesson() {
        LessonVideoStorage.delete(relativePath: lesson.localVideoRef)
        modelContext.delete(lesson)
        try? modelContext.save()
        ToastCenter.shared.show("레슨을 삭제했습니다.")
        dismiss()
    }

    // MARK: 상단 바(뒤로 + 공유)
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    Text("레슨").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(DS.primary)
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 8) {
                if let report {
                    ShareLink(item: shareText(report)) {
                        circleIcon("square.and.arrow.up")
                    }
                }
                Menu {
                    Button {
                        renameText = lesson.displayTitle
                        showRename = true
                    } label: { Label("이름 수정", systemImage: "pencil") }
                    Button {
                        editDate = lesson.displayDate
                        showDateEdit = true
                    } label: { Label("날짜 수정", systemImage: "calendar") }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: { Label("삭제", systemImage: "trash") }
                } label: {
                    circleIcon("ellipsis")
                }
            }
        }
        .padding(.top, 8)
    }

    private func circleIcon(_ system: String) -> some View {
        Image(systemName: system)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DS.labelNormal)
            .frame(width: 34, height: 34)
            .background(DS.fillNormal, in: Circle())
    }

    // MARK: 영상 영역
    @ViewBuilder
    private var videoArea: some View {
        ZStack {
            if let url = LessonVideoStorage.resolve(relativePath: lesson.localVideoRef) {
                VideoPlayer(player: player)
                    .onAppear { if player == nil { player = AVPlayer(url: url); performInitialSeek() } }
            } else {
                // YouTube 등 로컬 영상이 없는 경우 — 목업의 정적 프레임.
                ZStack {
                    Color.black
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.white.opacity(0.85))
                    VStack {
                        HStack {
                            Text(lesson.isYouTube ? "YouTube 분석" : "영상 없음")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(.black.opacity(0.55), in: Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)
                }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 재생 중 현재 위치를 기준으로 이전/다음 코칭 구간으로 바로 점프하는 바.
    /// 로컬 영상(seek 가능)이 있을 때만 표시된다(호출부에서 hasVideo 가드).
    private func cueNavBar(_ report: Report) -> some View {
        let secs = report.timestamps.map(\.sec).sorted()
        return HStack(spacing: 0) {
            cueNavButton(system: "chevron.backward", label: "이전 코칭") {
                jumpCue(secs, direction: -1)
            }
            Rectangle().fill(DS.lineNormal).frame(width: 1, height: 20)
            cueNavButton(system: "chevron.forward", label: "다음 코칭", trailing: true) {
                jumpCue(secs, direction: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    private func cueNavButton(system: String, label: String, trailing: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !trailing { Image(systemName: system) }
                Text(label)
                if trailing { Image(systemName: system) }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(DS.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 현재 재생 지점 기준으로 앞/뒤 코칭 구간을 찾아 seek한다.
    /// 이전(-1): 방금 시작한 구간에서 누르면 그 구간을 다시 재생하지 않고 진짜
    /// 이전 구간으로 가도록 1.5초 여유를 둔다. 다음(+1): 바로 뒤 구간으로.
    private func jumpCue(_ secs: [Int], direction: Int) {
        guard !secs.isEmpty else { return }
        let now = player?.currentTime().seconds ?? 0
        let target: Int
        if direction < 0 {
            target = secs.last(where: { Double($0) < now - 1.5 }) ?? secs.first!
        } else {
            target = secs.first(where: { Double($0) > now + 0.5 }) ?? secs.last!
        }
        seek(target)
    }

    // MARK: 태그 칩
    private func tagChips(_ tags: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(tags, id: \.self) { t in
                Text(t)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.labelNormal)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(DS.fillNormal, in: Capsule())
            }
        }
    }

    // MARK: 3패널 세그먼트
    private var segment: some View {
        HStack(spacing: 2) {
            ForEach(DetailPanel.allCases, id: \.self) { p in
                let active = panel == p
                Button { panel = p } label: {
                    Text(p.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? DS.labelStrong : DS.labelAlternative)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(active ? DS.card : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .shadow(color: active ? Color.black.opacity(0.12) : .clear, radius: 3, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(DS.fillNormal, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 요약
    @ViewBuilder
    private func summaryPanel(_ report: Report) -> some View {
        let text = report.fullSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        Text(text?.isEmpty == false ? text! : "요약이 아직 없어요.")
            .font(.system(size: 15))
            .lineSpacing(6)
            .foregroundStyle(DS.labelNormal)
    }

    // MARK: 코칭 구간
    @ViewBuilder
    private func cuesPanel(_ report: Report) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(showQuote ? "코치 피드백 — 눌러서 영상 이동" : "발언 인용 대신 코칭 구간 중심으로 안내해요 — 정확한 발언은 영상에서 직접 확인하세요")
                .font(.system(size: 12))
                .foregroundStyle(DS.labelAlternative)
            if report.timestamps.isEmpty {
                Text("코칭 구간이 없어요.").font(.system(size: 14)).foregroundStyle(DS.labelAssistive)
            } else {
                ForEach(report.timestamps) { cue in
                    cueCard(cue)
                }
            }
        }
    }

    private func cueCard(_ cue: Report.TimestampItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Button { seek(cue.sec) } label: {
                    Text(timeString(cue.sec))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(DS.primary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!hasVideo)
                Text(cue.label).font(.system(size: 14, weight: .bold)).foregroundStyle(DS.labelStrong)
                Spacer(minLength: 0)
            }
            if showQuote, let q = cue.quote, !q.isEmpty {
                Text("“\(q)”").font(.system(size: 13)).italic().foregroundStyle(DS.labelAlternative)
            }
            HStack(spacing: 8) {
                if let fix = cue.fix, !fix.isEmpty {
                    Text("→ \(fix)").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.primary)
                }
                Spacer(minLength: 0)
                ReactionPills(value: reactionBinding("timestamp:\(cue.sec)"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    // MARK: 인사이트
    @ViewBuilder
    private func insightsPanel(_ report: Report) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 10) {
                insightCard(icon: "!", title: "고질병", body: report.card1Problem,
                            color: DS.negative, bg: DS.negativeBg, key: "card1_problem")
                insightCard(icon: "\u{201C}", title: "코치 큐잉", body: report.card2Cueing,
                            color: DS.info, bg: DS.infoBg, key: "card2_cueing")
                insightCard(icon: "→", title: "다음 액션", body: report.card3Action,
                            color: DS.positive, bg: DS.positiveBg, key: "card3_action")
            }
            if !report.keywords.isEmpty {
                HStack(spacing: 8) {
                    ForEach(report.keywords, id: \.self) { kw in
                        Text(kw).font(.system(size: 12, weight: .medium)).foregroundStyle(DS.labelNormal)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(DS.fillNormal, in: Capsule())
                    }
                }
            }
            notePad
        }
    }

    @ViewBuilder
    private func insightCard(icon: String, title: String, body: String?, color: Color, bg: Color, key: String) -> some View {
        if let body, !body.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 8) {
                        Text(icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(color, in: Circle())
                        Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(color)
                    }
                    Spacer()
                    ReactionPills(value: reactionBinding(key))
                }
                Text(body).font(.system(size: 13)).lineSpacing(4).foregroundStyle(DS.labelNormal)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var notePad: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.primary)
                Text("메모")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.labelStrong)
                Spacer(minLength: 0)
                if noteFocused {
                    Button("완료") { noteFocused = false }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.primary)
                        .buttonStyle(.plain)
                }
            }
            TextField("오늘 기억에 남는 코칭을 적어두세요", text: noteBinding, axis: .vertical)
                .font(.system(size: 15))
                .lineSpacing(3)
                .lineLimit(1...8)
                .textFieldStyle(.plain)
                .tint(DS.primary)
                .focused($noteFocused)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    // MARK: 반응/메모 저장
    private var reactions: [String: String] {
        guard let json = lesson.reactionsJSON, let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private func reactionBinding(_ key: String) -> Binding<String?> {
        Binding(
            get: { reactions[key] },
            set: { newValue in
                var dict = reactions
                dict[key] = newValue
                if let data = try? JSONEncoder().encode(dict), let json = String(data: data, encoding: .utf8) {
                    lesson.reactionsJSON = json
                    save()
                }
            }
        )
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { lesson.userNote ?? "" },
            set: { lesson.userNote = $0.isEmpty ? nil : $0; save() }
        )
    }

    private func save() { try? modelContext.save() }

    // MARK: 헬퍼
    private func decode() {
        report = lesson.decodedReport
        performInitialSeek()
    }

    private func seek(_ sec: Int) {
        player?.seek(to: CMTime(seconds: Double(sec), preferredTimescale: 600))
        player?.play()
    }

    private func performInitialSeek() {
        guard !didInitialSeek, let sec = initialSeekSec, player != nil else { return }
        didInitialSeek = true
        seek(sec)
    }

    private func shareText(_ report: Report) -> String {
        var lines = ["🎾 \(lesson.displayTitle)"]
        if let p = report.card1Problem { lines.append("\n[고질병]\n\(p)") }
        if let c = report.card2Cueing { lines.append("\n[코치 큐잉]\n\(c)") }
        if let a = report.card3Action { lines.append("\n[다음 액션]\n\(a)") }
        lines.append("\n— 오늘의 테니스")
        return lines.joined(separator: "\n")
    }

    private func timeString(_ sec: Int) -> String { String(format: "%d:%02d", sec / 60, sec % 60) }
}

/// 항목별 👍/👎 (목업 스타일 원형 pill).
struct ReactionPills: View {
    @Binding var value: String?

    var body: some View {
        HStack(spacing: 6) {
            pill(system: "hand.thumbsup.fill", target: "up", on: DS.primaryBg, onColor: DS.primary)
            pill(system: "hand.thumbsdown.fill", target: "down", on: DS.negativeBg, onColor: DS.negative)
        }
    }

    private func pill(system: String, target: String, on: Color, onColor: Color) -> some View {
        let active = value == target
        return Button { value = active ? nil : target } label: {
            Image(systemName: system)
                .font(.system(size: 12))
                .foregroundStyle(active ? onColor : DS.labelAssistive)
                .frame(width: 26, height: 26)
                .background(active ? on : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
