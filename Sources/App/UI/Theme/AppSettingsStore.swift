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

    @Published var enablePushNotifications: Bool {
        didSet { persist() }
    }

    @Published var enableBackgroundSync: Bool {
        didSet { persist() }
    }

    @Published var enableBackgroundMediaPrefetch: Bool {
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
        static let enablePushNotifications = "app.settings.enablePushNotifications"
        static let enableBackgroundSync = "app.settings.enableBackgroundSync"
        static let enableBackgroundMediaPrefetch = "app.settings.enableBackgroundMediaPrefetch"
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
        enablePushNotifications = defaults.object(forKey: Key.enablePushNotifications) == nil
            ? true
            : defaults.bool(forKey: Key.enablePushNotifications)
        enableBackgroundSync = defaults.object(forKey: Key.enableBackgroundSync) == nil
            ? true
            : defaults.bool(forKey: Key.enableBackgroundSync)
        enableBackgroundMediaPrefetch = defaults.object(forKey: Key.enableBackgroundMediaPrefetch) == nil
            ? false
            : defaults.bool(forKey: Key.enableBackgroundMediaPrefetch)
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
        defaults.set(enablePushNotifications, forKey: Key.enablePushNotifications)
        defaults.set(enableBackgroundSync, forKey: Key.enableBackgroundSync)
        defaults.set(enableBackgroundMediaPrefetch, forKey: Key.enableBackgroundMediaPrefetch)
    }

    nonisolated static var keepDeletedMessagesValue: Bool {
        UserDefaults.standard.object(forKey: Key.keepDeletedMessages) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Key.keepDeletedMessages)
    }
}
