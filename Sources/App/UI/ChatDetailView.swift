import SwiftUI

struct ChatDetailView: View {
    @ObservedObject var vm: AppViewModel
    let chatId: Int64
    @FocusState private var isComposerFocused: Bool
    @State private var showProfile = false
    @State private var selectedAttachment: TgAttachment?

    private var title: String {
        vm.chats.first(where: { $0.id == chatId })?.title ?? "Чат"
    }

    private var selectedChat: TgChat? {
        vm.chats.first(where: { $0.id == chatId })
    }

    private var subtitle: String {
        if vm.isBusy { return "обновление..." }
        return selectedChat?.statusText ?? "был(а) недавно"
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
        .toolbar(.hidden, for: .tabBar)
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
                        Text("Не удалось загрузить профиль")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .task {
                await vm.loadProfile(chatId: chatId)
            }
        }
        .fullScreenCover(item: $selectedAttachment) { attachment in
            MediaViewerView(attachment: attachment)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.messages) { message in
                        let replyPreview = message.replyToMessageId.flatMap { replyId in
                            vm.messages.first(where: { $0.id == replyId })?.text
                        }
                        MessageBubbleView(
                            message: message,
                            incomingAvatarPath: selectedChat?.avatarPath,
                            incomingTitle: title,
                            replyPreviewText: replyPreview,
                            onOpenAttachment: { attachment in
                                selectedAttachment = attachment
                            },
                            onReply: {
                                vm.startReply(message)
                                isComposerFocused = true
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
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    vm.quoteMessage(message)
                                    isComposerFocused = true
                                } label: {
                                    Label("Цитата", systemImage: "arrowshape.turn.up.left")
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
        .background(.bar)
    }

    private var composerBar: some View {
        VStack(spacing: 8) {
            if let reply = vm.replyPreviewText(), vm.replyingToMessageId != nil {
                replyPreview(reply)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Сообщение", text: $vm.composeText, axis: .vertical)
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
        let button = Button {
            Task {
                await vm.sendMessage()
                isComposerFocused = false
            }
        } label: {
            Image(systemName: "paperplane.fill")
        }
        .clipShape(Circle())
        .controlSize(.large)
        .disabled(vm.isBusy || isComposeTextEmpty)

        if isComposeTextEmpty {
            button.buttonStyle(.bordered)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }

    private func replyPreview(_ text: String) -> some View {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewText = trimmedText.isEmpty ? "Сообщение" : trimmedText

        return HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(AppColors.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text("Ответ")
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
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassContainer(cornerRadius: 14)
    }
}
