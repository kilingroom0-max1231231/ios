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
    @Published var userProfileDetail: UserProfileDetail?
    @Published var userProfileStories: [TgStoryItem] = []
    @Published var userProfileGifts: [TgGiftItem] = []
    @Published var isUserProfileLoading = false
    @Published var isUserProfileExtrasLoading = false
    @Published var isSwitchingAccount = false
    @Published private(set) var chatMediaGeneration = 0

    private var repository: TelegramRepository?
    private var messagesReloadTasks: [Int64: Task<Void, Never>] = [:]
    private var mediaPathsApplyTask: Task<Void, Never>?
    private var loadedStoriesForUserId: Int64?
    private var loadedGiftsForUserId: Int64?
    private var mediaDownloadsInProgress: Set<Int64> = []
    private var typingClearTasks: [Int64: Task<Void, Never>] = [:]
    private var typingUserClearTasks: [String: Task<Void, Never>] = [:]
    private var activeTypersByChat: [Int64: [Int64: TypingParticipant]] = [:]

    private struct TypingParticipant: Equatable {
        var name: String
        var actionKey: String
    }
    private var profileLoadTask: Task<Void, Never>?
    private var isTdlibConfigured = false
    private let credentials = ApiCredentialsStore()
    private let accountSessions = AccountSessionStore.shared
    private var isLoadingOlderMessages = false
    private var isLoadingPeekOlder = false
    private var toastDismissTask: Task<Void, Never>?
    private var toastDismissGeneration = 0

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

    var accountList: [AccountSession] {
        accountSessions.sessions
    }

    var activeAccountId: String {
        accountSessions.activeAccountId
    }

    var canAddMoreAccounts: Bool {
        accountSessions.canAddAccount()
    }

    var visibleMessages: [TgMessage] {
        guard !AppSettingsStore.shared.keepDeletedMessages else { return messages }
        return messages.filter { !$0.isDeleted }
    }

    func applyKeepDeletedMessagesPreference() async {
        guard let repository, let chatId = selectedChatId else { return }
        if AppSettingsStore.shared.keepDeletedMessages {
            await reloadMessagesFromStore(chatId: chatId, mergeWithExisting: false)
            return
        }

        try? repository.purgeDeletedMessages(chatId: chatId)
        messages = messages.filter { !$0.isDeleted }
        peekMessages = peekMessages.filter { !$0.isDeleted }
        await patchDeletedChatPreview(chatId: chatId)
    }

    func start() async {
        phase = .loading
        bootstrapError = nil

        do {
            let repo = try TelegramRepository.bootstrap(accountId: accountSessions.activeAccountId)
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

    func addAccount() {
        guard accountSessions.addAccount() != nil else {
            status = AppText.tr("Можно добавить максимум 5 аккаунтов", "You can add up to 5 accounts")
            return
        }
        status = AppText.tr("Аккаунт добавлен. Выберите его в списке выше.", "Account added. Choose it in the list above.")
    }

    func switchAccount(to accountId: String) async {
        guard accountId != accountSessions.activeAccountId else { return }
        guard !isSwitchingAccount else { return }
        isSwitchingAccount = true
        defer { isSwitchingAccount = false }
        accountSessions.setActiveAccount(id: accountId)

        // Reset volatile state before new repository bootstrap.
        chats = []
        messages = []
        selectedChatId = nil
        visibleChatId = nil
        chatProfile = nil
        chatMembers = []
        chatMediaMessages = []
        peekChatId = nil
        peekMessages = []
        me = nil
        isTdlibConfigured = false

        await recreateRepository()
        await connect(saveCredentials: false)
    }

    func refreshChats() async {
        guard let repository, authState == .ready else { return }

        let typingByChat = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.typingText.map { (chat.id, $0) }
        })

        if chats.isEmpty {
            let cached = repository.cachedChats()
            if !cached.isEmpty {
                chats = sortChats(cached).map { chat in
                    var updated = chat
                    updated.typingText = typingByChat[chat.id]
                    return updated
                }
            }
        }

        let showBlockingLoader = chats.isEmpty
        if showBlockingLoader { isBusy = true }
        defer { if showBlockingLoader { isBusy = false } }

        do {
            let previousById = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
            chats = sortChats(try await repository.loadChats()).map { chat in
                var updated = chat
                if (updated.avatarPath?.isEmpty ?? true),
                   let previousPath = previousById[chat.id]?.avatarPath,
                   !previousPath.isEmpty {
                    updated.avatarPath = previousPath
                }
                updated.typingText = typingByChat[chat.id] ?? previousById[chat.id]?.typingText
                return updated
            }
            status = ""
        } catch {
            if chats.isEmpty {
                status = error.localizedDescription
            }
        }
    }

    func setChatVisible(_ chatId: Int64?) {
        let previous = visibleChatId
        visibleChatId = chatId
        Task { [weak self] in
            guard let self, let repository = self.repository else { return }
            if let previous, previous != chatId {
                try? await repository.closeChat(chatId: previous)
            }
            if let chatId {
                try? await repository.openChat(chatId: chatId)
            }
        }
    }

    func selectChat(_ chatId: Int64) async {
        if selectedChatId != chatId {
            messages = []
        }
        selectedChatId = chatId
        await refreshChatSendPermissions(chatId: chatId)
        await loadMessagesFromCache(chatId: chatId)
        await refreshMessages(force: true)
        if visibleChatId == chatId {
            await markChatRead(chatId)
        }
    }

    func refreshChatSendPermissions(chatId: Int64) async {
        guard let repository else { return }
        do {
            let permissions = try await repository.refreshChatSendPermissions(chatId: chatId)
            updateLocalChat(chatId) { chat in
                chat.canSendMessages = permissions.canSend
                chat.sendRestrictionText = permissions.reason
            }
        } catch {
            // Keep previous permissions on transient errors.
        }
    }

    func pinMessage(_ message: TgMessage) async {
        guard let repository, let chatId = selectedChatId else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await repository.pinMessage(chatId: chatId, messageId: message.id)
            status = AppText.tr("Сообщение закреплено", "Message pinned")
        } catch {
            status = error.localizedDescription
        }
    }

    private func loadMessagesFromCache(chatId: Int64) async {
        guard let repository else { return }
        do {
            let stored = try repository.storedMessages(chatId: chatId)
            guard !stored.isEmpty else { return }
            messages = applyReadState(deduplicatedMessages(stored), chatId: chatId)
        } catch {
            // Keep silent; network sync will populate messages.
        }
    }

    func refreshMessages(force: Bool = false) async {
        guard let repository, let chatId = selectedChatId else { return }

        if messages.isEmpty {
            await loadMessagesFromCache(chatId: chatId)
        }

        let showBlockingLoader = messages.isEmpty
        if showBlockingLoader { isBusy = true }
        defer { if showBlockingLoader { isBusy = false } }

        do {
            let syncedMessages = try await repository.syncMessages(chatId: chatId)
            if force || messages.isEmpty {
                messages = applyReadState(deduplicatedMessages(syncedMessages), chatId: chatId)
            } else {
                replaceMessagesPreservingDisplay(syncedMessages, chatId: chatId)
            }
            scheduleMediaDownloadIfNeeded(chatId: chatId, messages: messages)
        } catch {
            if messages.isEmpty {
                status = error.localizedDescription
            }
        }
    }

    func reloadMessagesFromStore(chatId: Int64, mergeWithExisting: Bool = true) async {
        guard let repository else { return }
        do {
            let stored = try repository.storedMessages(chatId: chatId)
            let normalized = applyReadState(deduplicatedMessages(stored), chatId: chatId)
            if mergeWithExisting {
                replaceMessagesPreservingDisplay(normalized, chatId: chatId)
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
            var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
            for message in older {
                byId[message.id] = message.mergingPreservingDisplayFields(from: byId[message.id])
            }
            messages = applyReadState(
                deduplicatedMessages(byId.values.sorted { $0.createdAt < $1.createdAt }),
                chatId: chatId
            )
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
        if selectedChatId != chatId {
            messages = []
        }
        selectedChatId = chatId
        navigationTargetChatId = chatId
        await loadMessagesFromCache(chatId: chatId)
        await refreshMessages(force: true)
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
        let repository = repository
        Task.detached(priority: .utility) { [weak self] in
            await Self.runMediaDownload(chatId: chatId, repository: repository, owner: self)
        }
    }

    private static func runMediaDownload(
        chatId: Int64,
        repository: TelegramRepository?,
        owner: AppViewModel?
    ) async {
        guard let repository else {
            await MainActor.run {
                owner?.mediaDownloadsInProgress.remove(chatId)
            }
            return
        }

        defer {
            Task { @MainActor in
                owner?.mediaDownloadsInProgress.remove(chatId)
            }
        }

        do {
            let downloadedMessages = try await repository.downloadMedia(chatId: chatId)
            await MainActor.run {
                guard let owner, owner.selectedChatId == chatId else { return }
                owner.applyMediaPaths(from: downloadedMessages, chatId: chatId)
            }
        } catch {
            await MainActor.run {
                owner?.status = error.localizedDescription
            }
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
            await reloadMessagesFromStore(chatId: chatId, mergeWithExisting: true)
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
                    isPremium: profile.isPremium,
                    premiumBadgePath: profile.premiumBadgePath,
                    hasActiveStories: profile.hasActiveStories,
                    giftCount: profile.giftCount,
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

    private func applyUpsertedMessage(_ message: TgMessage) {
        guard selectedChatId == message.chatId else { return }
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        if message.isDeleted && !AppSettingsStore.shared.keepDeletedMessages {
            byId.removeValue(forKey: message.id)
        } else {
            byId[message.id] = message.mergingPreservingDisplayFields(from: byId[message.id])
        }
        messages = applyReadState(
            deduplicatedMessages(byId.values.sorted { $0.createdAt < $1.createdAt }),
            chatId: message.chatId
        )
        scheduleMediaDownloadIfNeeded(chatId: message.chatId, messages: messages)
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
        toastDismissGeneration += 1
        let dismissGeneration = toastDismissGeneration
        toastDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 4_500_000_000)
            } catch {
                return
            }
            guard dismissGeneration == toastDismissGeneration else { return }
            incomingToast = nil
        }

        NotificationSoundPlayer.playMessageReceived()
    }

    func dismissIncomingToast() {
        toastDismissGeneration += 1
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
            var byId = Dictionary(uniqueKeysWithValues: peekMessages.map { ($0.id, $0) })
            for message in latest {
                byId[message.id] = message.mergingPreservingDisplayFields(from: byId[message.id])
            }
            peekMessages = byId.values.sorted { $0.createdAt < $1.createdAt }
        } catch {
            // Keep silent during peek preview.
        }
    }

    private func patchDeletedChatPreview(chatId: Int64) async {
        guard let repository,
              let lastId = chats.first(where: { $0.id == chatId })?.lastMessageId,
              let stored = try? repository.storedMessages(chatId: chatId),
              let lastMessage = stored.first(where: { $0.id == lastId }),
              lastMessage.isDeleted else { return }
        updateLocalChat(chatId) { chat in
            chat.lastMessagePreview = AppText.chatListPreview(for: lastMessage)
        }
    }

    private func applyMessagesDeleted(chatId: Int64, messageIds: Set<Int64>) async {
        guard !messageIds.isEmpty else { return }

        if AppSettingsStore.shared.keepDeletedMessages {
            let markDeleted: (TgMessage) -> TgMessage = { message in
                messageIds.contains(message.id) ? message.markedDeleted() : message
            }
            if selectedChatId == chatId {
                messages = messages.map(markDeleted)
            }
            if peekChatId == chatId {
                peekMessages = peekMessages.map(markDeleted)
            }
        } else {
            if selectedChatId == chatId {
                messages = messages.filter { !messageIds.contains($0.id) }
            }
            if peekChatId == chatId {
                peekMessages = peekMessages.filter { !messageIds.contains($0.id) }
            }
        }

        guard let repository else { return }
        let stored = (try? repository.storedMessages(chatId: chatId)) ?? []
        updateLocalChat(chatId) { chat in
            guard let lastId = chat.lastMessageId, messageIds.contains(lastId) else { return }
            if let lastMessage = stored.first(where: { $0.id == lastId }) {
                chat.lastMessagePreview = AppText.chatListPreview(for: lastMessage)
            } else if let lastMessage = messages.first(where: { $0.id == lastId }) {
                chat.lastMessagePreview = AppText.chatListPreview(for: lastMessage)
            }
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

        repository.onMessageUpserted = { [weak self] message in
            Task { @MainActor in
                self?.applyUpsertedMessage(message)
            }
        }

        repository.onMessagesDeleted = { [weak self] chatId, messageIds in
            Task { @MainActor in
                await self?.applyMessagesDeleted(chatId: chatId, messageIds: Set(messageIds))
            }
        }

        repository.onMessageReplaced = { [weak self] chatId, oldMessageId, newMessage in
            Task { @MainActor in
                guard let self, self.selectedChatId == chatId else { return }
                var updated = self.messages.filter { $0.id != oldMessageId }
                if let index = updated.firstIndex(where: { $0.id == newMessage.id }) {
                    let previous = updated[index]
                    updated[index] = newMessage.mergingPreservingDisplayFields(from: previous)
                } else {
                    updated.append(newMessage)
                }
                self.messages = self.applyReadState(
                    self.deduplicatedMessages(updated),
                    chatId: chatId
                )
            }
        }

        repository.onMessagesChanged = { [weak self] chatId in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleMessagesReload(chatId: chatId)
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
                await self?.refreshChatSendPermissions(chatId: chatId)
                await self?.patchDeletedChatPreview(chatId: chatId)
                self?.updateOutgoingReadReceipts(for: chatId)
                if self?.visibleChatId == chatId {
                    await self?.markChatRead(chatId)
                }
            }
        }

        repository.onTypingChanged = { [weak self] update in
            Task { @MainActor in
                self?.applyTypingUpdate(update)
            }
        }
    }

    private func scheduleMessagesReload(chatId: Int64) {
        messagesReloadTasks[chatId]?.cancel()
        messagesReloadTasks[chatId] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.peekChatId == chatId {
                await self.reloadPeekMessages(chatId: chatId)
            }
            if self.selectedChatId == chatId {
                await self.reloadMessagesFromStore(chatId: chatId, mergeWithExisting: true)
                if self.visibleChatId == chatId {
                    await self.markChatRead(chatId)
                }
            }
            self.messagesReloadTasks[chatId] = nil
        }
    }

    private func applyPhase(for state: AuthState) async {
        switch state {
        case .ready:
            phase = .main
            status = ""
            if let repository {
                let cached = repository.cachedChats()
                if !cached.isEmpty {
                    chats = sortChats(cached)
                }
            }
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
            if let me {
                accountSessions.updateActiveAccount(
                    title: me.displayName,
                    phone: me.phoneNumber,
                    userId: me.id,
                    avatarPath: me.avatarPath
                )
            }
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
            let repo = try TelegramRepository.bootstrap(accountId: accountSessions.activeAccountId)
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

    func loadUserProfile(userId: Int64) async {
        guard let repository else { return }
        isUserProfileLoading = true
        defer { isUserProfileLoading = false }

        do {
            userProfileDetail = try await repository.loadUserProfileDetail(userId: userId)
            loadedStoriesForUserId = nil
            loadedGiftsForUserId = nil
            userProfileStories = []
            userProfileGifts = []
            await loadUserProfileStories(userId: userId, force: true)
        } catch {
            status = error.localizedDescription
        }
    }

    func loadUserProfileStories(userId: Int64, force: Bool = false) async {
        guard let profile = userProfileDetail, profile.userId == userId else { return }
        await loadActiveStories(chatId: profile.privateChatId, force: force)
    }

    func loadActiveStories(chatId: Int64, force: Bool = false) async {
        guard let repository else { return }
        if !force, loadedStoriesForUserId == chatId, !userProfileStories.isEmpty { return }

        isUserProfileExtrasLoading = true
        defer { isUserProfileExtrasLoading = false }

        do {
            let stories = try await repository.loadUserStories(chatId: chatId)
            userProfileStories = stories
            if !stories.isEmpty || force {
                loadedStoriesForUserId = chatId
            }
        } catch {
            if force {
                userProfileStories = []
            }
        }
    }

    func loadUserProfileGifts(userId: Int64) async {
        guard let repository,
              let profile = userProfileDetail,
              profile.userId == userId,
              loadedGiftsForUserId != userId else { return }

        isUserProfileExtrasLoading = true
        defer { isUserProfileExtrasLoading = false }

        do {
            userProfileGifts = try await repository.loadUserGifts(userId: userId)
            loadedGiftsForUserId = userId
        } catch {
            userProfileGifts = []
        }
    }

    func openMyProfile() async {
        guard let me else { return }
        await loadUserProfile(userId: me.id)
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
                await loadActiveStories(chatId: profile.chatId, force: profile.hasActiveStories)

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

    private func applyTypingUpdate(_ update: ChatTypingUpdate) {
        let chatId = update.chatId

        if let userId = update.userId, userId == me?.id {
            return
        }

        if let userId = update.userId {
            let taskKey = "\(chatId)-\(userId)"
            typingUserClearTasks[taskKey]?.cancel()

            if let actionKey = update.actionKey {
                var chatTypers = activeTypersByChat[chatId] ?? [:]
                let existingName = chatTypers[userId]?.name
                chatTypers[userId] = TypingParticipant(name: existingName ?? "…", actionKey: actionKey)
                activeTypersByChat[chatId] = chatTypers
                publishTypingSummary(for: chatId)

                if existingName == nil, let repository {
                    Task { [weak self] in
                        guard let self else { return }
                        let name = (try? await repository.fetchUserDisplayName(userId: userId)) ?? "User"
                        await MainActor.run {
                            guard var typers = self.activeTypersByChat[chatId],
                                  var participant = typers[userId] else { return }
                            participant.name = name
                            typers[userId] = participant
                            self.activeTypersByChat[chatId] = typers
                            self.publishTypingSummary(for: chatId)
                        }
                    }
                }

                typingUserClearTasks[taskKey] = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: 5_500_000_000)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self?.removeTyper(userId: userId, chatId: chatId)
                        self?.typingUserClearTasks[taskKey] = nil
                    }
                }
            } else {
                removeTyper(userId: userId, chatId: chatId)
                typingUserClearTasks[taskKey] = nil
            }
            return
        }

        // Private chat / action without user id.
        typingClearTasks[chatId]?.cancel()
        if let actionKey = update.actionKey {
            updateLocalChat(chatId) { chat in
                chat.typingText = AppText.typingStatus(actionKey)
            }
            typingClearTasks[chatId] = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 5_500_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.updateLocalChat(chatId) { chat in
                    chat.typingText = nil
                }
                self?.typingClearTasks[chatId] = nil
            }
        } else {
            activeTypersByChat[chatId] = nil
            updateLocalChat(chatId) { chat in
                chat.typingText = nil
            }
        }
    }

    private func removeTyper(userId: Int64, chatId: Int64) {
        guard var chatTypers = activeTypersByChat[chatId] else { return }
        chatTypers.removeValue(forKey: userId)
        if chatTypers.isEmpty {
            activeTypersByChat[chatId] = nil
            updateLocalChat(chatId) { chat in
                chat.typingText = nil
            }
        } else {
            activeTypersByChat[chatId] = chatTypers
            publishTypingSummary(for: chatId)
        }
    }

    private func publishTypingSummary(for chatId: Int64) {
        guard let typers = activeTypersByChat[chatId], !typers.isEmpty else {
            updateLocalChat(chatId) { chat in
                chat.typingText = nil
            }
            return
        }

        let chatKind = chats.first(where: { $0.id == chatId })?.kind ?? .unknown
        let actionKey = typers.values.first?.actionKey ?? "typing"
        let names = typers.values.map(\.name).sorted()

        let summary: String?
        switch chatKind {
        case .basicGroup, .supergroup, .channel:
            summary = AppText.groupTypingStatus(names: names, actionKey: actionKey)
        case .private, .savedMessages, .unknown:
            if let only = names.first {
                summary = AppText.groupTypingStatus(names: [only], actionKey: actionKey)
            } else {
                summary = AppText.typingStatus(actionKey)
            }
        }

        updateLocalChat(chatId) { chat in
            chat.typingText = summary
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

    private func applyMediaPaths(from downloaded: [TgMessage], chatId: Int64) {
        guard selectedChatId == chatId else { return }
        mediaPathsApplyTask?.cancel()
        mediaPathsApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self, !Task.isCancelled else { return }
            self.mergeMediaPaths(from: downloaded, chatId: chatId)
        }
    }

    private func mergeMediaPaths(from downloaded: [TgMessage], chatId: Int64) {
        guard selectedChatId == chatId else { return }
        let downloadedById = Dictionary(uniqueKeysWithValues: downloaded.map { ($0.id, $0) })
        var didChange = false

        let updated = messages.map { message -> TgMessage in
            guard let source = downloadedById[message.id] else { return message }
            let mergedAttachments = message.attachments.map { attachment -> TgAttachment in
                guard let fileId = attachment.fileId,
                      let refreshed = source.attachments.first(where: { $0.fileId == fileId }) else {
                    return attachment
                }
                let newPath = refreshed.localPath.flatMap { $0.isEmpty ? nil : $0 }
                let newAnim = refreshed.animationPath.flatMap { $0.isEmpty ? nil : $0 }
                let pathChanged = newPath != nil && newPath != attachment.localPath
                let animChanged = newAnim != nil && newAnim != attachment.animationPath
                guard pathChanged || animChanged else { return attachment }
                didChange = true
                return TgAttachment(
                    id: attachment.id,
                    kind: attachment.kind,
                    fileId: attachment.fileId,
                    fileName: attachment.fileName,
                    mimeType: attachment.mimeType,
                    size: attachment.size,
                    localPath: newPath ?? attachment.localPath,
                    animationPath: newAnim ?? attachment.animationPath,
                    isPremiumSticker: refreshed.isPremiumSticker || attachment.isPremiumSticker
                )
            }
            guard mergedAttachments != message.attachments else { return message }
            return TgMessage(
                id: message.id,
                chatId: message.chatId,
                text: message.text,
                outgoing: message.outgoing,
                createdAt: message.createdAt,
                isEdited: message.isEdited,
                replyToMessageId: message.replyToMessageId,
                isDeleted: message.isDeleted,
                isReadByPeer: message.isReadByPeer,
                attachments: mergedAttachments,
                mediaAlbumId: message.mediaAlbumId,
                forwardedFrom: message.forwardedFrom,
                senderUserId: message.senderUserId,
                senderName: message.senderName,
                senderAvatarPath: message.senderAvatarPath,
                authorSignature: message.authorSignature,
                viewCount: message.viewCount
            )
        }

        guard didChange else { return }
        messages = applyReadState(updated, chatId: chatId)
        chatMediaGeneration += 1
    }

    private func replaceMessagesPreservingDisplay(_ incoming: [TgMessage], chatId: Int64) {
        if messages.isEmpty {
            messages = applyReadState(deduplicatedMessages(incoming), chatId: chatId)
            return
        }
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for message in incoming {
            byId[message.id] = message.mergingPreservingDisplayFields(from: byId[message.id])
        }
        messages = applyReadState(
            deduplicatedMessages(byId.values.sorted { $0.createdAt < $1.createdAt }),
            chatId: chatId
        )
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
        AppText.chatListPreview(for: message)
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
