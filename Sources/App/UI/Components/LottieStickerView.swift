import Lottie
import SwiftUI

struct LottieStickerView: View {
    let tgsPath: String

    var body: some View {
        LottieStickerRepresentable(tgsPath: tgsPath)
            .aspectRatio(contentMode: .fit)
    }
}

/// UIKit wrapper — stable across Lottie 4.x (SwiftUI `reloadAnimationTrigger` varies by minor version).
private struct LottieStickerRepresentable: UIViewRepresentable {
    let tgsPath: String

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.contentMode = .scaleAspectFit
        view.loopMode = .loop
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
