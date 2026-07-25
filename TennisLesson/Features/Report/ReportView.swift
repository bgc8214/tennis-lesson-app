import SwiftUI
import SwiftData
import AVKit
import TennisCore

struct ReportView: View {
    @Bindable var lesson: Lesson
    @Environment(\.modelContext) private var modelContext

    @State private var report: Report?
    @State private var decodeError: String?
    @State private var player: AVPlayer?
    @State private var cardImage: Image?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let videoURL = LessonVideoStorage.resolve(relativePath: lesson.localVideoRef) {
                    VideoPlayer(player: player)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onAppear {
                            if player == nil { player = AVPlayer(url: videoURL) }
                        }
                }

                if let report {
                    reportBody(report)
                } else if let decodeError {
                    Text("리포트를 읽을 수 없습니다: \(decodeError)")
                        .foregroundStyle(.red)
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .navigationTitle(lesson.videoTitle ?? "레슨 리포트")
        .toolbar {
            if let report {
                ToolbarItem {
                    Menu {
                        ShareLink("텍스트로 공유", item: shareText(report))
                        if let cardImage {
                            ShareLink(
                                "카드 이미지로 공유",
                                item: cardImage,
                                preview: SharePreview("오늘의 테니스 리포트", image: cardImage)
                            )
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task { decodeReport() }
        .onDisappear(perform: saveLesson)
    }

    @ViewBuilder
    private func reportBody(_ report: Report) -> some View {
        if report.transcriptQuality == "low" {
            Label("인용 신뢰도 낮음 — 참고용으로만 보세요", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        cardSection(title: "고질병", icon: "exclamationmark.circle.fill", tint: .red, text: report.card1Problem, evidence: report.card1Evidence)
        cardSection(title: "코치 큐잉", icon: "quote.bubble.fill", tint: .blue, text: report.card2Cueing, evidence: report.card2Evidence)
        cardSection(title: "다음 액션", icon: "arrow.forward.circle.fill", tint: .green, text: report.card3Action, evidence: report.card3Evidence)

        if let summary = report.fullSummary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("전체 요약").font(.headline)
                Text(summary).font(.subheadline)
            }
        }

        if !report.timestamps.isEmpty {
            timelineSection(report.timestamps)
        }

        if !report.aiContext.isEmpty {
            aiContextSection(report.aiContext)
        }

        if !report.keywords.isEmpty {
            keywordsSection(report.keywords)
        }

        myNoteSection()
    }

    /// 13문서 대체카드 — 별점 대신 즉석 👍/👎 반응 + 짧은 메모만 남긴다.
    @ViewBuilder
    private func myNoteSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("내 메모").font(.headline)
            HStack(spacing: 12) {
                reactionButton(symbol: "hand.thumbsup.fill", value: "up")
                reactionButton(symbol: "hand.thumbsdown.fill", value: "down")
            }
            TextField("이 레슨 리포트, 어땠나요?", text: noteBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .onSubmit(saveLesson)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func reactionButton(symbol: String, value: String) -> some View {
        let isSelected = lesson.userReaction == value
        return Button {
            lesson.userReaction = isSelected ? nil : value
            saveLesson()
        } label: {
            Image(systemName: symbol)
                .padding(10)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.15))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { lesson.userNote ?? "" },
            set: { lesson.userNote = $0.isEmpty ? nil : $0 }
        )
    }

    private func saveLesson() {
        try? modelContext.save()
    }

    @ViewBuilder
    private func cardSection(title: String, icon: String, tint: Color, text: String?, evidence: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(text)
                    .font(.body)
                if let evidence, !evidence.isEmpty {
                    Text("“\(evidence)”")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func timelineSection(_ items: [Report.TimestampItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("타임라인").font(.headline)
            ForEach(items) { item in
                Button {
                    seek(toSec: item.sec)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(timeString(item.sec))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).font(.subheadline.bold())
                            if let quote = item.quote, !quote.isEmpty {
                                Text("“\(quote)”")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    @ViewBuilder
    private func aiContextSection(_ items: [Report.AiContextItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI 보조 설명", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.purple)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.subheadline.bold())
                    Text(item.note).font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func keywordsSection(_ keywords: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("키워드").font(.headline)
            HStack {
                ForEach(keywords, id: \.self) { kw in
                    Text(kw)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func seek(toSec sec: Int) {
        player?.seek(to: CMTime(seconds: Double(sec), preferredTimescale: 600))
        player?.play()
    }

    private func decodeReport() {
        guard let json = lesson.reportJSON else {
            decodeError = "리포트 데이터가 없습니다"
            return
        }
        do {
            let decoded = try Report.decode(fromJSON: json)
            report = decoded
            renderCardImage(decoded)
        } catch {
            decodeError = String(describing: error)
        }
    }

    /// ShareLink용 카드 이미지 — 3단 카드를 오프스크린 뷰로 그려 PNG로 렌더링한다.
    @MainActor
    private func renderCardImage(_ report: Report) {
        let card = SummaryCardView(title: lesson.videoTitle ?? "오늘의 테니스", report: report)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        #if os(iOS)
        guard let uiImage = renderer.uiImage else { return }
        cardImage = Image(uiImage: uiImage)
        #else
        guard let nsImage = renderer.nsImage else { return }
        cardImage = Image(nsImage: nsImage)
        #endif
    }

    private func shareText(_ report: Report) -> String {
        var lines: [String] = []
        if let title = lesson.videoTitle { lines.append("🎾 \(title)") }
        if let p = report.card1Problem { lines.append("\n[고질병]\n\(p)") }
        if let c = report.card2Cueing { lines.append("\n[코치 큐잉]\n\(c)") }
        if let a = report.card3Action { lines.append("\n[다음 액션]\n\(a)") }
        lines.append("\n— 오늘의 테니스")
        return lines.joined(separator: "\n")
    }

    private func timeString(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

/// 공유용 카드 이미지 — ReportView 화면과 별개로, ImageRenderer가 오프스크린에서
/// 그리는 고정 폭 레이아웃(스크롤 없이 전체가 한 번에 들어가야 함).
private struct SummaryCardView: View {
    let title: String
    let report: Report

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("🎾 \(title)")
                .font(.title3.bold())

            cardBlock(label: "고질병", tint: .red, text: report.card1Problem)
            cardBlock(label: "코치 큐잉", tint: .blue, text: report.card2Cueing)
            cardBlock(label: "다음 액션", tint: .green, text: report.card3Action)

            Text("오늘의 테니스")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
        .background(cardBackground)
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    @ViewBuilder
    private func cardBlock(label: String, tint: Color, text: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.headline).foregroundStyle(tint)
                Text(text).font(.body)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
