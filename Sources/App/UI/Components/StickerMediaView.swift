import AVKit
import SwiftUI

/// Shows a sticker or gift: static preview, WebM loop, or loading placeholder.
struct StickerMediaView: View {
    let displayPath: String?
    let animationPath: String?
    var isAnimated: Bool = false

    private var animationURL: URL? {
        guard let animationPath, !animationPath.isEmpty,
              Self.isPlayableVideoPath(animationPath),
              FileManager.default.fileExists(atPath: animationPath) else { return nil }
        return URL(fileURLWithPath: animationPath)
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
            if shouldPlayVideo, let animationURL {
                LoopingVideoStickerView(url: animationURL, fallbackPath: rasterDisplayPath)
            } else {
                CachedLocalImage(path: rasterDisplayPath, contentMode: .fit) {
                    loadingPlaceholder
                }
            }
        }
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
        Image(systemName: "gift.fill")
            .font(.title)
            .foregroundStyle(
                LinearGradient(
                    colors: [AppColors.accent, .pink.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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
                    Image(systemName: "gift.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
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
