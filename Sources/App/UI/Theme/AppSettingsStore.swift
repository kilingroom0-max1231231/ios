import Foundation
import SwiftUI

@MainActor
final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()

    @Published var showProfileChatKind: Bool {
        didSet { persist() }
    }

    @Published var showProfileChatId: Bool {
        didSet { persist() }
    }

    @Published var showProfileUserId: Bool {
        didSet { persist() }
    }

    @Published var keepDeletedMessages: Bool {
        didSet { persist() }
    }

    private enum Key {
        static let showProfileChatKind = "app.settings.showProfileChatKind"
        static let showProfileChatId = "app.settings.showProfileChatId"
        static let showProfileUserId = "app.settings.showProfileUserId"
        static let keepDeletedMessages = "app.settings.keepDeletedMessages"
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Key.showProfileChatKind) == nil {
            showProfileChatKind = true
        } else {
            showProfileChatKind = defaults.bool(forKey: Key.showProfileChatKind)
        }
        showProfileChatId = defaults.object(forKey: Key.showProfileChatId) == nil
            ? false
            : defaults.bool(forKey: Key.showProfileChatId)
        showProfileUserId = defaults.object(forKey: Key.showProfileUserId) == nil
            ? false
            : defaults.bool(forKey: Key.showProfileUserId)
        keepDeletedMessages = defaults.object(forKey: Key.keepDeletedMessages) == nil
            ? true
            : defaults.bool(forKey: Key.keepDeletedMessages)
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(showProfileChatKind, forKey: Key.showProfileChatKind)
        defaults.set(showProfileChatId, forKey: Key.showProfileChatId)
        defaults.set(showProfileUserId, forKey: Key.showProfileUserId)
        defaults.set(keepDeletedMessages, forKey: Key.keepDeletedMessages)
    }

    nonisolated static var keepDeletedMessagesValue: Bool {
        UserDefaults.standard.object(forKey: Key.keepDeletedMessages) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Key.keepDeletedMessages)
    }
}
