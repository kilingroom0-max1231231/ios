import Foundation
import SwiftUI
import UIKit

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

    @Published var enableDoubleTapQuickReaction: Bool {
        didSet { persist() }
    }

    @Published var doubleTapQuickReactionEmoji: String {
        didSet { persist() }
    }

    @Published var enableLongPressMessagePanel: Bool {
        didSet { persist() }
    }

    @Published var enableTapOnReactionChips: Bool {
        didSet { persist() }
    }

    @Published var reactionHapticFeedback: Bool {
        didSet { persist() }
    }

    @Published var expandReactionPickerByDefault: Bool {
        didSet { persist() }
    }

    @Published var showChatFolderTabs: Bool {
        didSet { persist() }
    }

    @Published var confirmReactionRemove: Bool {
        didSet { persist() }
    }

    static let quickReactionEmojiOptions = [
        "👍", "❤️", "🔥", "🤣", "😍", "😮", "😢", "🎉", "🙏", "👏", "💯", "🤝", "⚡️", "🥰", "😡", "🤔"
    ]

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
        static let enableDoubleTapQuickReaction = "app.settings.enableDoubleTapQuickReaction"
        static let doubleTapQuickReactionEmoji = "app.settings.doubleTapQuickReactionEmoji"
        static let enableLongPressMessagePanel = "app.settings.enableLongPressMessagePanel"
        static let enableTapOnReactionChips = "app.settings.enableTapOnReactionChips"
        static let reactionHapticFeedback = "app.settings.reactionHapticFeedback"
        static let expandReactionPickerByDefault = "app.settings.expandReactionPickerByDefault"
        static let showChatFolderTabs = "app.settings.showChatFolderTabs"
        static let confirmReactionRemove = "app.settings.confirmReactionRemove"
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
        enableDoubleTapQuickReaction = defaults.object(forKey: Key.enableDoubleTapQuickReaction) == nil
            ? true
            : defaults.bool(forKey: Key.enableDoubleTapQuickReaction)
        doubleTapQuickReactionEmoji = defaults.string(forKey: Key.doubleTapQuickReactionEmoji) ?? "👍"
        enableLongPressMessagePanel = defaults.object(forKey: Key.enableLongPressMessagePanel) == nil
            ? true
            : defaults.bool(forKey: Key.enableLongPressMessagePanel)
        enableTapOnReactionChips = defaults.object(forKey: Key.enableTapOnReactionChips) == nil
            ? true
            : defaults.bool(forKey: Key.enableTapOnReactionChips)
        reactionHapticFeedback = defaults.object(forKey: Key.reactionHapticFeedback) == nil
            ? true
            : defaults.bool(forKey: Key.reactionHapticFeedback)
        expandReactionPickerByDefault = defaults.object(forKey: Key.expandReactionPickerByDefault) == nil
            ? false
            : defaults.bool(forKey: Key.expandReactionPickerByDefault)
        showChatFolderTabs = defaults.object(forKey: Key.showChatFolderTabs) == nil
            ? true
            : defaults.bool(forKey: Key.showChatFolderTabs)
        confirmReactionRemove = defaults.object(forKey: Key.confirmReactionRemove) == nil
            ? false
            : defaults.bool(forKey: Key.confirmReactionRemove)
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
        defaults.set(enableDoubleTapQuickReaction, forKey: Key.enableDoubleTapQuickReaction)
        defaults.set(doubleTapQuickReactionEmoji, forKey: Key.doubleTapQuickReactionEmoji)
        defaults.set(enableLongPressMessagePanel, forKey: Key.enableLongPressMessagePanel)
        defaults.set(enableTapOnReactionChips, forKey: Key.enableTapOnReactionChips)
        defaults.set(reactionHapticFeedback, forKey: Key.reactionHapticFeedback)
        defaults.set(expandReactionPickerByDefault, forKey: Key.expandReactionPickerByDefault)
        defaults.set(showChatFolderTabs, forKey: Key.showChatFolderTabs)
        defaults.set(confirmReactionRemove, forKey: Key.confirmReactionRemove)
    }

    func reactionHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard reactionHapticFeedback else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    nonisolated static var keepDeletedMessagesValue: Bool {
        UserDefaults.standard.object(forKey: Key.keepDeletedMessages) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Key.keepDeletedMessages)
    }
}
