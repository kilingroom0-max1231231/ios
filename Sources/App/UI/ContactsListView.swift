import SwiftUI

struct ContactsListView: View {
    @ObservedObject var vm: AppViewModel
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch vm.deviceContactsAuthorization {
                case .denied, .restricted:
                    accessDeniedView
                default:
                    contactsList
                }
            }
            .navigationDestination(for: Int64.self) { chatId in
                ChatDetailView(vm: vm, chatId: chatId)
            }
        }
        .task {
            await vm.refreshContactsIfNeeded()
        }
    }

    private var contactsList: some View {
        List {
            if vm.deviceContactsAuthorization == .notDetermined {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppText.tr(
                            "Разрешите доступ к контактам, чтобы находить друзей в Telegram и синхронизировать телефонную книгу.",
                            "Allow access to contacts to find friends on Telegram and sync your phone book."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Button {
                            Task { await vm.requestDeviceContactsAccess() }
                        } label: {
                            Text(AppText.tr("Разрешить доступ", "Allow access"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accent)
                    }
                    .padding(.vertical, 6)
                }
            }

            if vm.isSyncingContacts {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(AppText.tr("Синхронизация контактов…", "Syncing contacts…"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if vm.filteredContacts.isEmpty && !vm.isContactsLoading {
                Section {
                    ContentUnavailableView(
                        AppText.tr("Нет контактов", "No contacts"),
                        systemImage: "person.2.slash",
                        description: Text(AppText.tr(
                            "Синхронизируйте телефонную книгу или добавьте контакты в Telegram.",
                            "Sync your phone book or add contacts in Telegram."
                        ))
                    )
                }
            } else {
                Section {
                    ForEach(vm.filteredContacts) { contact in
                        contactRow(contact)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground())
        .overlay {
            if vm.isContactsLoading && vm.contacts.isEmpty {
                ProgressView()
            }
        }
        .searchable(
            text: $vm.contactsSearch,
            prompt: AppText.tr("Поиск контактов", "Search contacts")
        )
        .refreshable {
            await vm.refreshContacts(force: true)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await vm.syncDeviceContactsWithTelegram() }
                } label: {
                    if vm.isSyncingContacts {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(vm.isSyncingContacts)
                .accessibilityLabel(AppText.tr("Синхронизировать", "Sync"))
            }
        }
        .mainTabNavigationBar(title: AppText.tr("Контакты", "Contacts"))
    }

    private var accessDeniedView: some View {
        ContentUnavailableView {
            Label(AppText.tr("Нет доступа к контактам", "No contacts access"), systemImage: "person.crop.circle.badge.xmark")
        } description: {
            Text(AppText.tr(
                "Откройте Настройки iOS → Конфиденциальность → Контакты и разрешите доступ для этого приложения.",
                "Open iOS Settings → Privacy → Contacts and allow access for this app."
            ))
        } actions: {
            Button(AppText.tr("Открыть настройки", "Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)

            Button(AppText.tr("Показать контакты Telegram", "Show Telegram contacts")) {
                Task { await vm.refreshContacts(force: true) }
            }
        }
        .mainTabNavigationBar(title: AppText.tr("Контакты", "Contacts"))
    }

    private func contactRow(_ contact: TgContact) -> some View {
        Button {
            navigationPath.append(contact.privateChatId)
        } label: {
            HStack(spacing: 12) {
                AvatarView(
                    title: contact.displayName,
                    identifier: contact.userId,
                    imagePath: contact.avatarPath,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 3) {
                    DisplayNameWithPremium(
                        name: contact.displayName,
                        isPremium: contact.isPremium,
                        badgeImagePath: contact.premiumBadgePath,
                        font: .headline,
                        lineLimit: 1,
                        onPremiumBadgeTap: contact.isPremium
                            ? { vm.presentPremiumUpsell(for: contact.displayName, badgePath: contact.premiumBadgePath) }
                            : nil
                    )

                    if let phone = contact.phoneNumber, !phone.isEmpty {
                        Text(phone)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let username = contact.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
