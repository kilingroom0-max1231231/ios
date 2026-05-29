import SwiftUI

struct NotificationsSettingsView: View {
    @ObservedObject var appSettings: AppSettingsStore

    var body: some View {
        List {
            Section {
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
            } footer: {
                Text(AppText.tr(
                    "Системные push-уведомления iOS настраиваются отдельно в Настройках iPhone.",
                    "iOS system push notifications are configured separately in iPhone Settings."
                ))
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
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Уведомления", "Notifications"))
        .navigationBarTitleDisplayMode(.inline)
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
