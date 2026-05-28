import Foundation
import Combine
import Security
import UIKit

@MainActor
final class AppViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case setup
        case login
        case main
    }

    @Published var phase: Phase = .loading
    @Published var apiIdText = ""
    @Published var apiHash = ""
    @Published var phone = ""
    @Published var code = ""
    @Published var password = ""

    @Published var chats: [TgChat] = []
    @Published var selectedChatId: Int64?
    @Published var visibleChatId: Int64?
    @Published var messages: [TgMessage] = []
    @Published var incomingToast: IncomingMessageToast?
    @Published var privacySettings: [UserPrivacySettingValue] = UserPrivacySettingKind.allCases.map {
        UserPrivacySettingValue(kind: $0, visibility: .contacts)
    }
    @Published var isPrivacyLoading = false
    @Published var globalSearchScope: GlobalSearchScope = .myChats
    @Published var globalSearchQuery = ""
    @Published var globalSearchChats: [TgChat] = []
    @Published var globalSearchMessageHits: [GlobalSearchMessageHit] = []
    @Published var isGlobalSearching = false
    @Published var me: TgUser?
    @Published var composeText = ""
    @Published var editingMessageId: Int64?
    @Published var replyingToMessageId: Int64?
    @Published var chatProfile: ChatProfile?
    @Published var chatMembers: [ChatMember] = []
    @Published var chatMediaMessages: [TgMessage] = []
    @Published var isProfileLoading = false
    @Published var isProfileDetailsLoading = false
    @Published var chatSearch = ""
    @Published var status = ""
    @Published var authState: AuthState = .waitPhone
    @Published var isBusy = false
    @Published var bootstrapError: String?
    @Published var navigationTargetChatId: Int64?
    @Published var mainTabIndex = 0
    @Published var peekChatId: Int64?
    @Published var peekMessages: [TgMessage] = []
    @Published var isPeekLoading = false

    private var repository: TelegramRepository?
    private var mediaDownloadsInProgress: Set<Int64> = []
    private var typingClearTasks: [Int64: Task<Void, Never>] = [:]
    private var profileLoadTask: Task<Void, Never>?
    private var isTdlibConfigured = false
    private let credentials = ApiCredentialsStore()
    private var isLoadingOlderMessages = false
    private var isLoadingPeekOlder = false
    private var toastDismissTask: Task<Void, Never>?

    var filteredChats: [TgChat] {
        let query = chatSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chats }
        return chats.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.lastMessagePreview?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selectedChat: TgChat? {
        guard let selectedChatId else { return nil }
        return chats.first(where: { $0.id == selectedChatId })
    }

    func start() async {
        phase = .loading
        bootstrapError = nil

        do {
            let repo = try TelegramRepository.bootstrap()
            repository = repo
            wireRepository(repo)

            if let saved = credentials.load() {
                apiIdText = String(saved.apiId)
                apiHash = saved.apiHash
                await connect(saveCredentials: false)
            } else {
                phase = .setup
                status = "Введите API ID и API Hash с my.telegram.org"
            }
        } catch {
            bootstrapError = error.localizedDescription
            phase = .setup
            status = "TDLib недоступен: \(error.localizedDescription)"
        }
    }

    func saveAndConnect() async {
        guard let credentials = normalizedApiCredentials() else {
            status = "Укажите корректные api_id и api_hash (без пробелов и лишних символов)"
            return
        }
        apiIdText = String(credentials.apiId)
        apiHash = credentials.apiHash
        self.credentials.save(apiId: credentials.apiId, apiHash: credentials.apiHash)

        if isTdlibConfigured, let repository {
            authState = repository.authState()
            await applyPhase(for: authState)
            return
        }

        await recreateRepository()
        await connect(saveCredentials: false)
    }

    func connect(saveCredentials: Bool) async {
        guard let repository else {
            status = "Клиент не инициализирован"
            phase = .setup
            return
        }

        guard let credentials = normalizedApiCredentials() else {
            status = "Укажите api_id и api_hash"
            phase = .setup
            return
        }
        let apiId = credentials.apiId
        let apiHash = credentials.apiHash
        apiIdText = String(apiId)
        self.apiHash = apiHash

        if saveCredentials {
            self.credentials.save(apiId: apiId, apiHash: apiHash)
        }

        isBusy = true
        defer { isBusy = false }

        do {
            if !isTdlibConfigured {
            try await repository.setup(apiId: apiId, apiHash: apiHash)
                isTdlibConfigured = true
            }
            authState = repository.authState()
            await applyPhase(for: authState)
        } catch {
            let message = error.localizedDescription
            let upper = message.uppercased()
            if upper.contains("API_ID_INVALID") || upper.contains("APP_ID_INVALID") {
                status = "Telegram отклоняет api_id/api_hash. Проверь на my.telegram.org -> API development tools, что это App api_id и App api_hash из одной пары."
            } else {
                status = message
            }
            phase = .setup
        }
    }

    func submitAuth() async {
        guard let repository else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            switch authState {
            case .waitPhone:
                let normalized = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    status = "Введите номер телефона"
                    return
                }
                try await repository.submitPhone(normalized)
            case .waitCode:
                let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else {
                    status = "Введите код из Telegram"
                    return
                }
                try await repository.submitCode(normalized)
            case .waitPassword:
                guard !password.isEmpty else {
                    status = "Введите пароль 2FA"
                    return
                }
                try await repository.submitPassword(password)
            case .ready:
                break
            }

            authState = repository.authState()
            await applyPhase(for: authState)
        } catch {
            status = error.localizedDescription
        }
    }

    func signOut() {
        credentials.clear()
        apiIdText = ""
        apiHash = ""
        phone = ""
        code = ""
        password = ""
        chats = []
        messages = []
        selectedChatId = nil
        authState = .waitPhone
        repository = nil
        isTdlibConfigured = false
        bootstrapError = nil
        phase = .setup
        status = "Войдите снова — укажите API данные"
        Task { await start() }
    }

    func refreshChats() async {
        guard let repository, authState == .ready else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let typingByChat = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
                chat.typingText.map { (chat.id, $0) }
            })
            chats = sortChats(try await repository.loadChats()).map { chat in
                var updated = chat
                updated.typingText = typingByChat[chat.id]
                return updated
            }
            status = ""
        } catch {
            status = error.localizedDescription
        }
    }

    func setChatVisible(_ chatId: Int64?) {
        visibleChatId = chatId
    }

    func selectChat(_ chatId: Int64) async {
        selectedChatId = chatId
        messages = []
        await refreshMessages(replaceExisting: true)
        if visibleChatId == chatId {
            await markChatRead(chatId)
        }
    }

    func refreshMessages(replaceExisting: Bool = false) async {
        guard let repository, let chatId = selectedChatId else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if replaceExisting || messages.isEmpty {
                let syncedMessages = try await repository.syncMessages(chatId: chatId)
                messages = applyReadState(deduplicatedMessages(syncedMessages), chatId: chatId)
            } else {
                await reloadMessagesFromStore(chatId: chatId, mergeWithExisting: true)
            }
            scheduleMediaDownloadIfNeeded(chatId: chatId, messages: messages)
        } catch {
            status = error.localizedDescription
        }
    }

    func reloadMessagesFromStore(chatId: Int64, mergeWithExisting: Bool = false) async {
        guard let repository else { return }
        do {
            let stored = try repository.storedMessages(chatId: chatId)
            let normalized = applyReadState(deduplicatedMessages(stored), chatId: chatId)
            if mergeWithExisting {
                let existingIds = Set(messages.map(\.id))
                let newOnes = normalized.filter { !existingIds.contains($0.id) }
                messages = deduplicatedMessages(messages + newOnes)
            } else {
                messages = normalized
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func loadOlderMessagesIfNeeded(triggerMessageId: Int64) async {
        guard
            let repository,
            let chatId = selectedChatId,
            !isLoadingOlderMessages,
            let oldest = messages.first?.id,
            oldest == triggerMessageId
        else { return }

        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }

        do {
            let older = try await repository.loadOlderMessages(chatId: chatId, beforeMessageId: oldest)
            guard !older.isEmpty else { return }
            let existingIds = Set(messages.map(\.id))
            let newOnes = older.filter { !existingIds.contains($0.id) }
            messages = applyReadState(deduplicatedMessages(newOnes + messages), chatId: chatId)
            scheduleMediaDownloadIfNeeded(chatId: chatId, messages: messages)
        } catch {
            status = error.localizedDescription
        }
    }

    func openChatPeek(chatId: Int64) async {
        guard let repository else { return }
        peekChatId = chatId
        peekMessages = []
        isPeekLoading = true
        defer { isPeekLoading = false }
        do {
            peekMessages = try await repository.peekMessages(chatId: chatId)
        } catch {
            status = error.localizedDescription
            peekChatId = nil
        }
    }

    func closeChatPeek() {
        peekChatId = nil
        peekMessages = []
    }

    func loadPeekOlderIfNeeded(chatId: Int64, triggerMessageId: Int64) async {
        guard
            let repository,
            peekChatId == chatId,
            !isLoadingPeekOlder,
            let oldest = peekMessages.first?.id,
            oldest == triggerMessageId
        else { return }

        isLoadingPeekOlder = true
        defer { isLoadingPeekOlder = false }

        do {
            let older = try await repository.peekOlderMessages(chatId: chatId, beforeMessageId: oldest)
            guard !older.isEmpty else { return }
            let existingIds = Set(peekMessages.map(\.id))
            let newOnes = older.filter { !existingIds.contains($0.id) }
            peekMessages = newOnes + peekMessages
        } catch {
            status = error.localizedDescription
        }
    }

    func openChat(chatId: Int64) async {
        mainTabIndex = 0
        selectedChatId = chatId
        navigationTargetChatId = chatId
        messages = []
        await refreshMessages(replaceExisting: true)
        if visibleChatId == chatId {
            await markChatRead(chatId)
        }
    }

    func loadProfilePhotoPaths(userId: Int64) async -> [String] {
        guard let repository else { return [] }
        do {
            let paths = try await repository.loadUserProfilePhotoPaths(userId: userId)
            return paths.isEmpty ? [] : paths
        } catch {
            return []
        }
    }

    private func scheduleMediaDownloadIfNeeded(chatId: Int64, messages: [TgMessage]) {
        let hasMissingMedia = messages.contains { message in
            message.attachments.contains { attachment in
                attachment.fileId != nil && (attachment.localPath?.isEmpty ?? true)
            }
        }
        guard hasMissingMedia, !mediaDownloadsInProgress.contains(chatId) else { return }

        mediaDownloadsInProgress.insert(chatId)
        Task { [weak self] in
            await self?.downloadMedia(chatId: chatId)
        }
    }

    private func downloadMedia(chatId: Int64) async {
        guard let repository else {
            mediaDownloadsInProgress.remove(chatId)
            return
        }

        defer { mediaDownloadsInProgress.remove(chatId) }

        do {
            let downloadedMessages = try await repository.downloadMedia(chatId: chatId)
            if selectedChatId == chatId {
                messages = applyReadState(deduplicatedMessages(downloadedMessages), chatId: chatId)
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func sendMessage() async {
        guard let repository, let chatId = selectedChatId else { return }
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isBusy = true
        defer { isBusy = false }
        do {
            if let editingMessageId {
                try await repository.edit(chatId: chatId, messageId: editingMessageId, text: text)
                self.editingMessageId = nil
                self.replyingToMessageId = nil
            } else if let replyId = replyingToMessageId {
                try await repository.sendReply(chatId: chatId, text: text, replyToMessageId: replyId)
            } else {
                try await repository.send(chatId: chatId, text: text)
            }
            composeText = ""
            replyingToMessageId = nil
            await refreshChats()
        } catch {
            status = error.localizedDescription
        }
    }

    func startEditing(_ message: TgMessage) {
        guard message.outgoing else { return }
        editingMessageId = message.id
        composeText = message.text
    }

    func cancelEditing() {
        editingMessageId = nil
    }

    func deleteMyMessage(_ message: TgMessage, revoke: Bool) async {
        guard let repository, let chatId = selectedChatId, message.outgoing else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await repository.delete(chatId: chatId, messageIds: [message.id], revoke: revoke)
            await reloadMessagesFromStore(chatId: chatId)
            await refreshChats()
        } catch {
            status = error.localizedDescription
        }
    }

    func markChatRead(_ chatId: Int64, force: Bool = false) async {
        guard force || visibleChatId == chatId else { return }
        guard let repository else { return }
        let needsServerUpdate = chats.first(where: { $0.id == chatId }).map {
            $0.unreadCount > 0 || $0.isMarkedUnread
        } ?? true

        updateLocalChat(chatId) { chat in
            chat.unreadCount = 0
            chat.isMarkedUnread = false
        }

        guard needsServerUpdate else { return }

        do {
            try await repository.markChatRead(chatId: chatId)
            try await repository.markChatUnread(chatId: chatId, unread: false)
        } catch {
            status = error.localizedDescription
            await refreshChats()
        }
    }

    func markChatUnread(_ chatId: Int64) async {
        guard let repository else { return }
        updateLocalChat(chatId) { chat in
            chat.isMarkedUnread = true
            chat.unreadCount = max(chat.unreadCount, 1)
        }

        do {
            try await repository.markChatUnread(chatId: chatId, unread: true)
            await refreshChats()
        } catch {
            status = error.localizedDescription
            await refreshChats()
        }
    }

    func setChatPinned(_ chatId: Int64, pinned: Bool) async {
        guard let repository else { return }
        updateLocalChat(chatId) { chat in
            chat.isPinned = pinned
            chat.pinOrder = pinned ? Int64(Date().timeIntervalSince1970) : nil
        }
        chats = sortChats(chats)

        do {
            try await repository.setChatPinned(chatId: chatId, pinned: pinned)
            await refreshChats()
        } catch {
            status = error.localizedDescription
            await refreshChats()
        }
    }

    func setChatMute(_ chatId: Int64, duration: ChatMuteDuration) async {
        guard let repository else { return }
        updateLocalChat(chatId) { chat in
            chat.isMuted = duration != .off
            chat.muteUntil = muteUntilDate(for: duration)
        }

        do {
            try await repository.setChatMute(chatId: chatId, duration: duration)
            await refreshChats()
        } catch {
            status = error.localizedDescription
            await refreshChats()
        }
    }

    func clearChatHistory(_ chatId: Int64) async {
        guard let repository else { return }
        do {
            try await repository.clearChatHistory(chatId: chatId)
            if selectedChatId == chatId {
                messages = []
            }
            await refreshChats()
        } catch {
            status = error.localizedDescription
        }
    }

    func deleteChat(_ chatId: Int64) async {
        guard let repository else { return }
        chats.removeAll { $0.id == chatId }
        do {
            try await repository.deleteChat(chatId: chatId)
            if selectedChatId == chatId {
                selectedChatId = nil
                messages = []
            }
            await refreshChats()
        } catch {
            status = error.localizedDescription
            await refreshChats()
        }
    }

    func leaveChat(_ chatId: Int64) async {
        guard let repository else { return }
        chats.removeAll { $0.id == chatId }
        do {
            try await repository.leaveChat(chatId: chatId)
            if selectedChatId == chatId {
                selectedChatId = nil
                messages = []
            }
            await refreshChats()
        } catch {
            status = error.localizedDescription
            await refreshChats()
        }
    }

    func setUserBlocked(chatId: Int64, blocked: Bool) async {
        guard let repository else { return }
        let userId = chats.first(where: { $0.id == chatId })?.privateUserId
            ?? chatProfile?.userId
        guard let userId else {
            status = AppText.tr("Не удалось определить пользователя", "Could not resolve user")
            return
        }

        do {
            try await repository.setUserBlocked(userId: userId, isBlocked: blocked)
            updateLocalChat(chatId) { chat in
                chat.isBlockedByMe = blocked
                chat.isBlockedByPeer = blocked ? false : chat.isBlockedByPeer
                if blocked {
                    chat.statusText = AppText.tr("Заблокирован вами", "Blocked by you")
                    chat.canSendMessages = false
                    chat.sendRestrictionText = AppText.tr("Вы заблокировали этого пользователя", "You blocked this user")
                }
            }
            if var profile = chatProfile, profile.chatId == chatId {
                profile = ChatProfile(
                    chatId: profile.chatId,
                    title: profile.title,
                    kind: profile.kind,
                    avatarPath: profile.avatarPath,
                    username: profile.username,
                    description: profile.description,
                    membersCount: profile.membersCount,
                    statusText: blocked
                        ? AppText.tr("Заблокирован вами", "Blocked by you")
                        : profile.statusText,
                    userId: profile.userId,
                    isBlockedByMe: blocked,
                    isBlockedByPeer: profile.isBlockedByPeer
                )
                chatProfile = profile
            }
            await refreshChats()
            if selectedChatId == chatId {
                await loadProfile(chatId: chatId)
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func movePinnedChats(from source: IndexSet, to destination: Int) async {
        guard let repository else { return }
        var pinned = chats.filter(\.isPinned)
        moveItems(in: &pinned, from: source, to: destination)
        let pinnedIds = pinned.map(\.id)

        do {
            try await repository.reorderPinnedChats(chatIds: pinnedIds)
            await refreshChats()
        } catch {
            status = error.localizedDescription
            await refreshChats()
        }
    }

    func quoteMessage(_ message: TgMessage) {
        let snippet = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snippet.isEmpty else { return }
        let author = message.outgoing ? "Вы" : "Собеседник"
        composeText = "> \(author): \(snippet)\n" + composeText
    }

    func forwardMessage(_ message: TgMessage, to targetChatId: Int64) async {
        guard let repository else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await repository.forwardMessage(fromChatId: message.chatId, toChatId: targetChatId, messageId: message.id)
            if targetChatId == selectedChatId {
                await refreshMessages()
            }
            await refreshChats()
        } catch {
            status = error.localizedDescription
        }
    }

    func authStepTitle() -> String {
        switch authState {
        case .waitPhone: return "Номер телефона"
        case .waitCode: return "Код подтверждения"
        case .waitPassword: return "Пароль 2FA"
        case .ready: return "Готово"
        }
    }

    func authStepSubtitle() -> String {
        switch authState {
        case .waitPhone:
            return "Введите номер в международном формате, например +79991234567"
        case .waitCode:
            return "Код придёт в Telegram или по SMS"
        case .waitPassword:
            return "У аккаунта включена двухэтапная аутентификация"
        case .ready:
            return ""
        }
    }

    private func handleIncomingMessage(_ message: TgMessage) {
        guard !message.outgoing, phase == .main else { return }
        guard let chat = chats.first(where: { $0.id == message.chatId }) else { return }
        guard visibleChatId != message.chatId else { return }
        guard !chat.isMuted else { return }

        let preview = messagePreviewText(message)
        incomingToast = IncomingMessageToast(
            chatId: message.chatId,
            title: chat.title,
            preview: preview,
            avatarPath: chat.avatarPath
        )
        toastDismissTask?.cancel()
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if incomingToast?.chatId == message.chatId {
                incomingToast = nil
            }
        }
        NotificationSoundPlayer.playMessageReceived()
    }

    func dismissIncomingToast() {
        incomingToast = nil
        toastDismissTask?.cancel()
    }

    func openIncomingToastChat() async {
        guard let toast = incomingToast else { return }
        dismissIncomingToast()
        await openChat(chatId: toast.chatId)
    }

    private func reloadPeekMessages(chatId: Int64) async {
        guard let repository, peekChatId == chatId else { return }
        do {
            let latest = try await repository.peekMessages(chatId: chatId)
            let existingIds = Set(peekMessages.map(\.id))
            let newOnes = latest.filter { !existingIds.contains($0.id) }
            if !newOnes.isEmpty {
                peekMessages = peekMessages + newOnes
            }
        } catch {
            // Keep silent during peek preview.
        }
    }

    private func wireRepository(_ repository: TelegramRepository) {
        repository.onAuthStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.authState = state
                await self?.applyPhase(for: state)
            }
        }

        repository.onIncomingMessage = { [weak self] message in
            Task { @MainActor in
                self?.handleIncomingMessage(message)
            }
        }

        repository.onMessageReplaced = { [weak self] chatId, oldMessageId, newMessage in
            Task { @MainActor in
                guard let self, self.selectedChatId == chatId else { return }
                if let index = self.messages.firstIndex(where: { $0.id == oldMessageId }) {
                    self.messages[index] = newMessage
                } else {
                    self.messages = self.deduplicatedMessages(self.messages + [newMessage])
                }
            }
        }

        repository.onMessagesChanged = { [weak self] chatId in
            guard let self else { return }
            Task { @MainActor in
                if self.peekChatId == chatId {
                    await self.reloadPeekMessages(chatId: chatId)
                }
                if self.selectedChatId == chatId {
                    await self.reloadMessagesFromStore(chatId: chatId, mergeWithExisting: true)
                    if self.visibleChatId == chatId {
                        await self.markChatRead(chatId)
                    }
                }
            }
        }

        repository.onChatsChanged = { [weak self] in
            Task { @MainActor in
                await self?.refreshChats()
            }
        }

        repository.onChatChanged = { [weak self] chatId in
            Task { @MainActor in
                await self?.refreshChats()
                self?.updateOutgoingReadReceipts(for: chatId)
                if self?.visibleChatId == chatId {
                    await self?.markChatRead(chatId)
                }
            }
        }

        repository.onTypingChanged = { [weak self] chatId, text in
            Task { @MainActor in
                self?.applyTyping(text, for: chatId)
            }
        }
    }

    private func applyPhase(for state: AuthState) async {
        switch state {
        case .ready:
            phase = .main
            status = ""
            await refreshMe()
        case .waitPhone, .waitCode, .waitPassword:
            phase = .login
            status = ""
        }
    }

    func refreshMe() async {
        guard let repository, authState == .ready else { return }
        do {
            me = try await repository.loadMe()
            if phase == .main {
                await refreshChats()
            }
        } catch {
            // Non-critical for core UX; keep Settings usable even if this fails.
            me = nil
        }
    }

    private func normalizedApiCredentials() -> (apiId: Int, apiHash: String)? {
        let idDigits = apiIdText.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()

        guard let apiId = Int(idDigits), apiId > 0 else {
            return nil
        }

        let trimmedHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedHex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let normalizedHash = trimmedHash.unicodeScalars
            .filter { allowedHex.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()

        guard normalizedHash.count == 32 else {
            return nil
        }

        return (apiId, normalizedHash)
    }

    private func recreateRepository() async {
        do {
            let repo = try TelegramRepository.bootstrap()
            repository = repo
            wireRepository(repo)
            isTdlibConfigured = false
            bootstrapError = nil
        } catch {
            bootstrapError = error.localizedDescription
            status = "Не удалось пересоздать TDLib клиент: \(error.localizedDescription)"
        }
    }

    func startReply(_ message: TgMessage) {
        replyingToMessageId = message.id
    }

    func cancelReply() {
        replyingToMessageId = nil
    }

    func replyPreviewText() -> String? {
        guard let id = replyingToMessageId else { return nil }
        return messages.first(where: { $0.id == id })?.text
    }

    func loadProfile(chatId: Int64) async {
        guard let repository else { return }
        profileLoadTask?.cancel()
        chatProfile = nil
        chatMembers = []
        chatMediaMessages = []

        profileLoadTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isProfileLoading = true
                self.isProfileDetailsLoading = true
            }
            defer {
                Task { @MainActor [weak self] in
                    self?.isProfileLoading = false
                    self?.isProfileDetailsLoading = false
                }
            }

            do {
                let profile = try await repository.loadChatProfile(chatId: chatId)
                guard !Task.isCancelled else { return }
                await MainActor.run { self.chatProfile = profile }

                async let members: [ChatMember] = repository.loadChatMembers(chatId: chatId)
                async let media: [TgMessage] = repository.loadChatMedia(chatId: chatId)

                let (m, mm) = try await (members, media)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.chatMembers = m
                    self.chatMediaMessages = mm
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { self.status = error.localizedDescription }
            }
        }
    }

    func loadProfileDetails(chatId: Int64) async {
        // Deprecated: kept for compatibility, profile loading is now parallelized in loadProfile(chatId:).
        await loadProfile(chatId: chatId)
    }

    private func applyTyping(_ text: String?, for chatId: Int64) {
        typingClearTasks[chatId]?.cancel()
        updateLocalChat(chatId) { chat in
            chat.typingText = text
        }

        guard text != nil else { return }

        typingClearTasks[chatId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.updateLocalChat(chatId) { chat in
                    chat.typingText = nil
                }
                self?.typingClearTasks[chatId] = nil
            }
        }
    }

    private func updateLocalChat(_ chatId: Int64, mutate: (inout TgChat) -> Void) {
        guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
        mutate(&chats[index])
    }

    func searchLocalChats(query: String) -> [TgChat] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return chats }
        return chats.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.lastMessagePreview?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    func searchTelegram(query: String) async -> [TgChat] {
        guard let repository else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        do {
            async let local = repository.searchChats(query: trimmed)
            async let remote = repository.searchPublicChats(query: trimmed)
            let (localChats, publicChats) = try await (local, remote)
            var seen = Set<Int64>()
            return (localChats + publicChats).filter { seen.insert($0.id).inserted }
        } catch {
            status = error.localizedDescription
            return []
        }
    }

    func updateProfileName(firstName: String, lastName: String) async {
        guard let repository else { return }
        do {
            try await repository.updateProfileName(firstName: firstName, lastName: lastName)
            await refreshMe()
        } catch {
            status = error.localizedDescription
        }
    }

    func updateMyProfile(firstName: String, lastName: String, username: String) async {
        guard let repository else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await repository.updateProfileName(firstName: firstName, lastName: lastName)
            let normalizedUsername = username
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "@", with: "")
            try await repository.updateUsername(normalizedUsername)
            await refreshMe()
            status = ""
        } catch {
            status = error.localizedDescription
        }
    }

    func uploadMyProfilePhoto(from image: UIImage) async {
        guard let repository else { return }
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }

        isBusy = true
        defer { isBusy = false }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("profile-\(UUID().uuidString).jpg")
            try data.write(to: url)
            try await repository.uploadProfilePhoto(localPath: url.path)
            try? FileManager.default.removeItem(at: url)
            await refreshMe()
            status = ""
        } catch {
            status = error.localizedDescription
        }
    }

    func loadPrivacySettings() async {
        guard let repository else { return }
        isPrivacyLoading = true
        defer { isPrivacyLoading = false }
        do {
            privacySettings = try await repository.loadPrivacySettings()
            status = ""
        } catch {
            status = error.localizedDescription
        }
    }

    func updatePrivacySetting(_ kind: UserPrivacySettingKind, visibility: PrivacyVisibility) async {
        guard let repository else { return }
        do {
            try await repository.updatePrivacySetting(kind: kind, visibility: visibility)
            if let index = privacySettings.firstIndex(where: { $0.kind == kind }) {
                privacySettings[index].visibility = visibility
            }
            status = ""
        } catch {
            status = error.localizedDescription
        }
    }

    func runGlobalSearch() async {
        let query = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            globalSearchChats = []
            globalSearchMessageHits = []
            return
        }

        isGlobalSearching = true
        defer { isGlobalSearching = false }

        switch globalSearchScope {
        case .myChats:
            globalSearchChats = searchLocalChats(query: query)
            globalSearchMessageHits = []
        case .telegram:
            globalSearchChats = await searchTelegram(query: query)
            guard let repository else {
                globalSearchMessageHits = []
                return
            }
            do {
                globalSearchMessageHits = try await repository.searchMessagesGlobally(query: query)
            } catch {
                globalSearchMessageHits = []
                status = error.localizedDescription
            }
        }
    }

    func openChatFromSearch(_ chatId: Int64) async {
        await openChat(chatId: chatId)
    }

    private func deduplicatedMessages(_ items: [TgMessage]) -> [TgMessage] {
        var seen = Set<Int64>()
        return items
            .sorted { $0.createdAt < $1.createdAt }
            .filter { seen.insert($0.id).inserted }
    }

    private func applyReadState(_ items: [TgMessage], chatId: Int64) -> [TgMessage] {
        let lastRead = chats.first(where: { $0.id == chatId })?.lastReadOutboxMessageId ?? 0
        return items.map { message in
            guard message.outgoing else { return message }
            let isRead = message.id > 0 && message.id <= lastRead
            guard isRead != message.isReadByPeer else { return message }
            return TgMessage(
                id: message.id,
                chatId: message.chatId,
                text: message.text,
                outgoing: message.outgoing,
                createdAt: message.createdAt,
                isEdited: message.isEdited,
                replyToMessageId: message.replyToMessageId,
                isDeleted: message.isDeleted,
                isReadByPeer: isRead,
                attachments: message.attachments,
                mediaAlbumId: message.mediaAlbumId,
                forwardedFrom: message.forwardedFrom,
                senderUserId: message.senderUserId,
                senderName: message.senderName,
                senderAvatarPath: message.senderAvatarPath,
                authorSignature: message.authorSignature,
                viewCount: message.viewCount
            )
        }
    }

    private func updateOutgoingReadReceipts(for chatId: Int64) {
        guard selectedChatId == chatId, !messages.isEmpty else { return }
        messages = applyReadState(messages, chatId: chatId)
    }

    private func messagePreviewText(_ message: TgMessage) -> String {
        if message.isDeleted {
            return AppText.tr("Удалённое сообщение", "Deleted message")
        }
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let first = message.attachments.first {
            switch first.kind {
            case .photo: return AppText.tr("Фото", "Photo")
            case .video: return AppText.tr("Видео", "Video")
            case .voice: return AppText.tr("Голосовое", "Voice message")
            case .document: return first.fileName ?? AppText.tr("Файл", "File")
            default: return AppText.tr("Медиа", "Media")
            }
        }
        return AppText.tr("Новое сообщение", "New message")
    }

    private func sortChats(_ items: [TgChat]) -> [TgChat] {
        items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.isPinned && rhs.isPinned {
                return (lhs.pinOrder ?? 0) > (rhs.pinOrder ?? 0)
            }
            return (lhs.lastMessageDate ?? .distantPast) > (rhs.lastMessageDate ?? .distantPast)
        }
    }

    private func muteUntilDate(for duration: ChatMuteDuration) -> Date? {
        switch duration {
        case .off:
            return nil
        case .oneHour, .eightHours:
            return Date().addingTimeInterval(TimeInterval(duration.seconds))
        case .forever:
            return nil
        }
    }

    private func moveItems(in items: inout [TgChat], from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { items[$0] }
        for index in source.sorted(by: >) {
            items.remove(at: index)
        }

        var insertionIndex = destination
        let removedBeforeDestination = source.filter { $0 < destination }.count
        insertionIndex -= removedBeforeDestination
        insertionIndex = max(0, min(insertionIndex, items.count))

        for item in moving {
            items.insert(item, at: insertionIndex)
            insertionIndex += 1
        }
    }
}

private struct ApiCredentialsStore {
    private let apiIdKey = "telegram.api_id"
    private let apiHashKey = "telegram.api_hash"
    private let service = "online.maseai.telegramuserclient.credentials"
    private let account = "telegram.api_credentials"
    private let bundledApiId = 39444423
    private let bundledApiHash = "07679c329a2ea28d6b6f1858d5129d01"

    struct Saved {
        let apiId: Int
        let apiHash: String
    }

    func load() -> Saved? {
        if let fromKeychain = loadFromKeychain() {
            return fromKeychain
        }

        // One-time migration from old storage.
        let defaults = UserDefaults.standard
        let apiId = defaults.integer(forKey: apiIdKey)
        if apiId > 0, let apiHash = defaults.string(forKey: apiHashKey), !apiHash.isEmpty {
            let saved = Saved(apiId: apiId, apiHash: apiHash)
            saveToKeychain(saved)
            defaults.removeObject(forKey: apiIdKey)
            defaults.removeObject(forKey: apiHashKey)
            return saved
        }

        let bundled = bundledCredentials()
        saveToKeychain(bundled)
        return bundled
    }

    func save(apiId: Int, apiHash: String) {
        saveToKeychain(Saved(apiId: apiId, apiHash: apiHash))
    }

    func clear() {
        deleteFromKeychain()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: apiIdKey)
        defaults.removeObject(forKey: apiHashKey)
    }

    private func loadFromKeychain() -> Saved? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let apiId = object["api_id"] as? Int,
            let apiHash = object["api_hash"] as? String,
            apiId > 0,
            !apiHash.isEmpty
        else {
            return nil
        }
        return Saved(apiId: apiId, apiHash: apiHash)
    }

    private func bundledCredentials() -> Saved {
        Saved(apiId: bundledApiId, apiHash: bundledApiHash)
    }

    private func saveToKeychain(_ saved: Saved) {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: ["api_id": saved.apiId, "api_hash": saved.apiHash]
            )
        else {
            return
        }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let update: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(query as CFDictionary, update as CFDictionary)
        }
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
