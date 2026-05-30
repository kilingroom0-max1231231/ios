import SwiftUI

struct PremiumBadgeView: View {
    var imagePath: String?
    var size: CGFloat = 14
    var onTap: (() -> Void)?

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    badgeContent
                }
                .buttonStyle(.plain)
            } else {
                badgeContent
            }
        }
        .accessibilityLabel(AppText.tr("Telegram Premium", "Telegram Premium"))
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }

    @ViewBuilder
    private var badgeContent: some View {
        if let imagePath, !imagePath.isEmpty, hasStickerMedia {
            StickerMediaView(
                displayPath: imagePath,
                animationPath: animatedStickerPath,
                isAnimated: animatedStickerPath != nil,
                playbackMode: .animated,
                maxSide: size * 1.35
            )
            .frame(width: size, height: size)
        } else if let imagePath,
                  let image = LocalImageCache.shared.image(path: imagePath, maxPixelSize: size * 3) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            defaultStar
        }
    }

    private var hasStickerMedia: Bool {
        guard let imagePath, !imagePath.isEmpty else { return false }
        return TGSFileLoader.isTGSPath(imagePath)
            || StickerMediaView.isPlayableVideoPath(imagePath)
            || StickerMediaView.isRasterImagePath(imagePath)
    }

    private var animatedStickerPath: String? {
        guard let imagePath, !imagePath.isEmpty else { return nil }
        if TGSFileLoader.isTGSPath(imagePath) || StickerMediaView.isPlayableVideoPath(imagePath) {
            return imagePath
        }
        return nil
    }

    private var defaultStar: some View {
        Image(systemName: "star.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.45, green: 0.78, blue: 1.0),
                        Color(red: 0.55, green: 0.45, blue: 0.98),
                        Color(red: 0.95, green: 0.55, blue: 0.75)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

/// @username line without premium badge (badge is on display name).
struct UsernameLine: View {
    let username: String
    var font: Font = .caption
    var color: Color = AppColors.accent
    var vm: AppViewModel? = nil
    var onNavigate: (() -> Void)? = nil

    private var isInteractive: Bool { vm != nil }

    var body: some View {
        Group {
            if isInteractive {
                Button(action: openUsername) {
                    label
                }
                .buttonStyle(TappableLinkButtonStyle())
            } else {
                label
            }
        }
    }

    private var label: some View {
        Text("@\(username)")
            .font(font)
            .foregroundStyle(color)
            .underline(isInteractive, color: color.opacity(0.5))
            .lineLimit(1)
    }

    private func openUsername() {
        onNavigate?()
        guard let vm, let url = URL(string: "https://t.me/\(username)") else { return }
        vm.handleInternalLink(url)
    }
}

struct DisplayNameWithPremium: View {
    let name: String
    let isPremium: Bool
    var badgeImagePath: String?
    var font: Font = .headline
    var lineLimit: Int = 1
    /// Premium emoji/status is shown next to the display name (Telegram-style).
    var showBadgeOnName: Bool = true
    var onPremiumBadgeTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(font)
                .lineLimit(lineLimit)
            if isPremium && showBadgeOnName {
                PremiumBadgeView(
                    imagePath: badgeImagePath,
                    size: fontSize,
                    onTap: onPremiumBadgeTap
                )
            }
        }
    }

    private var fontSize: CGFloat {
        switch font {
        case .title2, .title2.weight(.bold), .title:
            return 16
        case .headline, .headline.weight(.semibold):
            return 13
        case .subheadline, .subheadline.weight(.semibold):
            return 11
        default:
            return 12
        }
    }
}
