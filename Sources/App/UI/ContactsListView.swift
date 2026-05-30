import SwiftUI
import UIKit

struct ContactsListView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        NavigationStack {
            Group {
                switch vm.deviceContactsAuthorization {
                case .denied, .restricted:
                    accessDeniedView
                default:
                    contactsList
                }
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
                    permissionCard
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }

            if vm.isSyncingContacts {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(AppText.tr("Синхронизация контактов…", "Syncing contacts…"))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }

            if vm.filteredContacts.isEmpty && !vm.isContactsLoading {
                Section {
                    emptyStateView(
                        icon: "person.2.slash",
                        title: AppText.tr("Нет контактов", "No contacts"),
                        message: AppText.tr(
                            "Синхронизируйте телефонную книгу или добавьте контакты в Telegram.",
                            "Sync your phone book or add contacts in Telegram."
                        )
                    )
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            } else {
                Section {
                    ForEach(vm.filteredContacts) { contact in
                        contactRow(contact)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground())
        .safeAreaInset(edge: .top, spacing: 0) {
            contactsHeader
        }
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

    private var contactsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppText.tr("Контакты Telegram", "Telegram contacts"))
                    .font(.subheadline.weight(.semibold))
                Text(AppText.tr(
                    "\(vm.filteredContacts.count) из \(vm.contacts.count)",
                    "\(vm.filteredContacts.count) of \(vm.contacts.count)"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var permissionCard: some View {
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var accessDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()

            emptyStateView(
                icon: "person.crop.circle.badge.xmark",
                title: AppText.tr("Нет доступа к контактам", "No contacts access"),
                message: AppText.tr(
                    "Откройте Настройки iOS → Конфиденциальность → Контакты и разрешите доступ для этого приложения.",
                    "Open iOS Settings → Privacy → Contacts and allow access for this app."
                )
            )
            .padding(.horizontal, 24)

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
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChatListScreenBackground())
        .mainTabNavigationBar(title: AppText.tr("Контакты", "Contacts"))
    }

    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func contactRow(_ contact: TgContact) -> some View {
        Button {
            vm.prepareChatFromContact(contact)
            Task { await vm.openChat(chatId: contact.privateChatId) }
        } label: {
            ContactCardView(
                contact: contact,
                vm: vm,
                onPremiumBadgeTap: contact.isPremium
                    ? { vm.presentPremiumUpsell(for: contact.displayName, badgePath: contact.premiumBadgePath) }
                    : nil
            )
        }
        .buttonStyle(ContactRowPressStyle())
    }
}

private struct ContactCardView: View {
    let contact: TgContact
    var vm: AppViewModel? = nil
    var onPremiumBadgeTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                title: contact.displayName,
                identifier: contact.userId,
                imagePath: contact.avatarPath,
                size: 52
            )

            VStack(alignment: .leading, spacing: 4) {
                DisplayNameWithPremium(
                    name: contact.displayName,
                    isPremium: contact.isPremium,
                    badgeImagePath: contact.premiumBadgePath,
                    font: .headline,
                    lineLimit: 1,
                    onPremiumBadgeTap: onPremiumBadgeTap
                )

                if let phone = contact.phoneNumber, !phone.isEmpty {
                    Text(phone)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let username = contact.username, !username.isEmpty {
                    UsernameLine(
                        username: username,
                        font: .subheadline,
                        color: AppColors.accent,
                        vm: vm
                    )
                } else {
                    Text(AppText.tr("Контакт Telegram", "Telegram contact"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ContactRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
