import SwiftUI
import UIKit

struct ContactsListView: View {
    @ObservedObject var vm: AppViewModel
    @State private var showNewConversation = false

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
                    .padding(.vertical, 8)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
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
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            } else {
                ForEach(vm.groupedFilteredContacts, id: \.letter) { section in
                    Section(section.letter) {
                        ForEach(section.contacts) { contact in
                            contactRow(contact)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground())
        .transparentNavigationBar()
        .navigationTitle(AppText.tr("Контакты", "Contacts"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $vm.contactsSearch,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: AppText.tr("Поиск", "Search")
        )
        .overlay {
            if vm.isContactsLoading && vm.contacts.isEmpty {
                ProgressView()
            }
        }
        .refreshable {
            await vm.refreshContacts(force: true)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNewConversation = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(AppText.tr("Новый чат", "New chat"))
            }

            ToolbarItem(placement: .navigationBarLeading) {
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
        .sheet(isPresented: $showNewConversation) {
            NewConversationView(vm: vm)
        }
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
        .transparentNavigationBar()
        .navigationTitle(AppText.tr("Контакты", "Contacts"))
        .navigationBarTitleDisplayMode(.inline)
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
            ContactRowView(
                contact: contact,
                vm: vm,
                onPremiumBadgeTap: contact.isPremium
                    ? { vm.presentPremiumUpsell(for: contact.displayName, badgePath: contact.premiumBadgePath) }
                    : nil
            )
        }
        .buttonStyle(ChatRowPressStyle())
    }
}

private struct ContactRowView: View {
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
                    Text(AppText.tr("в Telegram", "on Telegram"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
