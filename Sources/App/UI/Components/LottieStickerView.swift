import Lottie
import SwiftUI

struct LottieStickerView: View {
    let tgsPath: String

    var body: some View {
        LottieView {
            guard let jsonPath = TGSFileLoader.cachedLottieJSONPath(forTGSPath: tgsPath) else { return nil }
            return LottieAnimation.filepath(jsonPath)
        } placeholder: {
            ProgressView()
                .tint(.secondary)
        }
        .playing(loopMode: .loop)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .reloadAnimationTrigger(tgsPath, showPlaceholder: true)
    }
}
