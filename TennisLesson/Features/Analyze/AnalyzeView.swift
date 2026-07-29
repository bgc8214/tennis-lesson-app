import SwiftUI
import SwiftData
import TennisCore
import UniformTypeIdentifiers
import PhotosUI
#if os(iOS)
import UIKit
#endif

enum AnalyzePhase: Equatable {
    case queued
    case idle
    case importingFromPhotos
    case downloadingYouTube
    case extractingAudio
    /// (단계 메시지, 진행률 0~1 또는 nil=불확정). STT 단계만 실측 진행률을 가진다.
    case running(String, Double?)
    case done
    case failed(String)
}

/// 분석 시작 바텀시트 — 목업 디자인(사진첩 / 파일 / YouTube URL + 분석 중 스피너).
struct AnalyzeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var tracker = AnalysisTracker.shared
    @State private var showImporter = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var youtubeURLText: String = ""
    @State private var urlFieldOpen = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(DS.fillStrong).frame(width: 36, height: 5).padding(.top, 10).padding(.bottom, 14)
            pickerView
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .presentationDetents([.height(urlFieldOpen ? 380 : 320)])
        .presentationDragIndicator(.hidden)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.movie, .audio, .video], allowsMultipleSelection: false, onCompletion: handleFile)
        .onChange(of: photoPickerItem, handlePhotoPick)
    }

    // MARK: 선택 화면
    private var pickerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("레슨 분석").font(.system(size: 18, weight: .bold)).foregroundStyle(DS.labelStrong)
                Spacer()
                if tracker.pendingCount > 0 {
                    Text("\(tracker.pendingCount)개 진행/대기 중")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.primary)
                }
            }
            .padding(.bottom, 10)

            #if os(iOS)
            PhotosPicker(selection: $photoPickerItem, matching: .videos, photoLibrary: .shared()) {
                OptionRow(iconBg: DS.primaryBg, tint: DS.primary, system: "photo.on.rectangle", title: "사진첩에서 레슨 영상 선택")
            }
            .buttonStyle(.plain)
            #endif

            Button { showImporter = true } label: {
                OptionRow(iconBg: DS.positiveBg, tint: DS.greenAccent, system: "doc.fill", title: "파일에서 선택")
            }
            .buttonStyle(.plain)

            Button {
                withAnimation { urlFieldOpen.toggle() }
            } label: {
                OptionRow(iconBg: DS.negativeBg, tint: DS.negative, system: "play.rectangle.fill", title: "YouTube URL로 분석")
            }
            .buttonStyle(.plain)

            if urlFieldOpen {
                #if os(iOS)
                // 시스템 붙여넣기 버튼 — 탭 자체가 사용자 허가라 "붙여넣기 허용" 모달이
                // 안 뜬다. 클립보드 내용에 따라 스스로 활성/비활성되므로 감지 게이트 없이
                // 항상 노출하는 게 오히려 일관적이다(감지 휴리스틱의 누락·타이밍 문제 제거).
                if youtubeURLText.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        if let s = strings.first(where: { YouTubeURL.videoID(from: $0) != nil }) ?? strings.first {
                            youtubeURLText = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .tint(DS.primary)
                    .buttonBorderShape(.capsule)
                    .padding(.top, 10)
                }
                #endif

                HStack(spacing: 8) {
                    TextField("https://youtube.com/watch?v=...", text: $youtubeURLText)
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12).frame(height: 42)
                        .background(DS.pageBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.lineNormal, lineWidth: 1))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    Button {
                        let text = youtubeURLText; youtubeURLText = ""
                        tracker.enqueueYouTube(urlString: text, modelContext: modelContext)
                        dismiss()
                    } label: {
                        Text("가져오기").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 42)
                            .background(DS.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(youtubeURLText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 10)
            }

            Button { dismiss() } label: {
                Text("닫기").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.labelAlternative)
                    .frame(maxWidth: .infinity).padding(.top, 16)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 핸들러 — 모두 큐에 넣고 시트를 닫는다(진행은 메인 화면 배너에 표시).
    private func handleFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                tracker.enqueueUpload(sourceURL: url, cleanUpSource: false, title: nil, modelContext: modelContext)
                dismiss()
            }
        case .failure(let error):
            ToastCenter.shared.show("파일 선택 실패: \(error.localizedDescription)")
        }
    }

    private func handlePhotoPick(_ old: PhotosPickerItem?, _ newItem: PhotosPickerItem?) {
        guard let newItem else { return }
        Task {
            do {
                guard let movie = try await newItem.loadTransferable(type: PickedMovie.self) else {
                    ToastCenter.shared.show("사진첩에서 영상을 불러오지 못했습니다")
                    return
                }
                tracker.enqueueUpload(sourceURL: movie.url, cleanUpSource: true, title: nil, modelContext: modelContext)
                dismiss()
            } catch {
                print("[AnalyzeSheet] 사진첩 로드 실패: \(error)")
                ToastCenter.shared.show("사진첩 로드 실패")
            }
            photoPickerItem = nil
        }
    }
}

/// 바텀시트의 옵션 한 줄(아이콘 + 제목).
private struct OptionRow: View {
    let iconBg: Color
    let tint: Color
    let system: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: system).font(.system(size: 16)).foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(iconBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.labelStrong)
            Spacer()
        }
        .padding(.vertical, 12).padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

/// PhotosPicker에서 고른 영상을 `Data`가 아니라 파일 그대로(FileRepresentation) 받는다.
/// 시스템이 임시 위치에 이미 받아둔 파일을 앱 tmp로 복사만 하므로 메모리에 전체
/// 바이트가 올라가지 않는다 — Capacitor 버전의 base64 브리지 signal 9 재발 방지와
/// 같은 원칙(21문서 0절).
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}
