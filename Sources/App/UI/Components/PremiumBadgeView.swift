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

/// @username line without premium badge (badge is on display name).
struct UsernameLine: View {
    let username: String
    var font: Font = .caption
    var color: Color = .secondary

    var body: some View {
        Text("@\(username)")
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
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
