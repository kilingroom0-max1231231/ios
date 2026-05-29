import SwiftUI

struct GiftsGridView: View {
    @Environment(\.colorScheme) private var colorScheme

    let gifts: [TgGiftItem]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let stickerSide: CGFloat = 64

    private var cellBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(gifts) { gift in
                GiftGridCell(
                    gift: gift,
                    cellBackground: cellBackground,
                    stickerSide: stickerSide
                )
            }
        }
    }
}

private struct GiftGridCell: View {
    let gift: TgGiftItem
    let cellBackground: Color
    let stickerSide: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                stickerView
                    .frame(width: stickerSide, height: stickerSide)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                if hasSender {
                    senderOverlay
                        .padding(6)
                }
            }
            .frame(height: stickerSide + 14)

            Text(gift.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
        )
        .accessibilityLabel(gift.title)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var hasSender: Bool {
        gift.senderUserId != nil || gift.senderAvatarPath != nil || !(gift.senderName?.isEmpty ?? true)
    }

    private var stickerView: some View {
        StickerMediaView(
            displayPath: gift.stickerPath,
            animationPath: gift.animationPath,
            isAnimated: gift.isAnimated,
            maxSide: stickerSide
        )
    }

    private var senderOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarView(
                title: gift.senderName ?? "?",
                identifier: gift.senderUserId ?? 0,
                imagePath: gift.senderAvatarPath,
                size: 26
            )
            .overlay(
                Circle()
                    .stroke(cellBackground, lineWidth: 2)
            )

            if gift.senderIsPremium {
                PremiumBadgeView(imagePath: gift.senderPremiumBadgePath, size: 10)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 30, height: 30, alignment: .topLeading)
    }
}
