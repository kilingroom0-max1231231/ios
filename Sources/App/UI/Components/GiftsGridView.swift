import SwiftUI

struct GiftsGridView: View {
    @Environment(\.colorScheme) private var colorScheme

    let gifts: [TgGiftItem]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private var cellBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(gifts) { gift in
                GiftGridCell(gift: gift, cellBackground: cellBackground)
            }
        }
    }
}

private struct GiftGridCell: View {
    let gift: TgGiftItem
    let cellBackground: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                stickerView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 8)
                    .padding(.horizontal, 4)

                if hasSender {
                    senderOverlay
                        .padding(4)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(gift.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
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

    @ViewBuilder
    private var stickerView: some View {
        if let path = gift.stickerPath, let image = LocalImageCache.shared.image(path: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(6)
        } else {
            Image(systemName: "gift.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accent, AppColors.accent.opacity(0.65), .pink.opacity(0.85)],
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
                    .stroke(cellBackground, lineWidth: 2)
            )

            if gift.senderIsPremium {
                PremiumBadgeView(imagePath: gift.senderPremiumBadgePath, size: 11)
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 32, height: 32, alignment: .topLeading)
    }
}
