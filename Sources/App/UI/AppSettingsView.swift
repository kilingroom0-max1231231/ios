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
                Toggle(isOn: $appSettings.showMessageTimestamps) {
                    settingsLabel(
                        icon: "clock",
                        title: AppText.tr("Время сообщений", "Message time"),
                        subtitle: AppText.tr("Время в пузырях чата", "Time in chat bubbles")
                    )
                }

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
                Toggle(isOn: $appSettings.enableDoubleTapQuickReaction) {
                    settingsLabel(
                        icon: "hand.tap.fill",
                        title: AppText.tr("Двойной тап", "Double tap"),
                        subtitle: AppText.tr("Быстрая реакция по двойному нажатию", "Quick reaction on double tap")
                    )
                }

                if appSettings.enableDoubleTapQuickReaction {
                    NavigationLink {
                        QuickReactionEmojiPickerView(appSettings: appSettings)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "face.smiling")
                                .foregroundStyle(AppColors.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppText.tr("Эмодзи быстрой реакции", "Quick reaction emoji"))
                                HStack(spacing: 6) {
                                    Text(appSettings.doubleTapQuickReactionEmoji)
                                        .font(.title2)
                                    Text(AppText.tr("выбрано", "selected"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Toggle(isOn: $appSettings.enableLongPressMessagePanel) {
                    settingsLabel(
                        icon: "rectangle.stack",
                        title: AppText.tr("Панель по удержанию", "Hold for panel"),
                        subtitle: AppText.tr("Реакции и действия при долгом нажатии", "Reactions and actions on long press")
                    )
                }

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
            } footer: {
                Text(AppText.tr(
                    "Двойной тап ставит или снимает выбранную реакцию. Удержание открывает полную панель.",
                    "Double tap toggles the selected reaction. Long press opens the full panel."
                ))
            }

            Section {
                Toggle(isOn: $appSettings.enableTapOnReactionChips) {
                    settingsLabel(
                        icon: "hand.point.up.left.fill",
                        title: AppText.tr("Тап по реакциям", "Tap reactions under message"),
                        subtitle: AppText.tr("Ставить или снять реакцию под сообщением", "Toggle reaction under message")
                    )
                }

                Toggle(isOn: $appSettings.reactionHapticFeedback) {
                    settingsLabel(
                        icon: "waveform",
                        title: AppText.tr("Вибрация реакций", "Reaction haptics"),
                        subtitle: AppText.tr("Тактильный отклик при выборе", "Haptic feedback on pick")
                    )
                }

                Toggle(isOn: $appSettings.expandReactionPickerByDefault) {
                    settingsLabel(
                        icon: "arrow.up.left.and.arrow.down.right",
                        title: AppText.tr("Развёрнутая панель", "Expanded picker"),
                        subtitle: AppText.tr("Сразу все реакции в панели действий", "Show all reactions in action panel")
                    )
                }

                Toggle(isOn: $appSettings.confirmReactionRemove) {
                    settingsLabel(
                        icon: "exclamationmark.bubble",
                        title: AppText.tr("Подтверждать снятие", "Confirm remove"),
                        subtitle: AppText.tr("Перед удалением своей реакции", "Before removing your reaction")
                    )
                }
            } header: {
                Text(AppText.tr("Реакции", "Reactions"))
            } footer: {
                Text(AppText.tr(
                    "С Premium можно ставить несколько реакций — лимит задаёт Telegram.",
                    "With Premium you can add multiple reactions — limit is set by Telegram."
                ))
            }

            Section {
                Toggle(isOn: $appSettings.showChatFolderTabs) {
                    settingsLabel(
                        icon: "folder.fill",
                        title: AppText.tr("Вкладки папок", "Folder tabs"),
                        subtitle: AppText.tr("Показывать папки над списком чатов", "Show folders above chat list")
                    )
                }
            } header: {
                Text(AppText.tr("Чаты и папки", "Chats & folders"))
            } footer: {
                Text(AppText.tr(
                    "Папки синхронизируются с официальным Telegram. Удержание вкладки — настройки папки, контекстное меню чата — «В папку».",
                    "Folders sync with official Telegram. Long press tab for folder settings, chat menu — Move to folder."
                ))
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
