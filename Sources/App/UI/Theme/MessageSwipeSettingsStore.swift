import Foundation
import SwiftUI

enum MessageSwipeAction: String, CaseIterable, Codable, Identifiable {
    case off
    case reply
    case forward
    case quote
    case pin
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return AppText.tr("Выключено", "Off")
        case .reply: return AppText.tr("Ответить", "Reply")
        case .forward: return AppText.tr("Переслать", "Forward")
        case .quote: return AppText.tr("Цитата", "Quote")
        case .pin: return AppText.tr("Закрепить", "Pin")
        case .delete: return AppText.tr("Удалить", "Delete")
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "hand.draw"
        case .reply: return "arrowshape.turn.up.left"
        case .forward: return "arrowshape.turn.up.right"
        case .quote: return "text.quote"
        case .pin: return "pin.fill"
        case .delete: return "trash"
        }
    }

    @MainActor var accentColor: Color {
        switch self {
        case .off: return .secondary
        case .reply: return AppColors.accent
        case .forward: return .orange
        case .quote: return .teal
        case .pin: return .indigo
        case .delete: return .red
        }
    }
}

@MainActor
final class MessageSwipeSettingsStore: ObservableObject {
    static let shared = MessageSwipeSettingsStore()

    @Published var primaryAction: MessageSwipeAction {
        didSet { persist() }
    }

    private static let primaryKey = "messageSwipe.primaryAction"
    private static let legacyOrderKey = "messageSwipe.actionOrder"
    private static let legacyDisabledKey = "messageSwipe.disabled"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.primaryKey),
           let action = MessageSwipeAction(rawValue: raw) {
            primaryAction = action
        } else {
            primaryAction = Self.migrateLegacyAction() ?? .reply
        }
    }

    func resetToDefaults() {
        primaryAction = .reply
    }

    private static func migrateLegacyAction() -> MessageSwipeAction? {
        guard let order = UserDefaults.standard.stringArray(forKey: Self.legacyOrderKey) else { return nil }
        let disabled = Set(
            (UserDefaults.standard.stringArray(forKey: Self.legacyDisabledKey) ?? [])
                .compactMap(MessageSwipeAction.init(rawValue:))
        )
        let enabled = order.compactMap(MessageSwipeAction.init(rawValue:)).filter { !disabled.contains($0) }
        return enabled.first
    }

    private func persist() {
        UserDefaults.standard.set(primaryAction.rawValue, forKey: Self.primaryKey)
    }
}
