import SwiftUI
import UIKit

@MainActor
enum TabBarProfileIconRenderer {
    private static var cacheKey: String = ""
    private static var cachedImage: UIImage?

    static func tabImage(title: String, identifier: Int64, imagePath: String?) -> UIImage {
        let key = "\(identifier)|\(imagePath ?? "")|\(title)"
        if key == cacheKey, let cachedImage {
            return cachedImage
        }
        let rendered = render(title: title, identifier: identifier, imagePath: imagePath)
        cacheKey = key
        cachedImage = rendered
        return rendered
    }

    static func invalidate() {
        cacheKey = ""
        cachedImage = nil
    }

    private static func render(title: String, identifier: Int64, imagePath: String?) -> UIImage {
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            if let imagePath,
               !imagePath.isEmpty,
               let uiImage = LocalImageCache.shared.image(path: imagePath, maxPixelSize: 84) {
                UIBezierPath(ovalIn: rect).addClip()
                uiImage.draw(in: rect)
            } else {
                let colors = gradientColors(for: identifier)
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [colors.0.cgColor, colors.1.cgColor] as CFArray,
                    locations: [0, 1]
                )!
                let context = UIGraphicsGetCurrentContext()!
                context.saveGState()
                UIBezierPath(ovalIn: rect).addClip()
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
                context.restoreGState()

                let initials = avatarInitials(title)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
                let textSize = initials.size(withAttributes: attributes)
                let point = CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                )
                initials.draw(at: point, withAttributes: attributes)
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    private static func avatarInitials(_ value: String) -> String {
        let chunks = value.split(separator: " ").prefix(2)
        let letters = chunks.compactMap { $0.first?.uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    private static func gradientColors(for id: Int64) -> (UIColor, UIColor) {
        switch abs(id) % 5 {
        case 0: return (UIColor(red: 0.37, green: 0.55, blue: 0.95, alpha: 1), UIColor(red: 0.22, green: 0.77, blue: 0.89, alpha: 1))
        case 1: return (UIColor(red: 0.93, green: 0.56, blue: 0.37, alpha: 1), UIColor(red: 0.95, green: 0.36, blue: 0.55, alpha: 1))
        case 2: return (UIColor(red: 0.33, green: 0.78, blue: 0.54, alpha: 1), UIColor(red: 0.16, green: 0.58, blue: 0.89, alpha: 1))
        case 3: return (UIColor(red: 0.65, green: 0.49, blue: 0.95, alpha: 1), UIColor(red: 0.37, green: 0.45, blue: 0.91, alpha: 1))
        default: return (UIColor(red: 0.95, green: 0.71, blue: 0.31, alpha: 1), UIColor(red: 0.95, green: 0.47, blue: 0.31, alpha: 1))
        }
    }
}

@MainActor
final class TabBarSelectionAnimator {
    static let shared = TabBarSelectionAnimator()

    func animate(tab: MainTab, visibleTabs: [MainTab]) {
        guard let index = visibleTabs.firstIndex(of: tab),
              let tabBar = locateTabBar() else { return }

        let buttons = tabBar.subviews
            .flatMap { $0.subviews }
            .filter { String(describing: type(of: $0)).contains("UITabBarButton") }

        guard index < buttons.count else { return }
        let button = buttons[index]

        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut]) {
            button.transform = CGAffineTransform(scaleX: 1.14, y: 1.14)
        } completion: { _ in
            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                usingSpringWithDamping: 0.58,
                initialSpringVelocity: 0.9,
                options: [.allowUserInteraction]
            ) {
                button.transform = .identity
            }
        }
    }

    private func locateTabBar() -> UITabBar? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !window.isHidden {
                if let tabBar = findTabBar(in: window) {
                    return tabBar
                }
            }
        }
        return nil
    }

    private func findTabBar(in root: UIView) -> UITabBar? {
        if let tabBar = root as? UITabBar { return tabBar }
        for subview in root.subviews {
            if let found = findTabBar(in: subview) { return found }
        }
        return nil
    }
}

struct TabBarProfileTabIcon: View {
    let title: String
    let identifier: Int64
    let imagePath: String?

    var body: some View {
        Image(uiImage: TabBarProfileIconRenderer.tabImage(
            title: title,
            identifier: identifier,
            imagePath: imagePath
        ))
    }
}
