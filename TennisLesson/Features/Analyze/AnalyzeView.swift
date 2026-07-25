import SwiftUI
import SwiftData
import TennisCore
import UniformTypeIdentifiers
import PhotosUI
#if os(iOS)
import UIKit
#endif

enum AnalyzePhase: Equatable {
    case idle
    case importingFromPhotos
    case downloadingYouTube
    case extractingAudio
    case running(String)
    case done
    case failed(String)
}

struct AnalyzeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var phase: AnalyzePhase = .idle
    @State private var showImporter = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var savedLesson: Lesson?
    #if os(macOS)
    @State private var youtubeURLText: String = ""
    #endif

    var body: some View {
        VStack(spacing: 20) {
            switch phase {
            case .idle:
                #if os(iOS)
                PhotosPicker(
                    selection: $photoPickerItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label("사진첩에서 레슨 영상 선택", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                #endif

                Button("파일에서 선택") { showImporter = true }
                    .buttonStyle(.bordered)

                #if os(macOS)
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text("또는 YouTube URL (yt-dlp 필요, mac 전용 · 21문서 M5)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("https://youtube.com/watch?v=...", text: $youtubeURLText)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 280)
                        Button("가져오기") {
                            let text = youtubeURLText
                            youtubeURLText = ""
                            Task { await runFromYouTube(urlString: text) }
                        }
                        .disabled(youtubeURLText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                #endif
            case .importingFromPhotos:
                ProgressView("사진첩에서 불러오는 중...")
            case .downloadingYouTube:
                ProgressView("YouTube에서 다운로드 중...")
            case .extractingAudio:
                ProgressView("오디오 추출 중...")
            case .running(let message):
                ProgressView(message)
            case .done:
                ContentUnavailableView("분석 완료", systemImage: "checkmark.circle")
                Button("다시 분석") { phase = .idle }
            case .failed(let message):
                Text("실패: \(message)")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                Button("다시 시도") { phase = .idle }
            }
        }
        .padding()
        .navigationTitle("레슨 분석")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.movie, .audio, .video],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await runPipeline(sourceURL: url) }
                }
            case .failure(let error):
                phase = .failed(error.localizedDescription)
            }
        }
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                phase = .importingFromPhotos
                do {
                    // FileRepresentation/Transferable의 UTType 매칭이 사진첩 영상에서
                    // 불안정("given transferable item does not conform to" 크래시 실측)해서,
                    // 대신 원시 Data로 받아 직접 임시 파일에 쓴다 — 더 단순하고 확실한 경로.
                    guard let data = try await newItem.loadTransferable(type: Data.self) else {
                        phase = .failed("사진첩에서 영상을 불러오지 못했습니다")
                        return
                    }
                    let ext = newItem.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    try data.write(to: tempURL)
                    await runPipeline(sourceURL: tempURL, cleanUpSource: true)
                } catch {
                    print("[AnalyzeView] 사진첩 로드 실패: \(error)")
                    phase = .failed(String(describing: error))
                }
                photoPickerItem = nil
            }
        }
    }

    private func runPipeline(sourceURL: URL, cleanUpSource: Bool = false, sourceType: String = "upload") async {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        setIdleTimerDisabled(true)
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            if cleanUpSource { try? FileManager.default.removeItem(at: sourceURL) }
            setIdleTimerDisabled(false)
        }

        let lessonID = UUID()
        var localVideoRef: String?
        do {
            phase = .extractingAudio
            let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let audioURL = workDir.appendingPathComponent("audio.m4a")

            try await AudioExtractor.extractMono16k(from: sourceURL, to: audioURL)

            // 타임스탬프 점프 재생을 위해 원본 영상을 영구 보관(오디오는 임시 폴더에서만 사용).
            localVideoRef = try? LessonVideoStorage.persist(sourceURL: sourceURL, lessonID: lessonID)

            guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
                  apiKey != "placeholder", !apiKey.isEmpty else {
                phase = .failed("GEMINI_API_KEY가 설정되지 않았습니다 (Secrets.xcconfig 확인)")
                return
            }
            let modelName = (Bundle.main.object(forInfoDictionaryKey: "GEMINI_MODEL") as? String) ?? "gemini-2.0-flash"

            let sttEngine = WhisperKitSttEngine()
            let gemini = GeminiClient(apiKey: apiKey, model: modelName)
            let builder = ReportBuilder(sttEngine: sttEngine, gemini: gemini)

            let reportDict = try await builder.build(audioURL: audioURL, modelName: modelName) { message in
                Task { @MainActor in phase = .running(message) }
            }
            let reportJSON = try encodeReportJSON(reportDict)
            let report = try? Report.decode(fromJSON: reportJSON)

            let lesson = Lesson(
                id: lessonID,
                sourceType: sourceType,
                videoTitle: sourceURL.deletingPathExtension().lastPathComponent,
                status: "DONE",
                reportJSON: reportJSON,
                localVideoRef: localVideoRef,
                lessonType: report?.lessonType.joined(separator: ",")
            )
            modelContext.insert(lesson)
            try modelContext.save()
            savedLesson = lesson

            try? FileManager.default.removeItem(at: workDir)
            phase = .done
        } catch {
            print("[AnalyzeView] 파이프라인 실패: \(error)")
            LessonVideoStorage.delete(relativePath: localVideoRef)
            phase = .failed(String(describing: error))
        }
    }

    #if os(macOS)
    /// 21문서 M5 — YouTube는 iOS에서 보류(Python 임베드 리스크), macOS는 yt-dlp 외부
    /// 바이너리로 영상을 받아 기존 M2 파이프라인(runPipeline)을 그대로 재사용한다.
    /// 오디오 단독이 아니라 영상(가능하면 사전 병합된 단일 파일)을 받아야 ReportView의
    /// 타임스탬프 점프 재생이 유지된다.
    private func runFromYouTube(urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .downloadingYouTube

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let outputTemplate = workDir.appendingPathComponent("%(title)s.%(ext)s").path

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            var env = ProcessInfo.processInfo.environment
            // GUI 앱은 로그인 셸의 PATH를 상속받지 못해 Homebrew 경로를 직접 보강해야 한다.
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
            process.environment = env
            process.arguments = ["yt-dlp", "-f", "best[ext=mp4]/best", "--no-playlist", "-o", outputTemplate, trimmed]

            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errText = String(data: errData, encoding: .utf8) ?? "알 수 없는 오류"
                phase = .failed("yt-dlp 실패: \(errText.prefix(300))")
                return
            }

            let downloaded = try FileManager.default
                .contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)
                .first { !$0.lastPathComponent.hasPrefix(".") }
            guard let downloaded else {
                phase = .failed("다운로드된 파일을 찾을 수 없습니다")
                return
            }
            await runPipeline(sourceURL: downloaded, cleanUpSource: true, sourceType: "youtube")
        } catch {
            phase = .failed(String(describing: error))
        }
    }
    #endif

    /// 파이프라인 실행(수 분~수십 분) 중 화면이 잠들어 처리가 중단되지 않도록 방지.
    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }

    private func encodeReportJSON(_ report: [String: JSONValue]) throws -> String {
        let data = try JSONEncoder().encode(JSONValue.object(report))
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

#Preview {
    NavigationStack { AnalyzeView() }
        .modelContainer(for: Lesson.self, inMemory: true)
}
