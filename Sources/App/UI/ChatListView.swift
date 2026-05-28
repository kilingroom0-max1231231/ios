import SwiftUI
import UIKit

struct ChatListView: View {
    @ObservedObject var vm: AppViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            List {

                ForEach(visiblePinnedChats) { chat in
                    chatRow(chat)
                }
                .onMove { source, destination in
                    guard vm.chatSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { await vm.movePinnedChats(from: source, to: destination) }
                }

                ForEach(visibleOtherChats) { chat in
                    chatRow(chat)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppColors.screenBackground)
            .animation(.spring(response: 0.28, dampingFraction: 0.88), value: vm.filteredChats)
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int64.self) { chatId in
                ChatDetailView(vm: vm, chatId: chatId)
            }
            .overlay {
                if vm.chats.isEmpty && !vm.isBusy {
                    emptyChatsView
                }
            }
            .refreshable {
                await vm.refreshChats()
            }
            .toolbar {
                if !visiblePinnedChats.isEmpty && vm.chatSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                }
            }

            searchField
        }
    }

    private var visiblePinnedChats: [TgChat] {
        vm.filteredChats.filter(\.isPinned)
    }

    private var visibleOtherChats: [TgChat] {
        vm.filteredChats.filter { !$0.isPinned }
    }

    private func chatRow(_ chat: TgChat) -> some View {
        NavigationLink(value: chat.id) {
            ChatCardView(chat: chat)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
        .contextMenu {
            chatContextMenu(for: chat)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await vm.setChatPinned(chat.id, pinned: !chat.isPinned) }
            } label: {
                Label(chat.isPinned ? "Unpin" : "Pin", systemImage: chat.isPinned ? "pin.slash" : "pin.fill")
            }
            .tint(.orange)

            Button {
                Task {
                    if chat.unreadCount > 0 || chat.isMarkedUnread {
                        await vm.markChatRead(chat.id)
                    } else {
                        await vm.markChatUnread(chat.id)
                    }
                }
            } label: {
                Label(chat.unreadCount > 0 || chat.isMarkedUnread ? "Read" : "Unread", systemImage: chat.unreadCount > 0 || chat.isMarkedUnread ? "envelope.open" : "envelope.badge")
            }
            .tint(AppColors.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
                Label(chat.isMuted ? "Unmute" : "Mute", systemImage: chat.isMuted ? "bell.fill" : "bell.slash.fill")
            }
            .tint(.indigo)
        }
    }

    @ViewBuilder
    private func chatContextMenu(for chat: TgChat) -> some View {
        Button {
            Task { await vm.setChatPinned(chat.id, pinned: !chat.isPinned) }
        } label: {
            Label(chat.isPinned ? "Unpin Chat" : "Pin Chat", systemImage: chat.isPinned ? "pin.slash" : "pin.fill")
        }

        if chat.isMuted {
            Button {
                Task { await vm.setChatMute(chat.id, duration: .off) }
            } label: {
                Label("Unmute", systemImage: "bell.fill")
            }
        } else {
            Menu {
                Button("1 hour") {
                    Task { await vm.setChatMute(chat.id, duration: .oneHour) }
                }
                Button("8 hours") {
                    Task { await vm.setChatMute(chat.id, duration: .eightHours) }
                }
                Button("Forever") {
                    Task { await vm.setChatMute(chat.id, duration: .forever) }
                }
            } label: {
                Label("Mute", systemImage: "bell.slash.fill")
            }
        }

        Button {
            Task { await vm.markChatRead(chat.id) }
        } label: {
            Label("Mark as Read", systemImage: "envelope.open")
        }

        if chat.kind == .private || chat.kind == .savedMessages {
            Button {
                Task { await vm.markChatUnread(chat.id) }
            } label: {
                Label("Mark as Unread", systemImage: "envelope.badge")
            }
        }

        Divider()

        if chat.kind == .private || chat.kind == .savedMessages {
            Button(role: .destructive) {
                Task { await vm.clearChatHistory(chat.id) }
            } label: {
                Label("Clear History", systemImage: "eraser")
            }

            if chat.kind == .private {
                Button(role: .destructive) {
                    Task { await vm.deleteChat(chat.id) }
                } label: {
                    Label("Delete Chat", systemImage: "trash")
                }
            }
        } else if chat.kind == .channel {
            Button(role: .destructive) {
                Task { await vm.leaveChat(chat.id) }
            } label: {
                Label("Leave Channel", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } else {
            Button(role: .destructive) {
                Task { await vm.clearChatHistory(chat.id) }
            } label: {
                Label("Clear History", systemImage: "eraser")
            }
            Button(role: .destructive) {
                Task { await vm.leaveChat(chat.id) }
            } label: {
                Label("Leave Group", systemImage: "rectangle.portrait.and.arrow.right")
            }
            Button(role: .destructive) {
                Task { await vm.leaveChat(chat.id) }
            } label: {
                Label("Delete and Leave", systemImage: "trash")
            }
        }
    }

    private func deleteTitle(for chat: TgChat) -> String {
        switch chat.kind {
        case .channel:
            return "Leave"
        case .basicGroup, .supergroup:
            return "Leave"
        default:
            return "Delete"
        }
    }

    private var pullDetector: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: ChatListPullOffsetKey.self,
                    value: proxy.frame(in: .named("chat-list-scroll")).minY
                )
        }
        .frame(height: 1)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $vm.chatSearch)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !vm.chatSearch.isEmpty {
                Button {
                    vm.chatSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 360)
        .glassContainer(cornerRadius: 18)
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var emptyChatsView: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                "Нет чатов",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Потяните вниз для обновления")
            )
        } else {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Нет чатов")
                    .font(.headline)
                Text("Потяните вниз для обновления")
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(title: chat.title, identifier: chat.id, imagePath: chat.avatarPath, size: 52)
                Circle()
                    .fill((chat.isOnline ?? false) ? Color.green : Color.gray.opacity(0.75))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(chat.title)
                        .font(.headline)
                        .lineLimit(1)

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

                HStack(spacing: 6) {
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let status = chat.statusText, !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle((chat.isOnline ?? false) ? .green : .secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassContainer(cornerRadius: 18)
    }

    private var previewText: String {
        if let preview = chat.lastMessagePreview, !preview.isEmpty {
            return preview
        }
        switch chat.kind {
        case .savedMessages: return "Saved Messages"
        case .private: return "Личное сообщение"
        case .basicGroup, .supergroup: return "Группа"
        case .channel: return "Канал"
        case .unknown: return "Чат"
        }
    }

    private func iconName(for kind: ChatKind) -> String {
        switch kind {
        case .savedMessages: return "bookmark.fill"
        case .private: return "person.fill"
        case .basicGroup, .supergroup: return "person.2.fill"
        case .channel: return "megaphone.fill"
        case .unknown: return "bubble.left.fill"
        }
    }

    private func unreadText(_ value: Int) -> String {
        value > 99 ? "99+" : "\(value)"
    }
}

// Intentionally removed the "pull to reveal search" behavior.
// Search is always visible at the top.
