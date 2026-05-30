import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject private var appSettings = AppSettingsStore.shared
    @ObservedObject private var tabBar = MainTabBarStore.shared
    @ObservedObject private var accountStore = AccountSessionStore.shared
    @EnvironmentObject private var languageStore: AppLanguageStore
    @State private var accountPendingRemoval: AccountSession?

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
                            badgeImagePath: vm.me?.premiumBadgePath,
                            font: .headline,
                            onPremiumBadgeTap: vm.me?.isPremium == true
                                ? { vm.presentPremiumUpsell(for: vm.me?.displayName ?? "", badgePath: vm.me?.premiumBadgePath) }
                                : nil
                        )

                        if let username = vm.me?.username, !username.isEmpty {
                            UsernameLine(
                                username: username,
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

            Section(AppText.tr("Аккаунты", "Accounts")) {
                if vm.isSwitchingAccount {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(AppText.tr("Переключение аккаунта…", "Switching account…"))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                ForEach(accountStore.sessions) { account in
                    accountRow(account)
                }

                Button {
                    vm.addAccount()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(vm.canAddMoreAccounts ? AppColors.accent : .secondary)
                            .frame(width: 28)
                        Text(AppText.tr("Добавить аккаунт", "Add account"))
                            .foregroundStyle(vm.canAddMoreAccounts ? .primary : .secondary)
                    }
                }
                .disabled(!vm.canAddMoreAccounts || vm.isSwitchingAccount)

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
                                badgeImagePath: me.premiumBadgePath,
                                font: .body,
                                showBadgeOnName: false
                            )
                        }
                    }
                }

                NavigationLink {
                    PrivacySettingsView(vm: vm)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 28)
                        Text(AppText.tr("Конфиденциальность", "Privacy"))
                    }
                }
            }

            Section(AppText.tr("Контакты", "Contacts")) {
                Toggle(isOn: $appSettings.syncContactsOnLaunch) {
                    settingsLinkLabel(
                        icon: "arrow.triangle.2.circlepath",
                        title: AppText.tr("Синхронизация при запуске", "Sync on launch"),
                        subtitle: AppText.tr("Телефонная книга → Telegram", "Phone book → Telegram")
                    )
                }

                Button {
                    vm.selectMainTab(.contacts)
                } label: {
                    settingsLinkLabel(
                        icon: "person.2.fill",
                        title: AppText.tr("Список контактов", "Contacts list"),
                        subtitle: AppText.tr("\(vm.contacts.count) в Telegram", "\(vm.contacts.count) on Telegram")
                    )
                }
            }

            Section(AppText.tr("Приложение", "Application")) {
                NavigationLink {
                    NotificationsSettingsView(appSettings: appSettings)
                } label: {
                    settingsLinkLabel(
                        icon: "bell.badge",
                        title: AppText.tr("Уведомления", "Notifications"),
                        subtitle: AppText.tr("Push, фон, баннеры", "Push, background, banners")
                    )
                }

                NavigationLink {
                    DataStorageSettingsView(vm: vm, appSettings: appSettings)
                } label: {
                    settingsLinkLabel(
                        icon: "externaldrive",
                        title: AppText.tr("Данные и память", "Data & storage"),
                        subtitle: AppText.tr("Кэш, контакты, удалённые", "Cache, contacts, deleted")
                    )
                }

                NavigationLink {
                    AppSettingsView(
                        vm: vm,
                        appSettings: appSettings,
                        swipeSettings: MessageSwipeSettingsStore.shared
                    )
                } label: {
                    settingsLinkLabel(
                        icon: "slider.horizontal.3",
                        title: AppText.tr("Поведение", "Behavior"),
                        subtitle: AppText.tr("Реакции, жесты, папки, свайпы", "Reactions, gestures, folders, swipes")
                    )
                }

                NavigationLink {
                    AppearanceSettingsView(appearance: AppAppearanceStore.shared)
                } label: {
                    settingsLinkLabel(
                        icon: "paintpalette.fill",
                        title: AppText.tr("Оформление", "Appearance"),
                        subtitle: AppText.tr("Тема, фоны, пузыри", "Theme, backgrounds, bubbles")
                    )
                }

                NavigationLink {
                    TabBarCustomizationView(store: tabBar)
                } label: {
                    settingsLinkLabel(
                        icon: "dock.rectangle",
                        title: AppText.tr("Панель вкладок", "Tab bar"),
                        subtitle: AppText.tr("Видимость и порядок вкладок", "Tab visibility and order")
                    )
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
                NavigationLink {
                    AboutView()
                } label: {
                    settingsLinkLabel(
                        icon: "info.circle.fill",
                        title: AppText.tr("О приложении", "About"),
                        subtitle: "Telegram User Client"
                    )
                }
            }

            Section {
                Button(role: .destructive) {
                    vm.signOut()
                } label: {
                    Label(
                        AppText.tr("Сбросить приложение", "Reset app"),
                        systemImage: "arrow.counterclockwise"
                    )
                }
            } footer: {
                Text(AppText.tr(
                    "Удалит API-данные и все локальные сессии. Для выхода из одного аккаунта проведите по нему влево в списке выше.",
                    "Removes API credentials and all local sessions. To sign out of one account, swipe it left in the list above."
                ))
                .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .mainTabNavigationBar(title: AppText.tr("Настройки", "Settings"))
        .task {
            await vm.refreshMe()
        }
        .alert(
            AppText.tr("Выйти из аккаунта?", "Sign out of this account?"),
            isPresented: Binding(
                get: { accountPendingRemoval != nil },
                set: { if !$0 { accountPendingRemoval = nil } }
            ),
            presenting: accountPendingRemoval
        ) { account in
            Button(AppText.tr("Выйти", "Sign out"), role: .destructive) {
                Task { await vm.removeAccount(id: account.id) }
            }
            Button(AppText.tr("Отмена", "Cancel"), role: .cancel) {
                accountPendingRemoval = nil
            }
        } message: { account in
            Text(AppText.tr(
                "Локальные данные «\(account.title)» будут удалены с этого устройства.",
                "Local data for “\(account.title)” will be removed from this device."
            ))
        }
    }

    @ViewBuilder
    private func accountRow(_ account: AccountSession) -> some View {
        let isActive = account.id == accountStore.activeAccountId

        Button {
            guard !isActive, !vm.isSwitchingAccount else { return }
            Task { await vm.switchAccount(to: account.id) }
        } label: {
            HStack(spacing: 12) {
                AvatarView(
                    title: account.title,
                    identifier: account.userId ?? Int64(abs(account.id.hashValue)),
                    imagePath: account.avatarPath,
                    size: 44
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(account.title)
                            .font(.body.weight(isActive ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        if isActive {
                            Text(AppText.tr("активен", "active"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColors.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    if let phone = account.phone, !phone.isEmpty {
                        Text(phone)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if isActive, let username = vm.me?.username, !username.isEmpty {
                        UsernameLine(username: username, font: .caption, color: .secondary)
                    }
                }

                Spacer(minLength: 0)

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(vm.isSwitchingAccount)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                accountPendingRemoval = account
            } label: {
                Label(AppText.tr("Выйти", "Sign out"), systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    private var statusText: String {
        switch vm.authState {
        case .ready: return AppText.tr("Подключено", "Connected")
        case .waitPhone, .waitCode, .waitPassword: return AppText.tr("Требуется авторизация", "Authorization required")
        }
    }

    private func settingsLinkLabel(icon: String, title: String, subtitle: String) -> some View {
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
