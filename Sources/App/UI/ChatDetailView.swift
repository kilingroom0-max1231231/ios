import SwiftUI
import UIKit

struct ChatDetailView: View {
    @ObservedObject var vm: AppViewModel
    @EnvironmentObject private var swipeSettings: MessageSwipeSettingsStore
    let chatId: Int64
    @FocusState private var isComposerFocused: Bool
    @State private var showProfile = false
    @State private var mediaSelection: MediaViewerSelection?
    @State private var forwardingMessage: TgMessage?
    @State private var bottomScrollAnchorId: Int64?

    private var selectedChat: TgChat? {
        vm.chats.first(where: { $0.id == chatId })
    }

    private var title: String {
        if selectedChat?.kind == .savedMessages {
            return AppText.tr("Избранное", "Saved Messages")
        }
        return selectedChat?.title ?? AppText.tr("Чат", "Chat")
    }

    private var isSavedMessages: Bool {
        selectedChat?.kind == .savedMessages
    }

    private var isPeerTyping: Bool {
        guard let typing = selectedChat?.typingText else { return false }
        return !typing.isEmpty
    }

    private var subtitle: String {
        if isSavedMessages {
            return AppText.tr("ваши сохранённые сообщения", "your saved messages")
        }
        if selectedChat?.isBlockedByMe == true {
            return AppText.tr("Вы заблокировали", "You blocked them")
        }
        if selectedChat?.isBlockedByPeer == true {
            return AppText.tr("Ограничил(а) вас", "Restricted you")
        }
        if vm.isBusy { return AppText.tr("обновление...", "updating...") }
        if let typing = AppText.typingStatus(selectedChat?.typingText) {
            return typing
        }
        return selectedChat?.statusText ?? AppText.tr("был(а) недавно", "last seen recently")
    }

    private var subtitleColor: Color {
        if isPeerTyping { return .green }
        if selectedChat?.isOnline == true { return .green }
        return .secondary
    }

    private var canSend: Bool {
        selectedChat?.canSendMessages ?? true
    }

    var body: some View {
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        .background(ChatScreenBackground().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .transparentNavigationBar()
        .task(id: chatId) {
            vm.setChatVisible(chatId)
            await vm.selectChat(chatId)
        }
        .onDisappear {
            vm.setChatVisible(nil)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showProfile = true
                } label: {
                    HStack(spacing: 8) {
                        AvatarView(
                            title: title,
                            identifier: chatId,
                            imagePath: selectedChat?.avatarPath,
                            size: 30,
                            isSavedMessages: isSavedMessages
                        )
                        .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(subtitleColor)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 180, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .refreshable {
            await vm.refreshMessages()
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                Group {
                    if let profile = vm.chatProfile {
                        ChatProfileView(vm: vm, profile: profile)
                    } else if vm.isProfileLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text(AppText.tr("Не удалось загрузить профиль", "Failed to load profile"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .task {
                await vm.loadProfile(chatId: chatId)
            }
        }
        .fullScreenCover(item: $mediaSelection) { selection in
            MediaViewerView(attachments: selection.attachments, startIndex: selection.startIndex)
        }
        .sheet(item: $forwardingMessage) { message in
            NavigationStack {
                List {
                    ForEach(vm.chats.filter { $0.id != chatId }) { target in
                        Button {
                            Task {
                                await vm.forwardMessage(message, to: target.id)
                                forwardingMessage = nil
                            }
                        } label: {
                            HStack(spacing: 10) {
                                AvatarView(title: target.title, identifier: target.id, imagePath: target.avatarPath, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.title)
                                        .font(.body)
                                    if let status = target.statusText, !status.isEmpty {
                                        Text(status)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(target.canSendMessages == false)
                    }
                }
                .navigationTitle(AppText.tr("Переслать в...", "Forward to..."))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppText.tr("Закрыть", "Close")) {
                            forwardingMessage = nil
                        }
                    }
                }
            }
        }
    }

    private var mediaAttachments: [TgAttachment] {
        vm.messages.flatMap(\.attachments)
    }

    private struct MediaViewerSelection: Identifiable {
        let id = UUID()
        let attachments: [TgAttachment]
        let startIndex: Int
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groupedMessages) { message in
                        let replyPreview = message.replyToMessageId.flatMap { replyId in
                            replyQuoteText(for: replyId)
                        }
                        SwipeableMessageRow(actions: swipeActions(for: message)) {
                            MessageBubbleView(
                                message: message,
                                chatKind: selectedChat?.kind ?? .unknown,
                                peerAvatarPath: selectedChat?.avatarPath,
                                peerTitle: selectedChat?.title,
                                replyPreviewText: replyPreview,
                                onOpenAttachment: { attachment in
                                    let attachments = mediaAttachments
                                    if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
                                        mediaSelection = MediaViewerSelection(attachments: attachments, startIndex: idx)
                                    } else {
                                        mediaSelection = MediaViewerSelection(attachments: [attachment], startIndex: 0)
                                    }
                                },
                                onReply: canSend ? {
                                    vm.startReply(message)
                                    isComposerFocused = true
                                } : nil,
                                onForward: {
                                    forwardingMessage = message
                                },
                                onEdit: {
                                    vm.startEditing(message)
                                    isComposerFocused = true
                                },
                                onDelete: { revoke in
                                    Task { await vm.deleteMyMessage(message, revoke: revoke) }
                                }
                            )
                        }
                        .id(message.id)
                        .onAppear {
                            if message.id == groupedMessages.first?.id {
                                Task { await vm.loadOlderMessagesIfNeeded(triggerMessageId: message.id) }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
        }
        .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        if value.translation.height > 18 {
                            isComposerFocused = false
                        }
                    }
            )
            .onChange(of: vm.messages.last?.id) { newId in
                bottomScrollAnchorId = newId ?? groupedMessages.last?.id
            }
            .onChange(of: bottomScrollAnchorId) { anchorId in
                guard let anchorId else { return }
                scrollToBottom(proxy: proxy, anchorId: anchorId, animated: true)
            }
            .onChange(of: isComposerFocused) { focused in
                if focused, let anchorId = bottomScrollAnchorId {
                    scrollToBottom(proxy: proxy, anchorId: anchorId, animated: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                guard let anchorId = bottomScrollAnchorId else { return }
                scrollToBottom(proxy: proxy, anchorId: anchorId, animated: true)
            }
            .onAppear {
                bottomScrollAnchorId = groupedMessages.last?.id
                if let anchorId = bottomScrollAnchorId {
                    scrollToBottom(proxy: proxy, anchorId: anchorId, animated: false)
                }
            }
        }
    }

    private func swipeActions(for message: TgMessage) -> [MessageSwipeActionButton] {
        swipeSettings.enabledOrderedActions.compactMap { action in
            switch action {
            case .reply:
                guard canSend else { return nil }
                return MessageSwipeActionButton(
                    id: action.rawValue,
                    title: action.title,
                    systemImage: action.systemImage,
                    color: AppColors.accent
                ) {
                    vm.startReply(message)
                    isComposerFocused = true
                }
            case .forward:
                return MessageSwipeActionButton(
                    id: action.rawValue,
                    title: action.title,
                    systemImage: action.systemImage,
                    color: .orange
                ) {
                    forwardingMessage = message
                }
            case .quote:
                guard canSend else { return nil }
                return MessageSwipeActionButton(
                    id: action.rawValue,
                    title: action.title,
                    systemImage: action.systemImage,
                    color: .teal
                ) {
                    vm.quoteMessage(message)
                    isComposerFocused = true
                }
            case .pin:
                guard canPinMessages else { return nil }
                return MessageSwipeActionButton(
                    id: action.rawValue,
                    title: action.title,
                    systemImage: action.systemImage,
                    color: .indigo
                ) {
                    Task { await vm.pinMessage(message) }
                }
            case .delete:
                guard message.outgoing else { return nil }
                return MessageSwipeActionButton(
                    id: action.rawValue,
                    title: action.title,
                    systemImage: action.systemImage,
                    color: .red
                ) {
                    Task { await vm.deleteMyMessage(message, revoke: true) }
                }
            }
        }
    }

    private var canPinMessages: Bool {
        switch selectedChat?.kind {
        case .basicGroup, .supergroup, .channel:
            return true
        default:
            return false
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, anchorId: Int64, animated: Bool) {
        let scroll = {
            proxy.scrollTo(anchorId, anchor: .bottom)
        }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.22), scroll)
            } else {
                scroll()
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if !canSend, let reason = selectedChat?.sendRestrictionText {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                composerBar
            }
        }
        .background(Color.clear)
    }

    private var composerBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                composerSideButton(systemName: "paperclip") {
                    // Attachment picker — later
                }
                .opacity(canSend ? 1 : 0.4)
                .disabled(!canSend)

                messageInputIsland

                if vm.editingMessageId != nil {
                    composerSideButton(systemName: "xmark") {
                        vm.cancelEditing()
                        isComposerFocused = false
                    }
                    .disabled(vm.isBusy)
                    sendIslandButton
                } else if isComposeTextEmpty {
                    composerSideButton(systemName: "mic.fill") {
                        // Voice message — later
                    }
                    .opacity(canSend ? 1 : 0.4)
                    .disabled(!canSend)
                } else {
                    sendIslandButton
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var messageInputIsland: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reply = vm.replyPreviewText(), vm.replyingToMessageId != nil {
                replyPreview(reply)
                Divider()
                    .padding(.horizontal, 12)
            }

            TextField(AppText.tr("Сообщение", "Message"), text: $vm.composeText, axis: .vertical)
                .lineLimit(1...6)
                .focused($isComposerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .disabled(!canSend)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassContainer(cornerRadius: 22)
    }

    private func composerSideButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .composerIslandButton()
    }

    private var isComposeTextEmpty: Bool {
        vm.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendIslandButton: some View {
        Button {
            Task {
                await vm.sendMessage()
            }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .background(AppColors.accent, in: Circle())
        .disabled(vm.isBusy || isComposeTextEmpty || !canSend)
        .opacity(vm.isBusy || !canSend ? 0.6 : 1)
    }

    private func replyQuoteText(for replyId: Int64) -> String? {
        guard let replied = vm.messages.first(where: { $0.id == replyId }) else { return nil }
        let body = replied.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = replied.senderName, !name.isEmpty {
            if body.isEmpty {
                return name
            }
            return "\(name): \(body)"
        }
        if !body.isEmpty {
            return body
        }
        if !replied.attachments.isEmpty {
            return AppText.tr("Медиа", "Media")
        }
        return nil
    }

    private func replyPreview(_ text: String) -> some View {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewText = trimmedText.isEmpty ? AppText.tr("Сообщение", "Message") : trimmedText

        return HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(AppColors.accent)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(AppText.tr("Ответ", "Reply"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                vm.cancelReply()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groupedMessages: [TgMessage] {
        // Merge album messages (TDLib `media_album_id`) into one bubble.
        let items = vm.visibleMessages
        var out: [TgMessage] = []
        var i = 0
        while i < items.count {
            let current = items[i]
            guard let albumId = current.mediaAlbumId, albumId != 0 else {
                out.append(current)
                i += 1
                continue
            }

            var merged = current
            var attachments = current.attachments
            var j = i + 1
            while j < items.count {
                let next = items[j]
                guard next.mediaAlbumId == albumId, next.outgoing == current.outgoing else { break }
                attachments.append(contentsOf: next.attachments)
                if merged.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !next.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    merged = TgMessage(
                        id: merged.id,
                        chatId: merged.chatId,
                        text: next.text,
                        outgoing: merged.outgoing,
                        createdAt: merged.createdAt,
                        isEdited: merged.isEdited || next.isEdited,
                        replyToMessageId: merged.replyToMessageId ?? next.replyToMessageId,
                        isDeleted: merged.isDeleted || next.isDeleted,
                        isReadByPeer: merged.isReadByPeer || next.isReadByPeer,
                        attachments: attachments,
                        mediaAlbumId: albumId,
                        forwardedFrom: merged.forwardedFrom ?? next.forwardedFrom,
                        senderUserId: merged.senderUserId ?? next.senderUserId,
                        senderName: merged.senderName ?? next.senderName,
                        senderAvatarPath: merged.senderAvatarPath ?? next.senderAvatarPath,
                        authorSignature: merged.authorSignature ?? next.authorSignature,
                        viewCount: max(merged.viewCount ?? 0, next.viewCount ?? 0)
                    )
                }
                j += 1
            }

            if merged.attachments.count != attachments.count {
                merged = TgMessage(
                    id: merged.id,
                    chatId: merged.chatId,
                    text: merged.text,
                    outgoing: merged.outgoing,
                    createdAt: merged.createdAt,
                    isEdited: merged.isEdited,
                    replyToMessageId: merged.replyToMessageId,
                    isDeleted: merged.isDeleted,
                    isReadByPeer: merged.isReadByPeer,
                    attachments: attachments,
                    mediaAlbumId: albumId,
                    forwardedFrom: merged.forwardedFrom,
                    senderUserId: merged.senderUserId,
                    senderName: merged.senderName,
                    senderAvatarPath: merged.senderAvatarPath,
                    authorSignature: merged.authorSignature,
                    viewCount: merged.viewCount
                )
            }

            out.append(merged)
            i = j
        }
        return out
    }
}
