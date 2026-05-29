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

    private override init() {
        super.init()
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            lastRegistrationError = error.localizedDescription
            return false
        }
    }

    func setDeviceToken(_ token: Data) {
        deviceTokenHex = token.map { String(format: "%02x", $0) }.joined()
        pendingToken = token
    }

    func registerDeviceIfNeeded(repository: TelegramRepository?) async {
        guard AppSettingsStore.shared.enablePushNotifications else { return }
        guard let repository else { return }
        guard let token = pendingToken ?? deviceTokenHex.flatMap(hexData) else { return }

        do {
            try await repository.registerPushDevice(token: token, sandbox: isSandbox)
            lastRegistrationError = nil
        } catch {
            lastRegistrationError = error.localizedDescription
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
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushNotificationDelegate.shared
        if UserDefaults.standard.object(forKey: "app.settings.enablePushNotifications") == nil
            || UserDefaults.standard.bool(forKey: "app.settings.enablePushNotifications") {
            application.registerForRemoteNotifications()
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
            PushNotificationService.shared.reportRegistrationError(error.localizedDescription)
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
