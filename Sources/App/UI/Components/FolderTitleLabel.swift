import SwiftUI

struct FolderTitleLabel: View {
    let segments: [TextSegment]
    var font: Font = .subheadline.weight(.semibold)
    var lineLimit: Int = 1

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment.content {
                case .text(let value):
                    Text(value)
                        .font(font)
                case .customEmoji(_, let path):
                    if let path, !path.isEmpty {
                        StickerMediaView(
                            displayPath: path,
                            animationPath: path,
                            isAnimated: path.lowercased().hasSuffix(".tgs") || path.lowercased().hasSuffix(".webm"),
                            playbackMode: .staticPreview,
                            maxSide: 18
                        )
                        .frame(width: 18, height: 18)
                    } else {
                        Text("✨")
                            .font(font)
                    }
                }
            }
        }
        .lineLimit(lineLimit)
    }
}

struct FolderIconView: View {
    let emoji: String?
    let customEmojiPath: String?
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let customEmojiPath, !customEmojiPath.isEmpty {
                StickerMediaView(
                    displayPath: customEmojiPath,
                    animationPath: customEmojiPath,
                    isAnimated: customEmojiPath.lowercased().hasSuffix(".tgs") || customEmojiPath.lowercased().hasSuffix(".webm"),
                    playbackMode: .staticPreview,
                    maxSide: size
                )
            } else if let emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: size * 0.85))
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(AppColors.accent)
            }
        }
        .frame(width: size, height: size)
    }
}
