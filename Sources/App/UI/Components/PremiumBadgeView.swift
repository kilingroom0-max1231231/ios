import SwiftUI

struct PremiumBadgeView: View {
    var imagePath: String?
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let imagePath,
               let image = LocalImageCache.shared.image(path: imagePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                defaultStar
            }
        }
        .accessibilityLabel(AppText.tr("Telegram Premium", "Telegram Premium"))
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

/// Premium badge immediately after @username (nickname).
struct UsernameWithPremium: View {
    let username: String
    let isPremium: Bool
    var badgeImagePath: String?
    var font: Font = .caption
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            Text("@\(username)")
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
            if isPremium {
                PremiumBadgeView(imagePath: badgeImagePath, size: badgeSize)
            }
        }
    }

    private var badgeSize: CGFloat {
        font == .subheadline ? 12 : 11
    }
}

struct DisplayNameWithPremium: View {
    let name: String
    let isPremium: Bool
    var badgeImagePath: String?
    var font: Font = .headline
    var lineLimit: Int = 1
    /// When false, premium is shown only on the username line (Telegram-style).
    var showBadgeOnName: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(font)
                .lineLimit(lineLimit)
            if isPremium && showBadgeOnName {
                PremiumBadgeView(imagePath: badgeImagePath, size: fontSize)
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
