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

    @Published var syncContactsOnLaunch: Bool {
        didSet { persist() }
    }

    @Published var didPromptContactsPermission: Bool {
        didSet { persist() }
    }

    @Published var enableInAppSounds: Bool {
        didSet { persist() }
    }

    @Published var enableIncomingBanners: Bool {
        didSet { persist() }
    }

    @Published var showMessageTimestamps: Bool {
        didSet { persist() }
    }

    private enum Key {
        static let showProfileChatKind = "app.settings.showProfileChatKind"
        static let showProfileChatId = "app.settings.showProfileChatId"
        static let showProfileUserId = "app.settings.showProfileUserId"
        static let keepDeletedMessages = "app.settings.keepDeletedMessages"
        static let syncContactsOnLaunch = "app.settings.syncContactsOnLaunch"
        static let didPromptContactsPermission = "app.settings.didPromptContactsPermission"
        static let enableInAppSounds = "app.settings.enableInAppSounds"
        static let enableIncomingBanners = "app.settings.enableIncomingBanners"
        static let showMessageTimestamps = "app.settings.showMessageTimestamps"
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
        syncContactsOnLaunch = defaults.object(forKey: Key.syncContactsOnLaunch) == nil
            ? true
            : defaults.bool(forKey: Key.syncContactsOnLaunch)
        didPromptContactsPermission = defaults.bool(forKey: Key.didPromptContactsPermission)
        enableInAppSounds = defaults.object(forKey: Key.enableInAppSounds) == nil
            ? true
            : defaults.bool(forKey: Key.enableInAppSounds)
        enableIncomingBanners = defaults.object(forKey: Key.enableIncomingBanners) == nil
            ? true
            : defaults.bool(forKey: Key.enableIncomingBanners)
        showMessageTimestamps = defaults.object(forKey: Key.showMessageTimestamps) == nil
            ? true
            : defaults.bool(forKey: Key.showMessageTimestamps)
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(showProfileChatKind, forKey: Key.showProfileChatKind)
        defaults.set(showProfileChatId, forKey: Key.showProfileChatId)
        defaults.set(showProfileUserId, forKey: Key.showProfileUserId)
        defaults.set(keepDeletedMessages, forKey: Key.keepDeletedMessages)
        defaults.set(syncContactsOnLaunch, forKey: Key.syncContactsOnLaunch)
        defaults.set(didPromptContactsPermission, forKey: Key.didPromptContactsPermission)
        defaults.set(enableInAppSounds, forKey: Key.enableInAppSounds)
        defaults.set(enableIncomingBanners, forKey: Key.enableIncomingBanners)
        defaults.set(showMessageTimestamps, forKey: Key.showMessageTimestamps)
    }

    nonisolated static var keepDeletedMessagesValue: Bool {
        UserDefaults.standard.object(forKey: Key.keepDeletedMessages) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Key.keepDeletedMessages)
    }
}
