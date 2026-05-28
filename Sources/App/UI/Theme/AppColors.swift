import SwiftUI
import UIKit

enum AppColors {
    static let accent = Color(red: 0.16, green: 0.53, blue: 0.92)
    static let incomingBubble = Color(UIColor.secondarySystemBackground)
    static let outgoingBubble = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.20, green: 0.37, blue: 0.60, alpha: 1.0)
                : UIColor(red: 0.86, green: 0.95, blue: 1.0, alpha: 1.0)
        }
    )
    static let outgoingText = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? .white : .black
        }
    )
    static let chatBackground = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)
                : UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1.0)
        }
    )
    static let composerBackground = Color(UIColor.secondarySystemBackground)
    static let screenBackground = Color(.systemGroupedBackground)
}
