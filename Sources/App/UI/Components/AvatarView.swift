import SwiftUI
import UIKit

struct AvatarView: View {
    let title: String
    let identifier: Int64
    let imagePath: String?
    var size: CGFloat = 50
    var isSavedMessages: Bool = false

    @State private var avatarImage: UIImage?

    var body: some View {
        Group {
            if isSavedMessages {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.62, blue: 0.98), Color(red: 0.22, green: 0.48, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            } else if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(LinearGradient(colors: avatarGradientColors(identifier), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Text(avatarInitials(title))
                            .font(.system(size: size * 0.34, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
        .task(id: imagePath) {
            guard let imagePath, !imagePath.isEmpty else {
                avatarImage = nil
                return
            }
            let loaded = await Task.detached(priority: .utility) {
                LocalImageCache.shared.image(path: imagePath, maxPixelSize: max(size * 3, 96))
            }.value
            avatarImage = loaded
        }
    }

    private func avatarInitials(_ value: String) -> String {
        let chunks = value.split(separator: " ").prefix(2)
        let letters = chunks.compactMap { $0.first?.uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    private func avatarGradientColors(_ id: Int64) -> [Color] {
        switch abs(id) % 5 {
        case 0: return [Color(red: 0.37, green: 0.55, blue: 0.95), Color(red: 0.22, green: 0.77, blue: 0.89)]
        case 1: return [Color(red: 0.93, green: 0.56, blue: 0.37), Color(red: 0.95, green: 0.36, blue: 0.55)]
        case 2: return [Color(red: 0.33, green: 0.78, blue: 0.54), Color(red: 0.16, green: 0.58, blue: 0.89)]
        case 3: return [Color(red: 0.65, green: 0.49, blue: 0.95), Color(red: 0.37, green: 0.45, blue: 0.91)]
        default: return [Color(red: 0.95, green: 0.71, blue: 0.31), Color(red: 0.95, green: 0.47, blue: 0.31)]
        }
    }
}
