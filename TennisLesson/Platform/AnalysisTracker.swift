import Foundation
import SwiftData
import TennisCore
import os
#if os(iOS)
import UIKit
import BackgroundTasks
#endif

/// 큐에 담긴 분석 작업 하나. 여러 개를 넣어도 트래커가 하나씩 순차 처리한다.
@Observable
@MainActor
final class AnalysisJob: Identifiable {
    enum Source {
        case upload(URL, cleanUp: Bool)
        case youtube(String)
    }

    let id = UUID()
    let source: Source
    var title: String
    var phase: AnalyzePhase = .queued
    var task: Task<Void, Never>?

    init(source: Source, title: String) {
        self.source = source
        self.title = title
    }
}

/// 분석 파이프라인을 앱 전역에서 **큐로** 관리한다. 여러 영상을 넣으면 줄 세워
/// 하나씩 처리하고, 진행/대기 목록을 화면에서 계속 볼 수 있다(화면 생명주기와 무관).
@Observable
@MainActor
final class AnalysisTracker {
    static let shared = AnalysisTracker()
    private init() {}

    nonisolated static let logger = Logger(subsystem: "com.bossback.tennislesson", category: "AnalysisTracker")

    /// 대기(.queued) + 실행 중 + 최근 실패 작업. UI가 이 목록을 그대로 보여준다.
    private(set) var jobs: [AnalysisJob] = []
    private var runningJobID: UUID?
    private var worker: Task<Void, Never>?
    private var modelContext: ModelContext?

    /// 현재 실행 중인 작업이 있는가(백그라운드 유지·배너 표시 판단).
    var isRunning: Bool { runningJobID != nil }
    /// 아직 처리 안 끝난(대기/실행) 작업 수.
    var pendingCount: Int { jobs.filter { $0.phase != .done && !$0.isFailed }.count }

    private var currentPhase: AnalyzePhase {
        jobs.first(where: { $0.id == runningJobID })?.phase ?? .idle
    }

    // MARK: - 큐 추가

    func enqueueUpload(sourceURL: URL, cleanUpSource: Bool, title: String?, modelContext: ModelContext) {
        self.modelContext = modelContext
        let job = AnalysisJob(
            source: .upload(sourceURL, cleanUp: cleanUpSource),
            title: title ?? sourceURL.deletingPathExtension().lastPathComponent
        )
        jobs.append(job)
        ToastCenter.shared.show(isRunning ? "분석 대기열에 추가했어요" : "분석을 시작했어요")
        startWorker()
    }

    func enqueueYouTube(urlString: String, modelContext: ModelContext) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.modelContext = modelContext
        let job = AnalysisJob(source: .youtube(trimmed), title: "YouTube 레슨")
        jobs.append(job)
        ToastCenter.shared.show(isRunning ? "분석 대기열에 추가했어요" : "분석을 시작했어요")
        startWorker()
    }

    /// 실패한 작업을 목록에서 지운다(X).
    func dismiss(_ job: AnalysisJob) {
        guard job.isFailed else { return }
        jobs.removeAll { $0.id == job.id }
    }

    /// 실패한 작업을 다시 큐에 넣는다.
    func retry(_ job: AnalysisJob) {
        guard job.isFailed else { return }
        job.phase = .queued
        startWorker()
    }

    /// 작업 취소(대기 중이면 그냥 제거, 실행 중이면 파이프라인 취소 후 제거).
    func cancel(_ job: AnalysisJob) {
        if job.id == runningJobID {
            job.task?.cancel()
        }
        jobs.removeAll { $0.id == job.id }
        ToastCenter.shared.show("분석을 취소했습니다.")
    }

    // MARK: - 워커(순차 처리)

    private func startWorker() {
        guard worker == nil else { return }
        #if os(iOS)
        requestBackgroundContinuation()
        #endif
        setIdleTimerDisabled(true)
        worker = Task { [weak self] in
            guard let self else { return }
            await self.drain()
            self.worker = nil
            self.setIdleTimerDisabled(false)
            #if os(iOS)
            self.finishBackgroundTask(success: true)
            #endif
        }
    }

    private func drain() async {
        while let job = jobs.first(where: { $0.phase == .queued }) {
            runningJobID = job.id
            let t = Task { [weak self] in
                guard let self else { return }
                await self.run(job)
            }
            job.task = t
            await t.value
            job.task = nil
            runningJobID = nil
            // 완료된 작업은 목록에서 제거(레슨 목록에 실제 레슨으로 나타남).
            // 실패한 작업은 사용자가 보고 재시도/삭제하도록 남긴다.
            if case .done = job.phase {
                jobs.removeAll { $0.id == job.id }
            } else if !job.isFailed {
                // 취소된 경우: run()이 상태를 안 바꾸고 빠졌고, cancel()이 이미 제거했으면
                // 여기서 할 일 없음. 혹시 남아있으면 제거.
                jobs.removeAll { $0.id == job.id }
            }
        }
    }

    private func run(_ job: AnalysisJob) async {
        switch job.source {
        case .youtube(let url):
            await runFromYouTube(job, urlString: url)
        case .upload(let url, let cleanUp):
            await runPipeline(job, sourceURL: url, cleanUpSource: cleanUp, sourceType: "upload", videoTitle: job.title)
        }
    }

    private func setPhase(_ phase: AnalyzePhase, for job: AnalysisJob) {
        job.phase = phase
        #if os(iOS)
        if job.id == runningJobID { updateBackgroundTaskProgress() }
        #endif
    }

    // MARK: - 파이프라인

    private func runFromYouTube(_ job: AnalysisJob, urlString: String) async {
        // A안: 폰이 영상을 받아 재생용으로 보관하고, 서버엔 오디오만 보낸다.
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: workDir) }
        do {
            setPhase(.downloadingYouTube, for: job)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let resolved = try await YouTubeDirectClient.resolve(urlString: urlString)
            job.title = resolved.title
            let downloaded = try await YouTubeDirectClient.download(resolved, to: workDir)
            await runPipeline(job, sourceURL: downloaded, cleanUpSource: false, sourceType: "youtube", videoTitle: resolved.title)
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            Self.logger.error("[FAIL] YouTube 경로 실패: \(String(describing: error), privacy: .public)")
            setPhase(.failed(String(describing: error)), for: job)
            AnalysisNotifier.notifyFailed(title: job.title)
        }
    }

    private func runPipeline(
        _ job: AnalysisJob,
        sourceURL: URL,
        cleanUpSource: Bool,
        sourceType: String,
        videoTitle: String?
    ) async {
        guard let modelContext else { return }
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            if cleanUpSource { try? FileManager.default.removeItem(at: sourceURL) }
        }

        let lessonID = UUID()
        var localVideoRef: String?
        do {
            setPhase(.extractingAudio, for: job)
            let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let audioURL = workDir.appendingPathComponent("audio.m4a")

            try await AudioExtractor.extractMono16k(from: sourceURL, to: audioURL)
            try Task.checkCancellation()

            localVideoRef = try? LessonVideoStorage.persist(sourceURL: sourceURL, lessonID: lessonID)

            let durationSec = Int((try? await AudioExtractor.duration(of: sourceURL)) ?? 0)
            let backend = BackendClient()
            let resolved = try await backend.analyzeUpload(
                audioURL: audioURL,
                durationSec: durationSec,
                title: videoTitle ?? sourceURL.deletingPathExtension().lastPathComponent
            ) { [weak self, weak job] message in
                Task { @MainActor in
                    guard let self, let job else { return }
                    self.setPhase(.running(message, nil), for: job)
                }
            }

            let lesson = Lesson(
                id: lessonID,
                sourceType: sourceType,
                videoTitle: resolved.title ?? videoTitle ?? sourceURL.deletingPathExtension().lastPathComponent,
                status: "DONE",
                reportJSON: resolved.reportJSON,
                localVideoRef: localVideoRef,
                lessonType: resolved.lessonType.isEmpty ? nil : resolved.lessonType.joined(separator: ","),
                durationSec: durationSec > 0 ? durationSec : nil
            )
            modelContext.insert(lesson)
            try modelContext.save()

            try? FileManager.default.removeItem(at: workDir)
            setPhase(.done, for: job)
            AnalysisNotifier.notifyDone(title: lesson.displayTitle)
        } catch {
            LessonVideoStorage.delete(relativePath: localVideoRef)
            if Task.isCancelled || error is CancellationError { return }
            Self.logger.error("[FAIL] 파이프라인 실패: \(String(describing: error), privacy: .public)")
            setPhase(.failed(String(describing: error)), for: job)
            AnalysisNotifier.notifyFailed(title: job.title)
        }
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }

    // MARK: - 백그라운드 지속(iOS 26 BGContinuedProcessingTask)

    #if os(iOS)
    // register()·submit()·Info.plist는 동일한 "구체적" 식별자를 써야 한다(와일드카드
    // 넘기면 크래시 — 2026-07-26 확인). 큐 전체를 하나의 백그라운드 작업으로 덮는다.
    nonisolated private static let bgTaskIdentifier = "com.bossback.tennislesson.analyze.session"
    private var bgTask: BGContinuedProcessingTask?
    nonisolated(unsafe) private static var bgRegistered = false

    /// **반드시 nonisolated여야 한다.** MainActor 격리면 launch handler 클로저도 MainActor로
    /// 추론돼, 시스템이 백그라운드 큐에서 호출할 때 격리 위반(SIGTRAP)으로 크래시한다.
    nonisolated func registerBackgroundTask() {
        guard !Self.bgRegistered else { return }
        Self.bgRegistered = true
        let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgTaskIdentifier, using: nil) { task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            nonisolated(unsafe) let sendableTask = continuedTask
            Task { @MainActor in AnalysisTracker.shared.attachBackgroundTask(sendableTask) }
        }
        Self.logger.notice("[BG] registerForTaskWithIdentifier returned \(ok, privacy: .public)")
    }

    private func requestBackgroundContinuation() {
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.bgTaskIdentifier,
            title: "레슨 분석 중",
            subtitle: "준비 중..."
        )
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.logger.error("[BG] submit failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func attachBackgroundTask(_ task: BGContinuedProcessingTask) {
        bgTask = task
        // expirationHandler는 "취소하라"가 아니다(포그라운드면 계속 돌 수 있음). 라이브
        // 액티비티 참조만 정리하고 파이프라인은 유지한다.
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.stopHeartbeat()
                self?.bgTask = nil
            }
        }
        startHeartbeat()
        updateBackgroundTaskProgress()
    }

    private func finishBackgroundTask(success: Bool) {
        stopHeartbeat()
        bgTask?.setTaskCompleted(success: success)
        bgTask = nil
    }

    /// 정체 구간(모델 로딩·다운로드)에서도 "멈춤"으로 만료되지 않게 진행률을 조금씩 전진.
    private var heartbeatTask: Task<Void, Never>?

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, let bg = self.bgTask else { break }
                let next = min(bg.progress.totalUnitCount - 1, bg.progress.completedUnitCount + 1)
                if next > bg.progress.completedUnitCount { bg.progress.completedUnitCount = next }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// 현재 실행 중 작업의 phase로 라이브 액티비티 진행률/자막을 갱신한다.
    /// 큐가 남았으면 자막에 "(N개 대기)"를 붙인다. 큐가 완전히 빌 때만 워커가 완료 처리.
    private func updateBackgroundTaskProgress() {
        guard let bgTask else { return }

        let waiting = jobs.filter { $0.phase == .queued }.count
        let waitSuffix = waiting > 0 ? " · \(waiting)개 대기" : ""

        let (fraction, subtitle): (Double, String) = {
            switch currentPhase {
            case .queued, .idle: return (0, "준비 중...")
            case .importingFromPhotos: return (0.05, "사진첩에서 불러오는 중...")
            case .downloadingYouTube: return (0.1, "YouTube에서 다운로드 중...")
            case .extractingAudio: return (0.15, "오디오 추출 중...")
            case .running(let message, let sttFraction):
                if let sttFraction {
                    return (0.15 + sttFraction * 0.7, "\(message) \(Int(sttFraction * 100))%")
                }
                return (0.9, message)
            case .done: return (1.0, "완료")
            case .failed(let message): return (1.0, "실패: \(message)")
            }
        }()

        bgTask.progress.totalUnitCount = 1000
        let target = Int64(fraction * 1000)
        if target > bgTask.progress.completedUnitCount {
            bgTask.progress.completedUnitCount = target
        }
        bgTask.updateTitle("레슨 분석 중", subtitle: subtitle + waitSuffix)
    }
    #endif
}

extension AnalyzePhase {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

extension AnalysisJob {
    var isFailed: Bool { phase.isFailed }
}
