import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: AppViewModel
    @EnvironmentObject private var languageStore: AppLanguageStore

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    if let me = vm.me {
                        AvatarView(
                            title: me.displayName,
                            identifier: me.id,
                            imagePath: me.avatarPath,
                            size: 52
                        )
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(AppColors.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        DisplayNameWithPremium(
                            name: vm.me?.displayName ?? AppText.tr("Telegram User Client", "Telegram User Client"),
                            isPremium: vm.me?.isPremium ?? false,
                            font: .headline
                        )

                        if let username = vm.me?.username, !username.isEmpty {
                            UsernameWithPremium(
                                username: username,
                                isPremium: vm.me?.isPremium ?? false,
                                badgeImagePath: vm.me?.premiumBadgePath,
                                font: .subheadline,
                                color: .secondary
                            )
                        } else {
                            Text(statusText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section(AppText.tr("Аккаунт", "Account")) {
                if let me = vm.me {
                    NavigationLink {
                        UserProfileView(vm: vm, userId: me.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(AppColors.accent)
                                .frame(width: 28)
                            DisplayNameWithPremium(
                                name: AppText.tr("Мой профиль", "My profile"),
                                isPremium: me.isPremium,
                                font: .body
                            )
                        }
                    }
                }

                NavigationLink {
                    PrivacySettingsView(vm: vm)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 28)
                        Text(AppText.tr("Профиль и приватность", "Profile & privacy"))
                    }
                }
            }

            Section(AppText.tr("Приложение", "Application")) {
                NavigationLink {
                    AppearanceSettingsView(appearance: AppAppearanceStore.shared)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 28)
                        Text(AppText.tr("Оформление", "Appearance"))
                    }
                }

                NavigationLink {
                    MessageSwipeSettingsView(store: MessageSwipeSettingsStore.shared)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.draw")
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 28)
                        Text(AppText.tr("Свайп сообщения", "Message swipe"))
                    }
                }

                Picker(selection: $languageStore.preferredLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 28)
                        Text(AppText.tr("Язык", "Language"))
                    }
                }
            }

            Section(AppText.tr("О приложении", "About")) {
                settingsRow(icon: "sparkles", title: AppText.tr("Интерфейс", "Interface"), value: AppText.tr("Нативный Apple", "Native Apple"))
                settingsRow(icon: "lock.shield", title: AppText.tr("Хранилище", "Storage"), value: AppText.tr("Локальная база TDLib", "Local TDLib database"))
                settingsRow(icon: "photo.on.rectangle", title: AppText.tr("Медиа", "Media"), value: AppText.tr("Встроенный просмотр", "Inline previews"))
            }

            Section {
                Button(role: .destructive) {
                    vm.signOut()
                } label: {
                    Label(AppText.tr("Выйти", "Logout"), systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .mainTabNavigationBar(title: AppText.tr("Настройки", "Settings"))
        .task {
            await vm.refreshMe()
        }
    }

    private var statusText: String {
        switch vm.authState {
        case .ready: return AppText.tr("Подключено", "Connected")
        case .waitPhone, .waitCode, .waitPassword: return AppText.tr("Требуется авторизация", "Authorization required")
        }
    }

    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
