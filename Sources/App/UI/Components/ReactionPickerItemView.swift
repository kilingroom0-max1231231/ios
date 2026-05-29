import SwiftUI

struct ReactionPickerItemView: View {
    let item: TgReactionPickerItem
    var compact: Bool = false

    private var side: CGFloat { compact ? 28 : 32 }

    var body: some View {
        Group {
            if let path = item.imagePath, !path.isEmpty {
                StickerMediaView(
                    displayPath: path,
                    animationPath: path,
                    isAnimated: path.lowercased().hasSuffix(".webm") || path.lowercased().hasSuffix(".tgs"),
                    playbackMode: .staticPreview,
                    maxSide: side
                )
            } else {
                Text(item.emoji)
                    .font(.system(size: compact ? 26 : 30))
            }
        }
        .frame(width: side, height: side)
    }
}
