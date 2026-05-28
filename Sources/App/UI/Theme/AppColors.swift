import SwiftUI
import UIKit

enum AppColors {
    @MainActor static var accent: Color { AppAppearanceStore.shared.accentColor }

    @MainActor static func incomingBubble(_ scheme: ColorScheme) -> Color {
        AppAppearanceStore.shared.incomingBubble(colorScheme: scheme)
    }

    @MainActor static func outgoingBubble(_ scheme: ColorScheme) -> Color {
        AppAppearanceStore.shared.outgoingBubble(colorScheme: scheme)
    }

    @MainActor static func outgoingText(_ scheme: ColorScheme) -> Color {
        AppAppearanceStore.shared.outgoingText(colorScheme: scheme)
    }

    static let composerBackground = Color(UIColor.secondarySystemBackground)
}
