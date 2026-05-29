import SwiftUI

struct GiftsGridView: View {
    let gifts: [TgGiftItem]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(gifts) { gift in
                GiftGridCell(gift: gift)
            }
        }
    }
}

private struct GiftGridCell: View {
    let gift: TgGiftItem

    var body: some View {
        ZStack(alignment: .topLeading) {
            stickerView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 10)
                .padding(.horizontal, 4)

            if hasSender {
                senderOverlay
                    .padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(gift.title)
    }

    private var hasSender: Bool {
        gift.senderUserId != nil || gift.senderAvatarPath != nil || !(gift.senderName?.isEmpty ?? true)
    }

    @ViewBuilder
    private var stickerView: some View {
        if let path = gift.stickerPath, let image = LocalImageCache.shared.image(path: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "gift.fill")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.pink, Color.orange, Color.yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var senderOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarView(
                title: gift.senderName ?? "?",
                identifier: gift.senderUserId ?? 0,
                imagePath: gift.senderAvatarPath,
                size: 28
            )
            .overlay(
                Circle()
                    .stroke(Color.black, lineWidth: 2)
            )

            if gift.senderIsPremium {
                PremiumBadgeView(imagePath: gift.senderPremiumBadgePath, size: 11)
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 32, height: 32, alignment: .topLeading)
    }
}
