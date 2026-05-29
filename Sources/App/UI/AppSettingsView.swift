import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject var appSettings: AppSettingsStore
    @ObservedObject var swipeSettings: MessageSwipeSettingsStore

    var body: some View {
        List {
            Section {
                Toggle(isOn: $appSettings.showProfileChatKind) {
                    settingsLabel(
                        icon: "person.text.rectangle",
                        title: AppText.tr("Тип чата в профиле", "Chat type in profile"),
                        subtitle: AppText.tr("Пользователь, группа, канал…", "User, group, channel…")
                    )
                }

                Toggle(isOn: $appSettings.showProfileChatId) {
                    settingsLabel(
                        icon: "number",
                        title: AppText.tr("ID чата в профиле", "Chat ID in profile"),
                        subtitle: AppText.tr("Показывать числовой chat_id", "Show numeric chat_id")
                    )
                }

                Toggle(isOn: $appSettings.showProfileUserId) {
                    settingsLabel(
                        icon: "person.badge.key",
                        title: AppText.tr("ID пользователя в профиле", "User ID in profile"),
                        subtitle: AppText.tr("Для личных профилей", "For private user profiles")
                    )
                }
            } header: {
                Text(AppText.tr("Профиль", "Profile"))
            }

            Section {
                Toggle(isOn: $appSettings.keepDeletedMessages) {
                    settingsLabel(
                        icon: "trash.slash",
                        title: AppText.tr("Хранить удалённые", "Keep deleted messages"),
                        subtitle: AppText.tr(
                            "Если выкл. — удалённые исчезают из чата и локальной базы",
                            "If off — deleted messages are removed from chat and local DB"
                        )
                    )
                }
            } header: {
                Text(AppText.tr("Сообщения", "Messages"))
            }

            Section {
                NavigationLink {
                    MessageSwipeSettingsView(store: swipeSettings)
                } label: {
                    settingsLabel(
                        icon: "hand.draw",
                        title: AppText.tr("Свайп сообщений", "Message swipe"),
                        subtitle: AppText.tr("Действия при свайпе влево", "Actions on swipe left")
                    )
                }
            } header: {
                Text(AppText.tr("Жесты", "Gestures"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Настройки приложения", "App settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: appSettings.keepDeletedMessages) { _ in
            Task { await vm.applyKeepDeletedMessagesPreference() }
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
