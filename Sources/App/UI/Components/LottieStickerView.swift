import Lottie
import SwiftUI

struct LottieStickerView: View {
    let tgsPath: String
    var maxSide: CGFloat = 96
    var isPlaying: Bool = true

    var body: some View {
        LottieStickerRepresentable(tgsPath: tgsPath, isPlaying: isPlaying)
            .frame(width: maxSide, height: maxSide)
            .clipped()
    }
}

/// UIKit wrapper — stable across Lottie 4.x (SwiftUI `reloadAnimationTrigger` varies by minor version).
private struct LottieStickerRepresentable: UIViewRepresentable {
    let tgsPath: String
    let isPlaying: Bool

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.contentMode = .scaleAspectFit
        view.loopMode = .loop
        view.backgroundBehavior = .pauseAndRestore
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        applyAnimation(to: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        let pathChanged = context.coordinator.loadedPath != tgsPath
        let playChanged = context.coordinator.isPlaying != isPlaying
        if pathChanged || playChanged {
            applyAnimation(to: uiView, coordinator: context.coordinator)
        }
    }

    static func dismantleUIView(_ uiView: LottieAnimationView, coordinator: Coordinator) {
        uiView.stop()
        coordinator.loadedPath = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func applyAnimation(to view: LottieAnimationView, coordinator: Coordinator) {
        coordinator.loadedPath = tgsPath
        coordinator.isPlaying = isPlaying

        guard let animation = TGSFileLoader.cachedLottieAnimation(forTGSPath: tgsPath) else {
            view.stop()
            view.animation = nil
            return
        }
        view.animation = animation
        if isPlaying {
            view.play()
        } else {
            view.currentProgress = 0
            view.pause()
        }
    }

    final class Coordinator {
        var loadedPath: String?
        var isPlaying = true
    }
}
