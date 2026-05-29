import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceTokenHex: String?
    @Published private(set) var lastRegistrationError: String?

    func reportRegistrationError(_ message: String) {
        lastRegistrationError = message
    }

    private var pendingToken: Data?

    private static let remotePushBlockedKey = "push.remoteBlockedReason"

    private override init() {
        super.init()
    }

    var isRemotePushBlocked: Bool {
        guard let reason = UserDefaults.standard.string(forKey: Self.remotePushBlockedKey) else { return false }
        return !reason.isEmpty
    }

    func markRemotePushBlocked(_ reason: String) {
        UserDefaults.standard.set(reason, forKey: Self.remotePushBlockedKey)
        lastRegistrationError = reason
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if authorizationStatus == .denied {
            lastRegistrationError = Self.messageForDeniedAuthorization()
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            if granted {
                registerForRemoteNotificationsIfAllowed()
            } else {
                lastRegistrationError = Self.messageForDeniedAuthorization()
            }
            return granted
        } catch {
            lastRegistrationError = Self.humanReadablePushError(error)
            return false
        }
    }

    func registerForRemoteNotificationsIfAllowed() {
        if isRemotePushBlocked {
            lastRegistrationError = UserDefaults.standard.string(forKey: Self.remotePushBlockedKey)
            return
        }

        #if targetEnvironment(simulator)
        markRemotePushBlocked(Self.messageForSimulator())
        return
        #endif

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        case .denied:
            lastRegistrationError = Self.messageForDeniedAuthorization()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func setDeviceToken(_ token: Data) {
        deviceTokenHex = token.map { String(format: "%02x", $0) }.joined()
        pendingToken = token
        lastRegistrationError = nil
    }

    func registerDeviceIfNeeded(repository: TelegramRepository?) async {
        guard AppSettingsStore.shared.enablePushNotifications else { return }
        guard let repository else { return }
        guard let token = pendingToken ?? deviceTokenHex.flatMap(hexData) else { return }

        do {
            try await repository.registerPushDevice(token: token, sandbox: isSandbox)
            lastRegistrationError = nil
        } catch {
            lastRegistrationError = Self.humanReadablePushError(error)
        }
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        guard UserDefaults.standard.object(forKey: "app.settings.enableBackgroundSync") == nil
            || UserDefaults.standard.bool(forKey: "app.settings.enableBackgroundSync") else { return }
        _ = userInfo
        await AppDelegateHolder.viewModel?.handlePushNotification()
    }

    private var isSandbox: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private func hexData(_ hex: String) -> Data? {
        let chars = Array(hex)
        guard chars.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: chars.count / 2)
        var index = 0
        while index < chars.count {
            let byte = String(chars[index]) + String(chars[index + 1])
            guard let value = UInt8(byte, radix: 16) else { return nil }
            data.append(value)
            index += 2
        }
        return data
    }

    static func humanReadablePushError(_ error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == UNErrorDomain, nsError.code == 1 {
            return messageForFreeOrDeniedPush()
        }

        let description = nsError.localizedDescription.lowercased()
        if description.contains("personal development") || description.contains("free") {
            return messageForFreeDeveloperAccount()
        }
        if description.contains("aps-environment") || description.contains("entitlement") {
            return messageForFreeDeveloperAccount()
        }

        #if targetEnvironment(simulator)
        return messageForSimulator()
        #else
        return nsError.localizedDescription
        #endif
    }

    static func messageForDeniedAuthorization() -> String {
        AppText.tr(
            "Уведомления запрещены в iOS. Откройте Настройки → Уведомления → Telegram User Client и включите их.",
            "Notifications are disabled in iOS. Open Settings → Notifications → Telegram User Client and enable them."
        )
    }

    static func messageForFreeDeveloperAccount() -> String {
        AppText.tr(
            "Удалённые push недоступны с бесплатным Apple ID. Нужна платная подписка Apple Developer (99 USD/год) и Push в профиле подписи. Пока работают уведомления внутри приложения.",
            "Remote push is not available with a free Apple ID. You need a paid Apple Developer Program membership and Push in the signing profile. In-app alerts still work while the app is open."
        )
    }

    static func messageForFreeOrDeniedPush() -> String {
        AppText.tr(
            "Системные push сейчас недоступны (бесплатный Apple ID или запрет в Настройках iOS). Используйте баннеры в приложении.",
            "System push is unavailable (free Apple ID or disabled in iOS Settings). Use in-app banners instead."
        )
    }

    static func messageForSimulator() -> String {
        AppText.tr(
            "Push не поддерживается в симуляторе. Установите сборку на реальный iPhone.",
            "Push is not supported in the simulator. Install the build on a real iPhone."
        )
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushNotificationDelegate.shared
        Task { @MainActor in
            await PushNotificationService.shared.refreshAuthorizationStatus()
            let enabled = UserDefaults.standard.object(forKey: "app.settings.enablePushNotifications") == nil
                || UserDefaults.standard.bool(forKey: "app.settings.enablePushNotifications")
            if enabled {
                PushNotificationService.shared.registerForRemoteNotificationsIfAllowed()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.setDeviceToken(deviceToken)
            await AppDelegateHolder.viewModel?.registerPushTokenIfNeeded()
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            let message = PushNotificationService.humanReadablePushError(error)
            PushNotificationService.shared.markRemotePushBlocked(message)
        }
    }
}

private final class PushNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let enabled = UserDefaults.standard.object(forKey: "app.settings.enablePushNotifications") == nil
            || UserDefaults.standard.bool(forKey: "app.settings.enablePushNotifications")
        if enabled {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
