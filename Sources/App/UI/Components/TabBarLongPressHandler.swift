import SwiftUI
import UIKit

extension Notification.Name {
    static let openTabBarCustomization = Notification.Name("openTabBarCustomization")
}

@MainActor
final class TabBarLongPressInstaller: NSObject {
    static let shared = TabBarLongPressInstaller()

    private weak var tabBar: UITabBar?
    private var recognizers: [UILongPressGestureRecognizer] = []
    private var retryTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    func refresh() {
        retryTask?.cancel()
        retryTask = Task { @MainActor in
            for _ in 0..<24 {
                if Task.isCancelled { return }
                if installIfPossible() { return }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    @discardableResult
    private func installIfPossible() -> Bool {
        guard let tabBar = locateTabBar() else { return false }
        if self.tabBar === tabBar, !recognizers.isEmpty { return true }

        clearRecognizers()

        let targets = gestureTargets(for: tabBar)
        for view in targets {
            let longPress = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleLongPress(_:))
            )
            longPress.minimumPressDuration = 0.5
            longPress.cancelsTouchesInView = false
            longPress.delaysTouchesBegan = false
            longPress.delegate = self
            view.addGestureRecognizer(longPress)
            recognizers.append(longPress)
        }

        self.tabBar = tabBar
        return true
    }

    private func gestureTargets(for tabBar: UITabBar) -> [UIView] {
        var views: [UIView] = []
        func collect(from view: UIView) {
            views.append(view)
            for subview in view.subviews {
                collect(from: subview)
            }
        }
        collect(from: tabBar)
        return views
    }

    private func clearRecognizers() {
        for recognizer in recognizers {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
        recognizers.removeAll()
        tabBar = nil
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        NotificationCenter.default.post(name: .openTabBarCustomization, object: nil)
    }

    private func locateTabBar() -> UITabBar? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !window.isHidden {
                if let tabBar = findTabBar(in: window), isVisibleTabBar(tabBar) {
                    return tabBar
                }
            }
        }
        return nil
    }

    private func isVisibleTabBar(_ tabBar: UITabBar) -> Bool {
        !tabBar.isHidden && tabBar.alpha > 0.01 && tabBar.bounds.height > 20
    }

    private func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar, isVisibleTabBar(tabBar) {
            return tabBar
        }
        for subview in view.subviews {
            if let tabBar = findTabBar(in: subview) {
                return tabBar
            }
        }
        return nil
    }
}

extension TabBarLongPressInstaller: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        true
    }
}

private struct TabBarLongPressLifecycleModifier: ViewModifier {
    let refreshToken: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                TabBarLongPressInstaller.shared.refresh()
            }
            .onChange(of: refreshToken) { _ in
                TabBarLongPressInstaller.shared.refresh()
            }
    }
}

extension View {
    func tabBarLongPressLifecycle(refreshToken: String) -> some View {
        modifier(TabBarLongPressLifecycleModifier(refreshToken: refreshToken))
    }
}
