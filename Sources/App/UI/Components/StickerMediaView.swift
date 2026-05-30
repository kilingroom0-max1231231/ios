import AVKit
import SwiftUI

enum StickerPlaybackMode {
  /// Lottie / video loops (use sparingly — one per screen area).
    case animated
    /// WebP/PNG thumbnail only — for dense grids.
    case staticPreview
}

/// Shows a sticker or gift: static preview, WebM loop, or loading placeholder.
struct StickerMediaView: View {
    let displayPath: String?
    let animationPath: String?
    var isAnimated: Bool = false
    var playbackMode: StickerPlaybackMode = .animated
    /// Caps Lottie/video layout so grid cells do not expand to full animation bounds.
    var maxSide: CGFloat? = nil

    private var animationURL: URL? {
        guard let animationPath, !animationPath.isEmpty,
              Self.isPlayableVideoPath(animationPath),
              FileManager.default.fileExists(atPath: animationPath) else { return nil }
        return URL(fileURLWithPath: animationPath)
    }

    private var tgsPath: String? {
        if TGSFileLoader.isTGSPath(animationPath) { return animationPath }
        if TGSFileLoader.isTGSPath(displayPath) { return displayPath }
        return nil
    }

    private var shouldPlayVideo: Bool {
        isAnimated && animationURL != nil
    }

    private var rasterDisplayPath: String? {
        if let displayPath, !displayPath.isEmpty, Self.isRasterImagePath(displayPath) {
            return displayPath
        }
        if let animationPath, !animationPath.isEmpty, Self.isRasterImagePath(animationPath) {
            return animationPath
        }
        return nil
    }

    var body: some View {
        Group {
            if playbackMode == .staticPreview {
                staticPreviewContent
            } else {
                animatedContent
            }
        }
        .frame(width: maxSide, height: maxSide)
        .clipped()
    }

    @ViewBuilder
    private var staticPreviewContent: some View {
        // Dense grids must stay cheap: prefer a raster thumbnail and only decode the
        // (expensive) TGS/Lottie when no static image is available.
        if let staticRasterPath {
            CachedLocalImage(path: staticRasterPath, contentMode: .fit) {
                tgsStaticFallback
            }
        } else {
            tgsStaticFallback
        }
    }

    @ViewBuilder
    private var tgsStaticFallback: some View {
        if let tgsPath {
            LottieStickerView(tgsPath: tgsPath, maxSide: maxSide ?? 96, isPlaying: false)
        } else {
            loadingPlaceholder
        }
    }

    @ViewBuilder
    private var animatedContent: some View {
        if let tgsPath {
            LottieStickerView(tgsPath: tgsPath, maxSide: maxSide ?? 96, isPlaying: true)
        } else if shouldPlayVideo, let animationURL {
            LoopingVideoStickerView(url: animationURL, fallbackPath: rasterDisplayPath)
                .frame(maxWidth: maxSide, maxHeight: maxSide)
        } else {
            CachedLocalImage(path: rasterDisplayPath, contentMode: .fit) {
                loadingPlaceholder
            }
        }
    }

    /// Thumbnail for grid cells — never decodes TGS here.
    private var staticRasterPath: String? {
        if let displayPath, !displayPath.isEmpty, Self.isRasterImagePath(displayPath) {
            return displayPath
        }
        if let animationPath, !animationPath.isEmpty, Self.isRasterImagePath(animationPath) {
            return animationPath
        }
        return nil
    }

    static func isPlayableVideoPath(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext == "webm" || ext == "mp4" || ext == "mov"
    }

    static func isRasterImagePath(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["webp", "png", "jpg", "jpeg", "gif", "heic"].contains(ext)
    }

    private var loadingPlaceholder: some View {
        ProgressView()
            .scaleEffect(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoopingVideoStickerView: View {
    let url: URL?
    var fallbackPath: String?
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var playbackFailed = false

    var body: some View {
        Group {
            if playbackFailed {
                CachedLocalImage(path: fallbackPath ?? url?.path, contentMode: .fit) {
                    ProgressView()
                        .scaleEffect(0.75)
                }
            } else if let player {
                VideoPlayer(player: player)
                    .disabled(true)
            } else {
                ProgressView()
                    .tint(.secondary)
            }
        }
        .onAppear { startLoop() }
        .onDisappear { stopLoop() }
        .onChange(of: url?.path) { _ in
            playbackFailed = false
            stopLoop()
            startLoop()
        }
    }

    private func startLoop() {
        guard let url, !playbackFailed else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        queue.play()
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                if queue.currentItem?.status == .failed {
                    playbackFailed = true
                    stopLoop()
                }
            }
        }
    }

    private func stopLoop() {
        player?.pause()
        player = nil
        looper = nil
    }
}
