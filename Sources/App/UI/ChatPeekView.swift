import SwiftUI

struct ChatPeekView: View {
    @ObservedObject var vm: AppViewModel
    let chatId: Int64
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var chat: TgChat? {
        vm.chats.first(where: { $0.id == chatId })
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if vm.isPeekLoading && vm.peekMessages.isEmpty {
                            ProgressView()
                                .padding(.top, 40)
                        }

                        ForEach(groupedPeekMessages) { message in
                            MessageBubbleView(
                                message: message,
                                chatKind: chat?.kind ?? .unknown
                            )
                            .id(message.id)
                            .onAppear {
                                if message.id == groupedPeekMessages.first?.id {
                                    Task { await vm.loadPeekOlderIfNeeded(chatId: chatId, triggerMessageId: message.id) }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: vm.peekMessages.count) { _ in
                    if let last = vm.peekMessages.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let last = vm.peekMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(ChatScreenBackground().ignoresSafeArea())
            .navigationTitle(chat?.title ?? AppText.tr("Чат", "Chat"))
            .navigationBarTitleDisplayMode(.inline)
            .glassNavigationBar()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(chat?.title ?? AppText.tr("Чат", "Chat"))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(AppText.tr("Просмотр без прочтения", "Preview without marking read"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppText.tr("Закрыть", "Close")) {
                        vm.closeChatPeek()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await vm.openChat(chatId: chatId) }
                        vm.closeChatPeek()
                        dismiss()
                    } label: {
                        Text(AppText.tr("Открыть", "Open"))
                    }
                }
            }
        }
        .interactiveDismissDisabled(false)
    }

    private var groupedPeekMessages: [TgMessage] {
        let items = vm.peekMessages
        var out: [TgMessage] = []
        var index = 0
        while index < items.count {
            let current = items[index]
            guard let albumId = current.mediaAlbumId, albumId != 0 else {
                out.append(current)
                index += 1
                continue
            }
            var merged = current
            var attachments = current.attachments
            var nextIndex = index + 1
            while nextIndex < items.count {
                let next = items[nextIndex]
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
                nextIndex += 1
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
            index = nextIndex
        }
        return out
    }
}
