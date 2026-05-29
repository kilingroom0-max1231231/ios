import Lottie
import SwiftUI

struct LottieStickerView: View {
    let tgsPath: String
    var maxSide: CGFloat = 96

    var body: some View {
        LottieStickerRepresentable(tgsPath: tgsPath)
            .frame(width: maxSide, height: maxSide)
            .clipped()
    }
}

/// UIKit wrapper — stable across Lottie 4.x (SwiftUI `reloadAnimationTrigger` varies by minor version).
private struct LottieStickerRepresentable: UIViewRepresentable {
    let tgsPath: String

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.contentMode = .scaleAspectFit
        view.loopMode = .loop
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        loadAnimation(into: view)
        context.coordinator.loadedPath = tgsPath
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        if context.coordinator.loadedPath != tgsPath {
            loadAnimation(into: uiView)
            context.coordinator.loadedPath = tgsPath
        }
    }

    static func dismantleUIView(_ uiView: LottieAnimationView, coordinator: Coordinator) {
        uiView.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func loadAnimation(into view: LottieAnimationView) {
        guard let jsonPath = TGSFileLoader.cachedLottieJSONPath(forTGSPath: tgsPath) else {
            view.stop()
            view.animation = nil
            return
        }
        view.animation = LottieAnimation.filepath(jsonPath)
        view.play()
    }

    final class Coordinator {
        var loadedPath: String?
    }
}
