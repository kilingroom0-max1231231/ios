import Foundation
import SwiftUI

enum MessageSwipeAction: String, CaseIterable, Codable, Identifiable {
    case reply
    case forward
    case quote
    case pin
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reply: return AppText.tr("Ответить", "Reply")
        case .forward: return AppText.tr("Переслать", "Forward")
        case .quote: return AppText.tr("Цитата", "Quote")
        case .pin: return AppText.tr("Закрепить", "Pin")
        case .delete: return AppText.tr("Удалить", "Delete")
        }
    }

    var systemImage: String {
        switch self {
        case .reply: return "arrowshape.turn.up.left"
        case .forward: return "arrowshape.turn.up.right"
        case .quote: return "text.quote"
        case .pin: return "pin.fill"
        case .delete: return "trash"
        }
    }
}

@MainActor
final class MessageSwipeSettingsStore: ObservableObject {
    static let shared = MessageSwipeSettingsStore()

    @Published var orderedActions: [MessageSwipeAction] {
        didSet { persist() }
    }

    @Published var disabledActions: Set<MessageSwipeAction> {
        didSet { persist() }
    }

    var enabledOrderedActions: [MessageSwipeAction] {
        orderedActions.filter { !disabledActions.contains($0) }
    }

    private let orderKey = "messageSwipe.actionOrder"
    private let disabledKey = "messageSwipe.disabled"

    private init() {
        if let raw = UserDefaults.standard.stringArray(forKey: orderKey) {
            let decoded = raw.compactMap(MessageSwipeAction.init(rawValue:))
            orderedActions = decoded.isEmpty ? Self.defaultOrder : decoded
        } else {
            orderedActions = Self.defaultOrder
        }

        if let raw = UserDefaults.standard.stringArray(forKey: disabledKey) {
            disabledActions = Set(raw.compactMap(MessageSwipeAction.init(rawValue:)))
        } else {
            disabledActions = []
        }
    }

    func setEnabled(_ action: MessageSwipeAction, enabled: Bool) {
        if enabled {
            disabledActions.remove(action)
        } else {
            disabledActions.insert(action)
        }
    }

    func isEnabled(_ action: MessageSwipeAction) -> Bool {
        !disabledActions.contains(action)
    }

    func move(from source: IndexSet, to destination: Int) {
        orderedActions.move(fromOffsets: source, toOffset: destination)
    }

    func resetToDefaults() {
        orderedActions = Self.defaultOrder
        disabledActions = []
    }

    private static let defaultOrder: [MessageSwipeAction] = [
        .reply, .forward, .quote, .pin, .delete
    ]

    private func persist() {
        UserDefaults.standard.set(orderedActions.map(\.rawValue), forKey: orderKey)
        UserDefaults.standard.set(disabledActions.map(\.rawValue), forKey: disabledKey)
    }
}
