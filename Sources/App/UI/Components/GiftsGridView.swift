import SwiftUI

struct GiftsGridView: View {
    @Environment(\.colorScheme) private var colorScheme

    let gifts: [TgGiftItem]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let stickerSide: CGFloat = 64
    private let pageSize = 24

    @State private var visibleCount: Int

    init(gifts: [TgGiftItem]) {
        self.gifts = gifts
        _visibleCount = State(initialValue: min(24, gifts.count))
    }

    private var cellBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    private var displayedGifts: [TgGiftItem] {
        Array(gifts.prefix(visibleCount))
    }

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(displayedGifts) { gift in
                    GiftGridCell(
                        gift: gift,
                        cellBackground: cellBackground,
                        stickerSide: stickerSide
                    )
                }
            }

            if visibleCount < gifts.count {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        visibleCount = min(visibleCount + pageSize, gifts.count)
                    }
                } label: {
                    Text(AppText.tr(
                        "Показать ещё (\(gifts.count - visibleCount))",
                        "Show more (\(gifts.count - visibleCount))"
                    ))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(AppColors.accent)
            }
        }
        .onChange(of: gifts.count) { count in
            if visibleCount > count {
                visibleCount = count
            } else if visibleCount == 0 {
                visibleCount = min(pageSize, count)
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
            playbackMode: .staticPreview,
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
