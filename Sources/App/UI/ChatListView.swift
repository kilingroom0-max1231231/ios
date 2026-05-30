import SwiftUI
import UIKit

struct ChatListView: View {
    enum Mode {
        case main
        case archive
    }

    @ObservedObject var vm: AppViewModel
    @EnvironmentObject private var appSettings: AppSettingsStore
    var mode: Mode = .main
    @State private var navigationPath = NavigationPath()
    @State private var showNewConversation = false

    private var isArchiveMode: Bool { mode == .archive }
    private var listKind: TgChatListKind { isArchiveMode ? .archive : vm.mainListKind }

    var body: some View {
        if isArchiveMode {
            chatListContent
        } else {
            NavigationStack(path: $navigationPath) {
                chatListContent
            }
            .onChange(of: vm.navigationTargetChatId) { target in
                guard let target else { return }
                navigationPath.append(target)
                vm.navigationTargetChatId = nil
            }
        }
    }

    private var chatListContent: some View {
        List {
            if !isArchiveMode, appSettings.showChatFolderTabs, !vm.chatFolders.isEmpty {
                Section {
                    ChatFolderTabsView(vm: vm)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            }

            if !isArchiveMode, let summary = vm.archiveSummary {
                NavigationLink {
                    ChatListView(vm: vm, mode: .archive)
                } label: {
                    ArchiveChatRowView(summary: summary)
                }
                .buttonStyle(ChatRowPressStyle())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            }

            ForEach(visiblePinnedChats) { chat in
                chatRow(chat)
            }
            .onMove { source, destination in
                guard vm.chatSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Task { await vm.movePinnedChats(from: source, to: destination, list: listKind) }
            }

            ForEach(visibleOtherChats) { chat in
                chatRow(chat)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground())
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: displayedChats)
        .navigationDestination(for: Int64.self) { chatId in
            ChatDetailView(vm: vm, chatId: chatId)
        }
        .transparentNavigationBar()
        .navigationTitle(isArchiveMode ? AppText.tr("Архив", "Archived") : AppText.tr("Чаты", "Chats"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $vm.chatSearch,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: AppText.tr("Поиск", "Search")
        )
        .overlay {
            if displayedChats.isEmpty && !vm.isBusy {
                emptyChatsView
            }
        }
        .task {
            if isArchiveMode {
                await vm.refreshArchivedChatsIfNeeded()
            }
        }
        .refreshable {
            if isArchiveMode {
                await vm.refreshArchivedChatsIfNeeded()
            } else {
                await vm.refreshChats()
            }
        }
        .toolbar {
            if !isArchiveMode, vm.selectedChatFolderId != nil {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if let folder = vm.chatFolders.first(where: { $0.id == vm.selectedChatFolderId }) {
                            vm.folderSettingsTarget = folder
                        }
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .accessibilityLabel(AppText.tr("Настройки папки", "Folder settings"))
                }
            }

            if !isArchiveMode {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewConversation = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(AppText.tr("Новый чат", "New chat"))
                }
            }

            if !visiblePinnedChats.isEmpty && vm.chatSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showNewConversation) {
            NewConversationView(vm: vm)
        }
        .sheet(item: $vm.folderSettingsTarget) { folder in
            ChatFolderSettingsView(vm: vm, folder: folder)
        }
        .sheet(item: $vm.moveChatToFolderTarget) { chat in
            MoveChatToFolderSheet(vm: vm, chat: chat)
        }
        .sheet(isPresented: peekSheetPresented) {
            if let chatId = vm.peekChatId {
                ChatPeekView(vm: vm, chatId: chatId)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var displayedChats: [TgChat] {
        isArchiveMode ? vm.filteredArchivedChats : vm.filteredChats
    }

    private var visiblePinnedChats: [TgChat] {
        displayedChats.filter(\.isPinned)
    }

    private var visibleOtherChats: [TgChat] {
        displayedChats.filter { !$0.isPinned }
    }

    private var peekSheetPresented: Binding<Bool> {
        Binding(
            get: { vm.peekChatId != nil },
            set: { isPresented in
                if !isPresented {
                    vm.closeChatPeek()
                }
            }
        )
    }

    private func chatRow(_ chat: TgChat) -> some View {
        NavigationLink(value: chat.id) {
            ChatCardView(
                chat: chat,
                vm: vm,
                onPremiumBadgeTap: chat.kind == .private && chat.peerIsPremium
                    ? { vm.presentPremiumUpsell(for: chat.title, badgePath: chat.peerPremiumBadgePath) }
                    : nil
            )
        }
        .buttonStyle(ChatRowPressStyle())
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    Task { await vm.openChatPeek(chatId: chat.id) }
                }
        )
        .contextMenu {
            chatContextMenu(for: chat)
            Button {
                Task { await vm.openChatPeek(chatId: chat.id) }
            } label: {
                Label(AppText.tr("Просмотр", "Preview"), systemImage: "eye")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await vm.setChatPinned(chat.id, pinned: !chat.isPinned, list: listKind) }
            } label: {
                Label(chat.isPinned ? AppText.tr("Открепить", "Unpin") : AppText.tr("Закрепить", "Pin"), systemImage: chat.isPinned ? "pin.slash" : "pin.fill")
            }
            .tint(.orange)

            if isArchiveMode {
                Button {
                    Task { await vm.unarchiveChat(chat.id) }
                } label: {
                    Label(AppText.tr("Из архива", "Unarchive"), systemImage: "tray.and.arrow.up")
                }
                .tint(AppColors.accent)
            } else {
                Button {
                    Task {
                        if chat.unreadCount > 0 || chat.isMarkedUnread {
                            await vm.markChatRead(chat.id, force: true)
                        } else {
                            await vm.markChatUnread(chat.id)
                        }
                    }
                } label: {
                    Label(chat.unreadCount > 0 || chat.isMarkedUnread ? AppText.tr("Прочитано", "Read") : AppText.tr("Не прочитано", "Unread"), systemImage: chat.unreadCount > 0 || chat.isMarkedUnread ? "envelope.open" : "envelope.badge")
                }
                .tint(AppColors.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isArchiveMode {
                Button {
                    Task { await vm.archiveChat(chat.id) }
                } label: {
                    Label(AppText.tr("В архив", "Archive"), systemImage: "archivebox")
                }
                .tint(.gray)
            }

            Button(role: .destructive) {
                Task {
                    if chat.kind == .basicGroup || chat.kind == .supergroup || chat.kind == .channel {
                        await vm.leaveChat(chat.id)
                    } else {
                        await vm.deleteChat(chat.id)
                    }
                }
            } label: {
                Label(deleteTitle(for: chat), systemImage: "trash")
            }

            Button {
                Task { await vm.setChatMute(chat.id, duration: chat.isMuted ? .off : .forever) }
            } label: {
                Label(chat.isMuted ? AppText.tr("Со звуком", "Unmute") : AppText.tr("Без звука", "Mute"), systemImage: chat.isMuted ? "bell.slash.fill" : "bell.fill")
            }
            .tint(.indigo)
        }
    }

    @ViewBuilder
    private func chatContextMenu(for chat: TgChat) -> some View {
        Button {
            Task { await vm.setChatPinned(chat.id, pinned: !chat.isPinned, list: listKind) }
        } label: {
            Label(chat.isPinned ? AppText.tr("Открепить", "Unpin") : AppText.tr("Закрепить", "Pin"), systemImage: chat.isPinned ? "pin.slash" : "pin.fill")
        }

        if isArchiveMode {
            Button {
                Task { await vm.unarchiveChat(chat.id) }
            } label: {
                Label(AppText.tr("Из архива", "Unarchive"), systemImage: "tray.and.arrow.up")
            }
        } else {
            Button {
                Task { await vm.archiveChat(chat.id) }
            } label: {
                Label(AppText.tr("В архив", "Archive"), systemImage: "archivebox")
            }
        }

        if chat.isMuted {
            Button {
                Task { await vm.setChatMute(chat.id, duration: .off) }
            } label: {
                Label(AppText.tr("Со звуком", "Unmute"), systemImage: "bell.fill")
            }
        } else {
            Menu {
                Button(AppText.tr("1 час", "1 hour")) {
                    Task { await vm.setChatMute(chat.id, duration: .oneHour) }
                }
                Button(AppText.tr("8 часов", "8 hours")) {
                    Task { await vm.setChatMute(chat.id, duration: .eightHours) }
                }
                Button(AppText.tr("Навсегда", "Forever")) {
                    Task { await vm.setChatMute(chat.id, duration: .forever) }
                }
            } label: {
                Label(AppText.tr("Без звука", "Mute"), systemImage: "bell.slash.fill")
            }
        }

        Button {
            Task { await vm.markChatRead(chat.id, force: true) }
        } label: {
            Label(AppText.tr("Прочитано", "Read"), systemImage: "envelope.open")
        }

        if chat.kind == .private || chat.kind == .savedMessages {
            Button {
                Task { await vm.markChatUnread(chat.id) }
            } label: {
                Label(AppText.tr("Не прочитано", "Unread"), systemImage: "envelope.badge")
            }
        }

        if chat.kind == .private, chat.privateUserId != nil {
            Button(role: .destructive) {
                Task { await vm.setUserBlocked(chatId: chat.id, blocked: !chat.isBlockedByMe) }
            } label: {
                Label(
                    chat.isBlockedByMe
                        ? AppText.tr("Разблокировать", "Unblock")
                        : AppText.tr("Заблокировать", "Block"),
                    systemImage: chat.isBlockedByMe ? "hand.raised.slash" : "hand.raised.fill"
                )
            }
        }

        if !isArchiveMode, !vm.chatFolders.isEmpty {
            Button {
                vm.moveChatToFolderTarget = chat
            } label: {
                Label(AppText.tr("В папку…", "Move to folder…"), systemImage: "folder.badge.plus")
            }
        }

        if !isArchiveMode, let folderId = vm.selectedChatFolderId {
            Button(role: .destructive) {
                Task { await vm.removeChat(chat, fromFolder: folderId) }
            } label: {
                Label(AppText.tr("Убрать из папки", "Remove from folder"), systemImage: "folder.badge.minus")
            }
        }

        Divider()

        if chat.kind == .private || chat.kind == .savedMessages {
            Button(role: .destructive) {
                Task { await vm.clearChatHistory(chat.id) }
            } label: {
                Label(AppText.tr("Очистить историю", "Clear History"), systemImage: "eraser")
            }

            if chat.kind == .private {
                Button(role: .destructive) {
                    Task { await vm.deleteChat(chat.id) }
                } label: {
                    Label(AppText.tr("Удалить чат", "Delete Chat"), systemImage: "trash")
                }
            }
        } else if chat.kind == .channel {
            Button(role: .destructive) {
                Task { await vm.leaveChat(chat.id) }
            } label: {
                Label(AppText.tr("Покинуть канал", "Leave Channel"), systemImage: "rectangle.portrait.and.arrow.right")
            }
        } else {
            Button(role: .destructive) {
                Task { await vm.clearChatHistory(chat.id) }
            } label: {
                Label(AppText.tr("Очистить историю", "Clear History"), systemImage: "eraser")
            }
            Button(role: .destructive) {
                Task { await vm.leaveChat(chat.id) }
            } label: {
                Label(AppText.tr("Покинуть группу", "Leave Group"), systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    private func deleteTitle(for chat: TgChat) -> String {
        switch chat.kind {
        case .channel, .basicGroup, .supergroup:
            return AppText.tr("Выйти", "Leave")
        default:
            return AppText.tr("Удалить", "Delete")
        }
    }

    @ViewBuilder
    private var emptyChatsView: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                isArchiveMode ? AppText.tr("Архив пуст", "Archive is empty") : AppText.tr("Нет чатов", "No chats"),
                systemImage: isArchiveMode ? "archivebox" : "bubble.left.and.bubble.right",
                description: Text(AppText.tr("Потяните вниз для обновления", "Pull down to refresh"))
            )
        } else {
            VStack(spacing: 10) {
                Image(systemName: isArchiveMode ? "archivebox" : "bubble.left.and.bubble.right")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text(isArchiveMode ? AppText.tr("Архив пуст", "Archive is empty") : AppText.tr("Нет чатов", "No chats"))
                    .font(.headline)
                Text(AppText.tr("Потяните вниз для обновления", "Pull down to refresh"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
    }
}

private struct ChatCardView: View {
    let chat: TgChat
    var vm: AppViewModel? = nil
    var onPremiumBadgeTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(
                    title: chat.title,
                    identifier: chat.id,
                    imagePath: chat.avatarPath,
                    size: 52,
                    isSavedMessages: chat.kind == .savedMessages
                )
                if chat.kind == .private, chat.isOnline == true {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: 1, y: 1)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    DisplayNameWithPremium(
                        name: chat.title,
                        isPremium: chat.kind == .private && chat.peerIsPremium,
                        badgeImagePath: chat.peerPremiumBadgePath,
                        font: .headline,
                        lineLimit: 1,
                        onPremiumBadgeTap: onPremiumBadgeTap
                    )

                    if chat.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if chat.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if chat.isMarkedUnread {
                        Image(systemName: "envelope.badge.fill")
                            .font(.caption2)
                            .foregroundStyle(AppColors.accent)
                    }

                    Spacer(minLength: 8)

                    if chat.unreadCount > 0 {
                        Text(unreadText(chat.unreadCount))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppColors.accent)
                            .clipShape(Capsule())
                    }
                }

                Text(previewText)
                    .font(.subheadline)
                    .foregroundStyle(chat.typingText != nil ? .green : .secondary)
                    .lineLimit(1)

                if chat.kind == .private,
                   let username = chat.peerUsername,
                   !username.isEmpty {
                    UsernameLine(
                        username: username,
                        font: .caption,
                        color: AppColors.accent,
                        vm: vm
                    )
                }

                if chat.isBlockedByMe || chat.isBlockedByPeer {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption2)
                        Text(blockStatusText(for: chat))
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                } else if let status = chat.statusText, !status.isEmpty, chat.kind != .savedMessages {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle((chat.kind == .private && (chat.isOnline ?? false)) ? .green : .secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var previewText: String {
        if let typing = AppText.typingStatus(chat.typingText) {
            return typing
        }
        if let preview = chat.lastMessagePreview, !preview.isEmpty {
            return preview
        }
        switch chat.kind {
        case .savedMessages: return AppText.tr("Сохранённые сообщения", "Saved messages")
        case .private: return AppText.tr("Личное сообщение", "Private chat")
        case .basicGroup, .supergroup: return AppText.tr("Группа", "Group")
        case .channel: return AppText.tr("Канал", "Channel")
        case .unknown: return AppText.tr("Чат", "Chat")
        }
    }

    private func unreadText(_ value: Int) -> String {
        value > 99 ? "99+" : "\(value)"
    }

    private func blockStatusText(for chat: TgChat) -> String {
        if chat.isBlockedByMe {
            return AppText.tr("Заблокирован вами", "Blocked by you")
        }
        if chat.isBlockedByPeer {
            return AppText.tr("Ограничил(а) вас", "Restricted you")
        }
        return ""
    }
}

private struct ChatRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
