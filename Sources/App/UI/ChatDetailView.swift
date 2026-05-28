import SwiftUI

struct ChatDetailView: View {
    @ObservedObject var vm: AppViewModel
    let chatId: Int64
    @FocusState private var isComposerFocused: Bool
    @State private var showProfile = false
    @State private var mediaSelection: MediaViewerSelection?
    @State private var forwardingMessage: TgMessage?

    private var title: String {
        vm.chats.first(where: { $0.id == chatId })?.title ?? AppText.tr("Чат", "Chat")
    }

    private var selectedChat: TgChat? {
        vm.chats.first(where: { $0.id == chatId })
    }

    private var subtitle: String {
        if vm.isBusy { return AppText.tr("обновление...", "updating...") }
        return selectedChat?.statusText ?? AppText.tr("был(а) недавно", "last seen recently")
    }

    private var canSend: Bool {
        selectedChat?.canSendMessages ?? true
    }

    var body: some View {
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        .background(AppColors.chatBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await vm.selectChat(chatId) }
        }
        .task(id: chatId) {
            // Always load immediately when entering/switching chat
            await vm.selectChat(chatId)
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
                            size: 30
                        )
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
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
                            vm.messages.first(where: { $0.id == replyId })?.text
                        }
                        MessageBubbleView(
                            message: message,
                            incomingAvatarPath: selectedChat?.avatarPath,
                            incomingTitle: title,
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
                            .id(message.id)
                            .onAppear {
                                if message.id == groupedMessages.first?.id {
                                    Task { await vm.loadOlderMessagesIfNeeded(triggerMessageId: message.id) }
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    vm.quoteMessage(message)
                                    isComposerFocused = true
                                } label: {
                                    Label(AppText.tr("Цитата", "Quote"), systemImage: "arrowshape.turn.up.left")
                                }
                                .tint(AppColors.accent)
                            }
                    }
                }
                .padding(.vertical, 8)
        }
        .background(AppColors.chatBackground)
        .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        if value.translation.height > 18 {
                            isComposerFocused = false
                        }
                    }
            )
            .onChange(of: vm.messages.count) { _ in
                if let last = vm.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let last = vm.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()

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
        .background(AppColors.composerBackground.ignoresSafeArea(edges: .bottom))
    }

    private var composerBar: some View {
        VStack(spacing: 8) {
            if let reply = vm.replyPreviewText(), vm.replyingToMessageId != nil {
                replyPreview(reply)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(AppText.tr("Сообщение", "Message"), text: $vm.composeText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .glassField()

                if vm.editingMessageId != nil {
                    Button {
                        vm.cancelEditing()
                        isComposerFocused = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .controlSize(.large)
                    .disabled(vm.isBusy)
                }

                sendButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var isComposeTextEmpty: Bool {
        vm.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var sendButton: some View {
        Button {
            Task {
                await vm.sendMessage()
                isComposerFocused = false
            }
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(isComposeTextEmpty ? Color.secondary.opacity(0.35) : AppColors.accent)
                )
        }
        .buttonStyle(.plain)
        .disabled(vm.isBusy || isComposeTextEmpty)
        .opacity(vm.isBusy || isComposeTextEmpty ? 0.75 : 1)
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 320, alignment: .leading)
        .background(AppColors.composerBackground.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groupedMessages: [TgMessage] {
        // Merge album messages (TDLib `media_album_id`) into one bubble.
        let items = vm.messages
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
                        attachments: attachments,
                        mediaAlbumId: albumId,
                        forwardedFrom: merged.forwardedFrom ?? next.forwardedFrom
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
                    attachments: attachments,
                    mediaAlbumId: albumId,
                    forwardedFrom: merged.forwardedFrom
                )
            }

            out.append(merged)
            i = j
        }
        return out
    }
}
