import Foundation
import AVFoundation

/// `stt_providers.py`의 `_reencode_for_upload`(P3) 포팅 — 단, 네트워크 업로드가
/// 아니라 온디바이스 STT 입력용이라 목적만 "크기 최소화"에서 "WhisperKit 입력
/// 규격(16kHz mono)"으로 바뀌었다. ffmpeg 서브프로세스 대신 AVFoundation
/// AVAssetReader/Writer로 스트리밍 변환 — 파일 전체를 메모리에 올리지 않는다
/// (base64 브리지 전달로 signal 9 크래시가 났던 Capacitor 버전의 실패를
/// 반복하지 않기 위한 핵심 설계 — 21문서 0절).
public enum AudioExtractor {
    public enum ExtractError: Error, CustomStringConvertible {
        case noAudioTrack
        case readerFailed(String)
        case writerFailed(String)

        public var description: String {
            switch self {
            case .noAudioTrack: return "오디오 트랙을 찾을 수 없습니다"
            case .readerFailed(let msg): return "오디오 읽기 실패: \(msg)"
            case .writerFailed(let msg): return "오디오 쓰기 실패: \(msg)"
            }
        }
    }

    /// 소스 미디어(영상 또는 오디오)에서 16kHz mono m4a(AAC)로 추출/재인코딩한다.
    public static func extractMono16k(from sourceURL: URL, to outputURL: URL) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else { throw ExtractError.noAudioTrack }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        guard reader.canAdd(readerOutput) else { throw ExtractError.readerFailed("트랙 출력을 추가할 수 없습니다") }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let writerInputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerInputSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw ExtractError.writerFailed("writer input을 추가할 수 없습니다") }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw ExtractError.readerFailed(reader.error?.localizedDescription ?? "알 수 없는 오류")
        }
        guard writer.startWriting() else {
            throw ExtractError.writerFailed(writer.error?.localizedDescription ?? "알 수 없는 오류")
        }
        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "audio-extract")
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sample = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sample)
                    } else {
                        writerInput.markAsFinished()
                        if reader.status == .failed {
                            continuation.resume(throwing: ExtractError.readerFailed(reader.error?.localizedDescription ?? "알 수 없는 오류"))
                            return
                        }
                        writer.finishWriting {
                            if writer.status == .failed {
                                continuation.resume(throwing: ExtractError.writerFailed(writer.error?.localizedDescription ?? "알 수 없는 오류"))
                            } else {
                                continuation.resume()
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    public static func duration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }
}
