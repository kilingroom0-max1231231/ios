import SwiftUI
import UIKit

enum ChromeAppearance {
    static func configureTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    static func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().isTranslucent = true
    }
}

extension View {
    /// Chats / Search / Settings — inline title on a fully transparent bar.
    func mainTabNavigationBar(title: String) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .transparentNavigationBar()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
    }

    /// No bar background at all.
    func transparentNavigationBar() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Blur without opaque fill — glass over scrolling content, title stays on top.
    func glassNavigationBar() -> some View {
        toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    /// Same glass blur (open chat header).
    func frostedNavigationBar() -> some View {
        glassNavigationBar()
    }
}

struct FrostedBarBackground: View {
    var showsDivider = false

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Divider()
                }
            }
    }
}

struct ChatRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
