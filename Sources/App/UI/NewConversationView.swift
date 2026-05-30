import SwiftUI

struct NewConversationView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var showNewGroup = false
    @State private var showNewChannel = false
    @State private var showJoinLink = false

    private var filteredContacts: [TgContact] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return vm.contacts }
        return vm.contacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || ($0.username?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || ($0.phoneNumber?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    composeActionRow(
                        title: AppText.tr("Новая группа", "New Group"),
                        subtitle: AppText.tr("До 200 000 участников", "Up to 200,000 members"),
                        icon: "person.3.fill",
                        tint: .green
                    ) {
                        showNewGroup = true
                    }

                    composeActionRow(
                        title: AppText.tr("Новый канал", "New Channel"),
                        subtitle: AppText.tr("Трансляция для неограниченной аудитории", "Broadcast to unlimited audience"),
                        icon: "megaphone.fill",
                        tint: .orange
                    ) {
                        showNewChannel = true
                    }

                    composeActionRow(
                        title: AppText.tr("По ссылке", "Join by Link"),
                        subtitle: AppText.tr("t.me/+… или @username", "t.me/+… or @username"),
                        icon: "link",
                        tint: AppColors.accent
                    ) {
                        showJoinLink = true
                    }
                }
                .listRowBackground(Color(.systemBackground))
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))

                if !filteredContacts.isEmpty {
                    Section(AppText.tr("Контакты", "Contacts")) {
                        ForEach(filteredContacts) { contact in
                            Button {
                                Task { await openContact(contact) }
                            } label: {
                                contactRow(contact)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Color(.systemBackground))
                    .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                } else if vm.isContactsLoading {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Section {
                        Text(AppText.tr("Контакты не найдены", "No contacts found"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ChatListScreenBackground().ignoresSafeArea())
            .navigationTitle(AppText.tr("Новое сообщение", "New Message"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: AppText.tr("Кому написать?", "Who would you like to write to?")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.tr("Отмена", "Cancel")) { dismiss() }
                }
            }
            .task {
                await vm.refreshContactsIfNeeded()
            }
            .sheet(isPresented: $showNewGroup) {
                NewGroupSheet(vm: vm) { chatId in
                    finish(with: chatId)
                }
            }
            .sheet(isPresented: $showNewChannel) {
                NewChannelSheet(vm: vm) { chatId in
                    finish(with: chatId)
                }
            }
            .sheet(isPresented: $showJoinLink) {
                JoinByLinkSheet(vm: vm) { chatId in
                    finish(with: chatId)
                }
            }
        }
    }

    private func composeActionRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint.gradient)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func contactRow(_ contact: TgContact) -> some View {
        HStack(spacing: 12) {
            AvatarView(
                title: contact.displayName,
                identifier: contact.userId,
                imagePath: contact.avatarPath,
                size: 44
            )

            VStack(alignment: .leading, spacing: 2) {
                DisplayNameWithPremium(
                    name: contact.displayName,
                    isPremium: contact.isPremium,
                    badgeImagePath: contact.premiumBadgePath,
                    font: .body.weight(.semibold)
                )
                if let username = contact.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let phone = contact.phoneNumber, !phone.isEmpty {
                    Text(phone)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func openContact(_ contact: TgContact) async {
        vm.prepareChatFromContact(contact)
        finish(with: contact.privateChatId)
    }

    private func finish(with chatId: Int64) {
        dismiss()
        vm.selectMainTab(.chats)
        vm.navigationTargetChatId = chatId
        Task { await vm.refreshChats() }
    }
}

private struct NewGroupSheet: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let onCreated: (Int64) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var selectedContactIds: Set<Int64> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppText.tr("Название группы", "Group name"), text: $title)
                    TextField(AppText.tr("Описание", "Description"), text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section(AppText.tr("Участники", "Members")) {
                    if vm.contacts.isEmpty {
                        Text(AppText.tr("Сначала синхронизируйте контакты", "Sync contacts first"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.contacts) { contact in
                            Button {
                                toggle(contact.userId)
                            } label: {
                                HStack(spacing: 10) {
                                    AvatarView(
                                        title: contact.displayName,
                                        identifier: contact.userId,
                                        imagePath: contact.avatarPath,
                                        size: 36
                                    )
                                    Text(contact.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedContactIds.contains(contact.userId) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppColors.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(AppText.tr("Новая группа", "New Group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.tr("Отмена", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.tr("Создать", "Create")) {
                        Task { await create() }
                    }
                    .disabled(vm.isBusy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func toggle(_ userId: Int64) {
        if selectedContactIds.contains(userId) {
            selectedContactIds.remove(userId)
        } else {
            selectedContactIds.insert(userId)
        }
    }

    private func create() async {
        do {
            let chatId = try await vm.createGroup(
                title: title,
                description: description,
                memberUserIds: Array(selectedContactIds)
            )
            dismiss()
            onCreated(chatId)
        } catch {
            vm.status = error.localizedDescription
        }
    }
}

private struct NewChannelSheet: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let onCreated: (Int64) -> Void

    @State private var title = ""
    @State private var description = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppText.tr("Название канала", "Channel name"), text: $title)
                    TextField(AppText.tr("Описание", "Description"), text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(AppText.tr("Новый канал", "New Channel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.tr("Отмена", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.tr("Создать", "Create")) {
                        Task { await create() }
                    }
                    .disabled(vm.isBusy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func create() async {
        do {
            let chatId = try await vm.createChannel(title: title, description: description)
            dismiss()
            onCreated(chatId)
        } catch {
            vm.status = error.localizedDescription
        }
    }
}

private struct JoinByLinkSheet: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let onJoined: (Int64) -> Void

    @State private var link = ""
    @State private var username = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.tr("Пригласительная ссылка", "Invite link")) {
                    TextField("https://t.me/+…", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(AppText.tr("Или username", "Or username")) {
                    TextField("@username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(AppText.tr("По ссылке", "Join by Link"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.tr("Отмена", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.tr("Открыть", "Open")) {
                        Task { await submit() }
                    }
                    .disabled(vm.isBusy || !canSubmit)
                }
            }
        }
    }

    private var canSubmit: Bool {
        !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        do {
            let chatId: Int64
            let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLink.isEmpty {
                chatId = try await vm.joinChatByInviteLink(trimmedLink)
            } else {
                chatId = try await vm.openChatByUsername(trimmedUser)
            }
            dismiss()
            onJoined(chatId)
        } catch {
            vm.status = error.localizedDescription
        }
    }
}
