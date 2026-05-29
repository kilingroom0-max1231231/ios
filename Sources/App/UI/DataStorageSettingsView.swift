import SwiftUI

struct DataStorageSettingsView: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject var appSettings: AppSettingsStore

    var body: some View {
        List {
            Section(AppText.tr("Хранилище", "Storage")) {
                infoRow(
                    icon: "externaldrive",
                    title: AppText.tr("Сообщения", "Messages"),
                    value: AppText.tr("Локальная SQLite", "Local SQLite")
                )
                infoRow(
                    icon: "person.3",
                    title: AppText.tr("Чаты", "Chats"),
                    value: AppText.tr("Локальный кэш", "Local cache")
                )
                infoRow(
                    icon: "photo",
                    title: AppText.tr("Медиа", "Media"),
                    value: AppText.tr("TDLib + превью", "TDLib + previews")
                )
            }

            Section(AppText.tr("Контакты", "Contacts")) {
                Toggle(isOn: $appSettings.syncContactsOnLaunch) {
                    settingsLabel(
                        icon: "arrow.triangle.2.circlepath",
                        title: AppText.tr("Синхронизация при запуске", "Sync on launch"),
                        subtitle: AppText.tr("Импорт телефонной книги в Telegram", "Import phone book into Telegram")
                    )
                }

                Button {
                    Task { await vm.syncDeviceContactsWithTelegram() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 28)
                        Text(AppText.tr("Синхронизировать сейчас", "Sync now"))
                        Spacer()
                        if vm.isSyncingContacts {
                            ProgressView()
                        }
                    }
                }
                .disabled(vm.isSyncingContacts)
            }

            Section {
                Toggle(isOn: $appSettings.keepDeletedMessages) {
                    settingsLabel(
                        icon: "trash.slash",
                        title: AppText.tr("Хранить удалённые", "Keep deleted messages"),
                        subtitle: AppText.tr("Оставлять удалённые в локальной базе", "Keep deleted in local DB")
                    )
                }
            } header: {
                Text(AppText.tr("Сообщения", "Messages"))
            } footer: {
                Text(AppText.tr(
                    "Очистка кэша TDLib выполняется через официальный клиент или переустановку данных приложения.",
                    "Clearing TDLib cache is done via the official client or by reinstalling app data."
                ))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Данные и память", "Data & storage"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: appSettings.keepDeletedMessages) { _ in
            Task { await vm.applyKeepDeletedMessagesPreference() }
        }
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)
            Text(title)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
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
