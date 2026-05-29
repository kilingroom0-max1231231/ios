import AVKit
import SwiftUI

/// Shows a sticker or gift: static preview, WebM loop, or loading placeholder.
struct StickerMediaView: View {
    let displayPath: String?
    let animationPath: String?
    var isAnimated: Bool = false

    private var animationURL: URL? {
        guard let animationPath, !animationPath.isEmpty,
              FileManager.default.fileExists(atPath: animationPath) else { return nil }
        return URL(fileURLWithPath: animationPath)
    }

    var body: some View {
        Group {
            if isAnimated, let animationURL {
                LoopingVideoStickerView(url: animationURL)
            } else {
                CachedLocalImage(path: displayPath, contentMode: .fit) {
                    loadingPlaceholder
                }
            }
        }
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
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            if let player {
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
            stopLoop()
            startLoop()
        }
    }

    private func startLoop() {
        guard let url else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        queue.play()
    }

    private func stopLoop() {
        player?.pause()
        player = nil
        looper = nil
    }
}
