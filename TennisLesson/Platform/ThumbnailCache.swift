import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 레슨 목록 카드용 썸네일. 로컬 영상 파일에서 1초 지점 프레임을 뽑아 캐시한다
/// (서버 썸네일이 없는 업로드/YouTube 공용 경로 — AVFoundation만으로 온디바이스 처리).
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private init() {}

    private var cache: [UUID: Image] = [:]

    func thumbnail(for lessonID: UUID, videoURL: URL) async -> Image? {
        if let cached = cache[lessonID] { return cached }
        guard let image = await Self.generate(from: videoURL) else { return nil }
        cache[lessonID] = image
        return image
    }

    private static func generate(from url: URL) async -> Image? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        do {
            let result = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
            #if os(iOS)
            return Image(uiImage: UIImage(cgImage: result.image))
            #else
            return Image(nsImage: NSImage(cgImage: result.image, size: .zero))
            #endif
        } catch {
            return nil
        }
    }
}
