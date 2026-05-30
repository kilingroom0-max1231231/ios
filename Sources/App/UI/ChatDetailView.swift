import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers


struct ChatDetailView: View {
    @ObservedObject var vm: AppViewModel
    @EnvironmentObject private var swipeSettings: MessageSwipeSettingsStore
    @EnvironmentObject private var appSettings: AppSettingsStore
    let chatId: Int64
    @FocusState private var isComposerFocused: Bool
    @State private var showProfile = false
    @State private var mediaSelection: MediaViewerSelection?
    @State private var forwardingMessage: TgMessage?
    @State private var didInitialScrollToBottom = false
    @State private var isPinnedToBottom = true
    @State private var premiumUpsellContext: PremiumUpsellContext?
    @State private var showAttachmentMenu = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var showStickerPicker = false
    @State private var showVideoNoteCamera = false
    @State private var messageActionTarget: MessageActionTarget?
    @State private var messageBubbleFrames: [Int64: CGRect] = [:]
    @State private var pendingReactionRemoval: PendingReactionRemoval?
    @StateObject private var voiceRecorder = VoiceNoteRecorder()
    @State private var isMicPressing = false


    private enum ChatScrollAnchor {
        static let bottom = "chat-scroll-bottom"
    }

    private var selectedChat: TgChat? {
        vm.chat(for: chatId)
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
        if let status = selectedChat?.statusText, !status.isEmpty {
            return status
        }
        switch selectedChat?.kind {
        case .channel:
            return AppText.tr("канал", "channel")
        case .supergroup, .basicGroup:
            return AppText.tr("группа", "group")
        default:
            return ""
        }
    }

    private var subtitleColor: Color {
        if isPeerTyping { return .green }
        if selectedChat?.kind == .private, selectedChat?.isOnline == true { return .green }
        return .secondary
    }

    private var canSend: Bool {
        selectedChat?.canSendMessages == true
    }

    private var canReact: Bool {
        if let value = selectedChat?.canAddReactions {
            return value
        }
        if selectedChat?.isBlockedByMe == true || selectedChat?.isBlockedByPeer == true {
            return false
        }
        switch selectedChat?.kind {
        case .channel, .supergroup, .basicGroup:
            return true
        case .private:
            return selectedChat?.canSendMessages != false
        default:
            return true
        }
    }

    private var sendRestrictionBannerText: String {
        if let reason = selectedChat?.sendRestrictionText, !reason.isEmpty {
            return reason
        }
        if selectedChat?.kind == .channel {
            return AppText.tr(
                "Это канал — писать могут только администраторы",
                "Only admins can post in this channel"
            )
        }
        return AppText.tr("Запрещено отправлять сообщения", "Sending messages is not allowed")
    }

    var body: some View {
        ZStack {
            chatScreen
            messageActionsOverlayLayer
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: messageActionTarget?.id)
        .handleTelegramLinks(vm)
    }

    private var chatScreen: some View {
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
                    .opacity(messageActionTarget == nil ? 1 : 0)
                    .allowsHitTesting(messageActionTarget == nil)
            }
        .background(ChatScreenBackground().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(messageActionTarget == nil ? .visible : .hidden, for: .navigationBar)
        .transparentNavigationBar()
        .task(id: chatId) {
            didInitialScrollToBottom = false
            isPinnedToBottom = true
            vm.setChatVisible(chatId)
            await vm.selectChat(chatId)
        }
        .onDisappear {
            vm.setChatVisible(nil)
            didInitialScrollToBottom = false
            isPinnedToBottom = true
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
                            DisplayNameWithPremium(
                                name: title,
                                isPremium: selectedChat?.kind == .private && (selectedChat?.peerIsPremium ?? false),
                                badgeImagePath: selectedChat?.peerPremiumBadgePath,
                                font: .subheadline.weight(.semibold),
                                lineLimit: 1,
                                onPremiumBadgeTap: selectedChat?.kind == .private && (selectedChat?.peerIsPremium ?? false)
                                    ? { vm.presentPremiumUpsell(for: title, badgePath: selectedChat?.peerPremiumBadgePath) }
                                    : nil
                            )
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
        .sheet(item: $premiumUpsellContext) { context in
            PremiumUpsellSheet(context: context)
        }
        .sheet(isPresented: $showAttachmentMenu) {
            ChatAttachmentMenu(
                onPhoto: {
                    showAttachmentMenu = false
                    showPhotoPicker = true
                },
                onFile: {
                    showAttachmentMenu = false
                    showDocumentPicker = true
                },
                onSticker: {
                    showAttachmentMenu = false
                    showStickerPicker = true
                }
            )
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker { data in
                Task {
                    do {
                        let url = try MediaFileImporter.persistPhotoData(data)
                        await vm.sendOutgoingMedia(.photo(url))
                    } catch {
                        vm.status = error.localizedDescription
                    }
                }
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in
                Task {
                    do {
                        let persisted = try MediaFileImporter.persistPickedFile(url)
                        let name = url.lastPathComponent
                        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                        await vm.sendOutgoingMedia(.document(persisted, fileName: name, mimeType: mime))
                    } catch {
                        vm.status = error.localizedDescription
                    }
                }
            }
        }
        .sheet(isPresented: $showStickerPicker) {
            StickerPickerView(vm: vm) { sticker in
                Task { await vm.sendSticker(sticker) }
            }
        }
        .fullScreenCover(isPresented: $showVideoNoteCamera) {
            VideoNoteCameraPicker { url in
                Task {
                    do {
                        let asset = AVURLAsset(url: url)
                        let duration = max(1, Int(CMTimeGetSeconds(asset.duration)))
                        let persisted = try MediaFileImporter.persistPickedFile(url)
                        await vm.sendOutgoingMedia(.videoNote(persisted, duration: duration))
                    } catch {
                        vm.status = error.localizedDescription
                    }
                }
            }
            .ignoresSafeArea()
        }
        .alert(item: $pendingReactionRemoval) { pending in
            Alert(
                title: Text(AppText.tr("Снять реакцию?", "Remove reaction?")),
                message: Text("\(pending.emoji)"),
                primaryButton: .destructive(
                    Text(AppText.tr("Снять", "Remove"))
                ) {
                    let live = liveMessage(pending.message)
                    Task { await vm.toggleReaction(on: live, emoji: pending.emoji) }
                },
                secondaryButton: .cancel()
            )
        }
        .onPreferenceChange(MessageBubbleFramePreferenceKey.self) { messageBubbleFrames = $0 }
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

    @ViewBuilder
    private var messageActionsOverlayLayer: some View {
        if let target = messageActionTarget {
            let replyMap = replyPreviewMap(from: vm.messages)
            MessageActionsOverlay(
                vm: vm,
                target: target,
                messageFrame: messageBubbleFrames[target.message.id],
                chatKind: selectedChat?.kind ?? .unknown,
                peerAvatarPath: selectedChat?.avatarPath,
                peerTitle: selectedChat?.title,
                replyPreviewText: target.message.replyToMessageId.flatMap { replyMap[$0] },
                canSend: canSend,
                canReact: canReact,
                canEdit: target.message.outgoing
                    && !target.message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                captionText: captionForMessage(target.message),
                onDismiss: { messageActionTarget = nil },
                onReply: {
                    vm.startReply(target.message)
                    isComposerFocused = true
                },
                onForward: {
                    forwardingMessage = target.message
                },
                onEdit: {
                    vm.startEditing(target.message)
                    isComposerFocused = true
                },
                onDelete: { revoke in
                    Task { await vm.deleteMyMessage(target.message, revoke: revoke) }
                },
                onCopy: {
                    if let text = captionForMessage(target.message) {
                        UIPasteboard.general.string = text
                    }
                }
            )
            .transition(.opacity)
            .zIndex(300)
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

    private enum ChatRow: Identifiable {
        case date(Date)
        case message(TgMessage)

        var id: String {
            switch self {
            case .date(let date):
                return "d-\(Int(date.timeIntervalSince1970))"
            case .message(let message):
                return "m-\(message.id)"
            }
        }
    }

    private var messageList: some View {
        let grouped = groupedMessages
        let rows = chatRows(from: grouped)
        let replyPreviews = replyPreviewMap(from: vm.messages)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .date(let date):
                            dateSeparator(date)
                                .transition(.opacity)
                        case .message(let message):
                            let replyPreview = message.replyToMessageId.flatMap { replyPreviews[$0] }
                            messageRow(for: message, replyPreview: replyPreview)
                                .id(message.id)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )
                                .onAppear {
                                    if message.id == grouped.first?.id {
                                        Task { await vm.loadOlderMessagesIfNeeded(triggerMessageId: message.id) }
                                    }
                                }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(ChatScrollAnchor.bottom)
                        .onAppear { isPinnedToBottom = true }
                        .onDisappear {
                            if didInitialScrollToBottom {
                                isPinnedToBottom = false
                            }
                        }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
                .animation(.spring(response: 0.32, dampingFraction: 0.9), value: grouped.last?.id)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(messageActionTarget != nil)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        if value.translation.height > 14 {
                            isPinnedToBottom = false
                        }
                        if value.translation.height > 18 {
                            isComposerFocused = false
                        }
                    }
            )
            .onChange(of: grouped.last?.id) { _ in
                let force = grouped.last?.outgoing == true
                requestScrollToBottom(proxy: proxy, animated: true, force: force)
            }
            .onChange(of: vm.chatMediaGeneration) { _ in
                requestScrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: isComposerFocused) { focused in
                if focused {
                    isPinnedToBottom = true
                    requestScrollToBottom(proxy: proxy, animated: true, force: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                guard isPinnedToBottom else { return }
                requestScrollToBottom(proxy: proxy, animated: true, force: true)
            }
            .onAppear {
                requestScrollToBottom(proxy: proxy, animated: false, force: true)
            }
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom, !grouped.isEmpty {
                    scrollToBottomButton {
                        isPinnedToBottom = true
                        requestScrollToBottom(proxy: proxy, animated: true, force: true)
                    }
                    .padding(.trailing, 14)
                    .padding(.bottom, 10)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isPinnedToBottom)
        }
    }

    private func chatRows(from groupedMessages: [TgMessage]) -> [ChatRow] {
        var rows: [ChatRow] = []
        var lastDay: Date?
        let calendar = Calendar.current
        for message in groupedMessages {
            let day = calendar.startOfDay(for: message.createdAt)
            if lastDay == nil || day != lastDay {
                rows.append(.date(day))
                lastDay = day
            }
            rows.append(.message(message))
        }
        return rows
    }

    private func dateSeparator(_ date: Date) -> some View {
        Text(dateTitle(date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private func dateTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return AppText.tr("Сегодня", "Today")
        }
        if calendar.isDateInYesterday(date) {
            return AppText.tr("Вчера", "Yesterday")
        }
        return date.formatted(
            .dateTime
                .locale(Locale(identifier: AppText.isRussian ? "ru_RU" : "en_US_POSIX"))
                .day()
                .month(.wide)
        )
    }

    @ViewBuilder
    private func messageRow(for message: TgMessage, replyPreview: String?) -> some View {
        Group {
            if isServiceMessage(message) {
                Text(message.text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 4)
            } else {
                let bubble = MessageBubbleView(
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
                    onPremiumSticker: { attachment in
                        premiumUpsellContext = .premiumSticker(attachment: attachment)
                    },
                    onReply: canSend ? {
                        vm.startReply(message)
                        isComposerFocused = true
                    } : nil,
                    onLongPress: {
                        messageActionTarget = MessageActionTarget(message: message)
                    },
                    onDoubleTap: canReact && appSettings.enableDoubleTapQuickReaction ? {
                        requestToggleReaction(
                            on: message,
                            emoji: appSettings.doubleTapQuickReactionEmoji
                        )
                    } : nil,
                    onReactionTap: canReact ? { reaction in
                        requestToggleReaction(on: message, reaction: reaction)
                    } : nil,
                    onForwardOriginTap: { origin in
                        Task { await vm.openForwardOrigin(origin) }
                    },
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

                let row = Group {
                    let swipe = swipeSettings.primaryAction
                    if swipe != .off,
                       let handler = swipeActionHandler(for: message, action: swipe) {
                        SwipeableMessageRow(
                            actionIcon: swipe.systemImage,
                            actionColor: swipe.accentColor,
                            onSwipe: handler
                        ) {
                            bubble
                        }
                    } else {
                        bubble
                    }
                }
                .opacity(messageActionTarget?.id == message.id ? 0 : 1)
                .reportMessageBubbleFrame(messageId: message.id)

                row
            }
        }
    }

    private func isServiceMessage(_ message: TgMessage) -> Bool {
        message.isService
    }

    private func swipeActionHandler(for message: TgMessage, action: MessageSwipeAction) -> (() -> Void)? {
        switch action {
        case .off:
            return nil
        case .reply:
            guard canSend else { return nil }
            return {
                vm.startReply(message)
                isComposerFocused = true
            }
        case .forward:
            return { forwardingMessage = message }
        case .quote:
            guard canSend else { return nil }
            return {
                vm.quoteMessage(message)
                isComposerFocused = true
            }
        case .pin:
            guard canPinMessages else { return nil }
            return { Task { await vm.pinMessage(message) } }
        case .delete:
            guard message.outgoing else { return nil }
            return { Task { await vm.deleteMyMessage(message, revoke: true) } }
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

    private func requestScrollToBottom(proxy: ScrollViewProxy, animated: Bool, force: Bool = false) {
        guard !groupedMessages.isEmpty else { return }
        guard force || isPinnedToBottom || !didInitialScrollToBottom else { return }

        let scroll = {
            proxy.scrollTo(ChatScrollAnchor.bottom, anchor: .bottom)
        }

        DispatchQueue.main.async {
            if animated {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    scroll()
                }
            } else {
                scroll()
            }

            if !didInitialScrollToBottom {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    scroll()
                    didInitialScrollToBottom = true
                }
            }
        }
    }

    private func scrollToBottomButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppText.tr("Вниз", "Scroll down"))
    }

    private var showBotStartButton: Bool {
        vm.selectedChatPeerIsBot
            && vm.messages.isEmpty
            && !vm.isBusy
            && canSend
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if showBotStartButton {
                botStartButton
            } else if !canSend {
                Text(sendRestrictionBannerText)
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

    private var botStartButton: some View {
        Button {
            Task { await vm.sendBotStart() }
        } label: {
            Text(AppText.tr("ЗАПУСТИТЬ", "START"))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var composerBar: some View {
        VStack(spacing: 8) {
            if voiceRecorder.isRecording {
                VoiceRecordingOverlay(
                    recorder: voiceRecorder,
                    onCancel: {
                        voiceRecorder.cancel()
                    },
                    onSend: {
                        Task {
                            guard let result = voiceRecorder.stop() else { return }
                            await vm.sendOutgoingMedia(.voice(result.url, duration: result.duration, waveform: result.waveform))
                        }
                    }
                )
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    composerSideButton(systemName: "paperclip") {
                        showAttachmentMenu = true
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
                        micButton
                    } else {
                        sendIslandButton
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var micButton: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .opacity(canSend ? 1 : 0.4)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard canSend, !voiceRecorder.isRecording else { return }
                        if !isMicPressing {
                            isMicPressing = true
                            Task {
                                guard await voiceRecorder.requestPermission() else {
                                    vm.status = AppText.tr("Нет доступа к микрофону", "Microphone access denied")
                                    return
                                }
                                do {
                                    try voiceRecorder.start()
                                } catch {
                                    vm.status = error.localizedDescription
                                }
                            }
                        }
                    }
                    .onEnded { value in
                        isMicPressing = false
                        guard voiceRecorder.isRecording else { return }
                        if value.translation.height < -80 {
                            showVideoNoteCamera = true
                            voiceRecorder.cancel()
                        } else if let result = voiceRecorder.stop() {
                            Task {
                                await vm.sendOutgoingMedia(.voice(result.url, duration: result.duration, waveform: result.waveform))
                            }
                        } else {
                            voiceRecorder.cancel()
                        }
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    guard canSend else { return }
                    showVideoNoteCamera = true
                }
            )
            .disabled(!canSend)
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

    private func replyQuoteText(for replied: TgMessage) -> String? {
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

    private func captionForMessage(_ message: TgMessage) -> String? {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return message.text }
        return nil
    }

    private func replyPreviewMap(from messages: [TgMessage]) -> [Int64: String] {
        var map: [Int64: String] = [:]
        map.reserveCapacity(messages.count)
        for message in messages {
            if let preview = replyQuoteText(for: message) {
                map[message.id] = preview
            }
        }
        return map
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
                        forwardOrigin: merged.forwardOrigin ?? next.forwardOrigin,
                        senderUserId: merged.senderUserId ?? next.senderUserId,
                        senderName: merged.senderName ?? next.senderName,
                        senderAvatarPath: merged.senderAvatarPath ?? next.senderAvatarPath,
                        authorSignature: merged.authorSignature ?? next.authorSignature,
                        viewCount: max(merged.viewCount ?? 0, next.viewCount ?? 0),
                        reactions: merged.reactions.isEmpty ? next.reactions : merged.reactions
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
                    forwardOrigin: merged.forwardOrigin,
                    senderUserId: merged.senderUserId,
                    senderName: merged.senderName,
                    senderAvatarPath: merged.senderAvatarPath,
                    authorSignature: merged.authorSignature,
                    viewCount: merged.viewCount,
                    reactions: merged.reactions
                )
            }

            out.append(merged)
            i = j
        }
        return out
    }

    private func liveMessage(_ message: TgMessage) -> TgMessage {
        vm.messages.first(where: { $0.id == message.id }) ?? message
    }

    private func requestToggleReaction(on message: TgMessage, emoji: String) {
        let live = liveMessage(message)
        if live.reactions.contains(where: { $0.emoji == emoji && $0.isChosen }),
           appSettings.confirmReactionRemove {
            pendingReactionRemoval = PendingReactionRemoval(message: live, emoji: emoji)
            return
        }
        Task { await vm.toggleReaction(on: live, emoji: emoji) }
    }

    private func requestToggleReaction(on message: TgMessage, reaction: TgMessageReaction) {
        if reaction.isChosen, appSettings.confirmReactionRemove {
            pendingReactionRemoval = PendingReactionRemoval(
                message: liveMessage(message),
                emoji: reaction.emoji
            )
            return
        }
        Task { await vm.toggleReaction(on: liveMessage(message), reaction: reaction) }
    }
}

private struct PendingReactionRemoval: Identifiable {
    let id = UUID()
    let message: TgMessage
    let emoji: String
}
