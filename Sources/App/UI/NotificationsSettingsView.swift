import SwiftUI
import UIKit

struct NotificationsSettingsView: View {
    @ObservedObject var appSettings: AppSettingsStore
    @ObservedObject private var pushService = PushNotificationService.shared

    var body: some View {
        List {
            Section {
                Toggle(isOn: $appSettings.enablePushNotifications) {
                    settingsLabel(
                        icon: "iphone.radiowaves.left.and.right",
                        title: AppText.tr("Push-уведомления", "Push notifications"),
                        subtitle: AppText.tr("Сообщения, когда приложение закрыто", "Messages when the app is closed")
                    )
                }
                .onChange(of: appSettings.enablePushNotifications) { enabled in
                    if enabled {
                        Task { await PushNotificationService.shared.requestAuthorization() }
                    }
                }

                pushStatusRow

                Toggle(isOn: $appSettings.enableBackgroundSync) {
                    settingsLabel(
                        icon: "arrow.clockwise.icloud",
                        title: AppText.tr("Синхронизация в фоне", "Background sync"),
                        subtitle: AppText.tr("Обновлять чаты при сворачивании", "Refresh chats when minimized")
                    )
                }

                Toggle(isOn: $appSettings.enableBackgroundMediaPrefetch) {
                    settingsLabel(
                        icon: "photo.on.rectangle.angled",
                        title: AppText.tr("Медиа в фоне", "Background media"),
                        subtitle: AppText.tr("Подгружать медиа открытого чата", "Prefetch media for open chat")
                    )
                }
            } footer: {
                Text(AppText.tr(
                    "Для push нужен доступ к уведомлениям в iOS. TDLib регистрирует токен устройства в Telegram.",
                    "Push requires iOS notification permission. TDLib registers the device token with Telegram."
                ))
            }

            Section(AppText.tr("В приложении", "In-app")) {
                Toggle(isOn: $appSettings.enableIncomingBanners) {
                    settingsLabel(
                        icon: "bell.badge",
                        title: AppText.tr("Баннеры входящих", "Incoming banners"),
                        subtitle: AppText.tr("Всплывающее уведомление вверху экрана", "Toast at the top of the screen")
                    )
                }

                Toggle(isOn: $appSettings.enableInAppSounds) {
                    settingsLabel(
                        icon: "speaker.wave.2",
                        title: AppText.tr("Звук в приложении", "In-app sound"),
                        subtitle: AppText.tr("Короткий сигнал при новом сообщении", "Short alert for new messages")
                    )
                }
            }

            Section(AppText.tr("Чаты", "Chats")) {
                Toggle(isOn: $appSettings.showMessageTimestamps) {
                    settingsLabel(
                        icon: "clock",
                        title: AppText.tr("Время в сообщениях", "Message timestamps"),
                        subtitle: AppText.tr("Показывать время отправки в пузырях", "Show send time in bubbles")
                    )
                }
            }

            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    settingsLabel(
                        icon: "gear",
                        title: AppText.tr("Настройки iOS", "iOS Settings"),
                        subtitle: AppText.tr("Звуки, баннеры, фокус", "Sounds, banners, Focus")
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Уведомления", "Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await pushService.refreshAuthorizationStatus()
        }
    }

    @ViewBuilder
    private var pushStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: pushStatusIcon)
                .foregroundStyle(pushStatusColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppText.tr("Статус push", "Push status"))
                Text(pushStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var pushStatusIcon: String {
        switch pushService.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private var pushStatusColor: Color {
        switch pushService.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .orange
        default: return .secondary
        }
    }

    private var pushStatusText: String {
        if let error = pushService.lastRegistrationError, !error.isEmpty {
            return error
        }
        switch pushService.authorizationStatus {
        case .authorized:
            if pushService.deviceTokenHex != nil {
                return AppText.tr("Разрешено, токен получен", "Allowed, token received")
            }
            return AppText.tr("Разрешено, ожидание токена", "Allowed, waiting for token")
        case .denied:
            return AppText.tr("Запрещено в iOS", "Denied in iOS")
        case .notDetermined:
            return AppText.tr("Нужно разрешение", "Permission required")
        case .provisional:
            return AppText.tr("Временно разрешено", "Provisionally allowed")
        case .ephemeral:
            return AppText.tr("Временный доступ", "Ephemeral access")
        @unknown default:
            return AppText.tr("Неизвестно", "Unknown")
        }
    }

    private func settingsLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
