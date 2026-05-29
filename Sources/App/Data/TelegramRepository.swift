import Foundation

enum TelegramRepositoryError: LocalizedError {
    case bootstrapFailed(String)

    var errorDescription: String? {
        switch self {
        case .bootstrapFailed(let message):
            return message
        }
    }
}

final class TelegramRepository {
    private let client: TelegramClientProtocol
    private let store: LocalMessageStore
    private let chatStore: LocalChatStore

    var onAuthStateChanged: ((AuthState) -> Void)?
    var onMessagesChanged: ((Int64) -> Void)?
    var onChatsChanged: (() -> Void)?
    var onChatChanged: ((Int64) -> Void)?
    var onTypingChanged: ((ChatTypingUpdate) -> Void)?
    var onIncomingMessage: ((TgMessage) -> Void)?
    var onMessageUpserted: ((TgMessage) -> Void)?
    var onMessagesDeleted: ((Int64, [Int64]) -> Void)?
    var onMessageReplaced: ((Int64, Int64, TgMessage) -> Void)?
    var onMessageInteractionUpdated: ((Int64, Int64, [TgMessageReaction], Int?) -> Void)?

    init(client: TelegramClientProtocol, store: LocalMessageStore, chatStore: LocalChatStore) {
        self.client = client
        self.store = store
        self.chatStore = chatStore
        self.client.setEventHandler { [weak self] event in
            guard let self else { return }
            switch event {
            case .authChanged(let state):
                self.onAuthStateChanged?(state)
            case .newMessage(let message):
                try? self.store.upsert(messages: [message])
                self.onIncomingMessage?(message)
                self.onMessageUpserted?(message)
                self.onMessagesChanged?(message.chatId)
                self.onChatChanged?(message.chatId)
            case .messageReplaced(let chatId, let oldMessageId, let newMessage):
                try? self.store.deleteMessage(chatId: chatId, messageId: oldMessageId)
                try? self.store.upsert(messages: [newMessage])
                self.onMessageReplaced?(chatId, oldMessageId, newMessage)
                self.onMessageUpserted?(newMessage)
                self.onMessagesChanged?(chatId)
                self.onChatChanged?(chatId)
            case .messagesDeleted(let chatId, let messageIds):
                if AppSettingsStore.keepDeletedMessagesValue {
                    try? self.store.markDeleted(chatId: chatId, messageIds: messageIds)
                } else {
                    try? self.store.removeMessages(chatId: chatId, messageIds: messageIds)
                }
                self.onMessagesDeleted?(chatId, messageIds)
                self.onMessagesChanged?(chatId)
                self.onChatChanged?(chatId)
            case .chatsChanged:
                self.onChatsChanged?()
            case .chatChanged(let chatId):
                self.onChatChanged?(chatId)
            case .chatTypingChanged(let chatId, let userId, let actionKey):
                self.onTypingChanged?(ChatTypingUpdate(chatId: chatId, userId: userId, actionKey: actionKey))
            case .messageInteractionUpdated(let chatId, let messageId, let reactions, let viewCount):
                self.onMessageInteractionUpdated?(chatId, messageId, reactions, viewCount)
            }
        }
    }

    static func bootstrap(accountId: String = "default") throws -> TelegramRepository {
        do {
            let client = try TDLibClient(accountId: accountId)
            let store = try LocalMessageStore(filename: TDLibPaths.messagesDatabaseFilename(accountId: accountId))
            let chatStore = try LocalChatStore(filename: TDLibPaths.chatsCacheFilename(accountId: accountId))
            return TelegramRepository(client: client, store: store, chatStore: chatStore)
        } catch {
            throw TelegramRepositoryError.bootstrapFailed(error.localizedDescription)
        }
    }

    func cachedChats() -> [TgChat] {
        (try? chatStore.read()) ?? []
    }

    func setup(apiId: Int, apiHash: String) async throws {
        try await client.configure(apiId: apiId, apiHash: apiHash)
    }

    func authState() -> AuthState {
        client.currentAuthState()
    }

    func submitPhone(_ phone: String) async throws {
        try await client.submitPhone(phone)
    }

    func submitCode(_ code: String) async throws {
        try await client.submitCode(code)
    }

    func submitPassword(_ password: String) async throws {
        try await client.submitPassword(password)
    }

    func loadChats(list: TgChatListKind = .main, limit: Int = 80) async throws -> [TgChat] {
        let remote = try await client.fetchChats(list: list, limit: limit)
        if list == .main {
            try? chatStore.write(chats: remote)
        }
        return remote
    }

    func loadChatPreview(chatId: Int64, listKind: TgChatListKind) async throws -> TgChat? {
        try await client.fetchChat(chatId: chatId, listKind: listKind)
    }

    func loadArchivedChats(limit: Int = 80) async throws -> [TgChat] {
        try await loadChats(list: .archive, limit: limit)
    }

    func loadChatFolders(force: Bool = false) async throws -> [TgChatFolder] {
        try await client.fetchChatFolders(forceRefresh: force)
    }

    func renameChatFolder(folderId: Int32, title: String) async throws {
        try await client.renameChatFolder(folderId: folderId, title: title)
    }

    func addChatToFolder(folderId: Int32, chatId: Int64) async throws {
        try await client.addChatToFolder(folderId: folderId, chatId: chatId)
    }

    func removeChatFromFolder(folderId: Int32, chatId: Int64) async throws {
        try await client.removeChatFromFolder(folderId: folderId, chatId: chatId)
    }

    func loadChatsInFolder(folderId: Int32, limit: Int = 80) async throws -> [TgChat] {
        try await loadChats(list: .folder(folderId), limit: limit)
    }

    func fetchChatFolderIncludedChatIds(folderId: Int32) async throws -> [Int64] {
        try await client.fetchChatFolderIncludedChatIds(folderId: folderId)
    }

    func archiveChat(chatId: Int64) async throws {
        try await client.addChatToList(chatId: chatId, list: .archive)
    }

    func unarchiveChat(chatId: Int64) async throws {
        try await client.removeChatFromList(chatId: chatId, list: .archive)
    }

    func enrichChatAvatars(_ chats: [TgChat]) async throws -> [TgChat] {
        let enriched = try await client.enrichChatsWithAvatarPaths(chats)
        try? chatStore.write(chats: enriched)
        return enriched
    }

    func registerPushDevice(token: Data, sandbox: Bool) async throws {
        try await client.registerPushDevice(token: token, sandbox: sandbox)
    }

    func processPushNotification() async {
        await client.processPushNotification()
    }

    static let initialMessagePageSize = 100
    static let olderMessagePageSize = 40
    static let peekMessagePageSize = 20

    func syncMessages(chatId: Int64, limit: Int = TelegramRepository.initialMessagePageSize) async throws -> [TgMessage] {
        let remote = try await client.fetchMessages(chatId: chatId, limit: limit)
        let persistable = AppSettingsStore.keepDeletedMessagesValue
            ? remote
            : remote.filter { !$0.isDeleted }
        if !persistable.isEmpty {
            try store.upsert(messages: persistable)
            try store.cleanupTemporaryOutgoingDuplicates(chatId: chatId)
        }

        var stored = try store.read(chatId: chatId, limit: 500).sorted { $0.createdAt < $1.createdAt }
        let needsEnrichment = stored.suffix(60).filter(Self.needsDisplayEnrichment)
        if !needsEnrichment.isEmpty {
            let enriched = try await client.enrichMessages(Array(needsEnrichment))
            try store.upsert(messages: enriched)
            stored = try store.read(chatId: chatId, limit: 500).sorted { $0.createdAt < $1.createdAt }
        }

        try await backfillStoredMessageMetadata(chatId: chatId, latestRemote: remote)
        stored = try store.read(chatId: chatId, limit: 500).sorted { $0.createdAt < $1.createdAt }

        return Self.mergeStoredMessages(stored, withRemoteEnrichment: remote)
    }

    private func backfillStoredMessageMetadata(chatId: Int64, latestRemote: [TgMessage]) async throws {
        let remoteIds = Set(latestRemote.map(\.id))
        let stored = try store.read(chatId: chatId, limit: 500)
        let staleIds = stored
            .filter { !remoteIds.contains($0.id) && Self.needsMetadataBackfill($0) }
            .map(\.id)
        guard !staleIds.isEmpty else { return }

        for chunkStart in stride(from: 0, to: staleIds.count, by: 100) {
            let end = min(chunkStart + 100, staleIds.count)
            let chunk = Array(staleIds[chunkStart..<end])
            let refreshed = try await client.fetchMessagesByIds(chatId: chatId, messageIds: chunk)
            if !refreshed.isEmpty {
                try store.upsert(messages: refreshed)
            }
        }
    }

    private static func mergeStoredMessages(_ stored: [TgMessage], withRemoteEnrichment remote: [TgMessage]) -> [TgMessage] {
        guard !remote.isEmpty else { return stored }
        let remoteById = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        return stored.map { message in
            guard let enriched = remoteById[message.id] else { return message }
            return enriched.mergingPreservingDisplayFields(from: message)
        }
    }

    private static func needsDisplayEnrichment(_ message: TgMessage) -> Bool {
        guard !message.isDeleted, !message.outgoing else { return false }
        if let userId = message.senderUserId, userId != 0 {
            if message.senderName == nil || message.senderAvatarPath == nil { return true }
        } else if message.senderName == nil {
            return true
        }
        return false
    }

    private static func needsMetadataBackfill(_ message: TgMessage) -> Bool {
        if message.isDeleted || message.outgoing { return false }
        if message.senderName == nil || message.senderAvatarPath == nil { return true }
        if message.forwardedFrom == nil && message.replyToMessageId == nil && message.senderUserId == nil {
            return true
        }
        return false
    }

    func peekMessages(chatId: Int64, limit: Int = TelegramRepository.peekMessagePageSize) async throws -> [TgMessage] {
        try await client.fetchMessages(chatId: chatId, limit: limit)
    }

    func peekOlderMessages(chatId: Int64, beforeMessageId: Int64, limit: Int = TelegramRepository.olderMessagePageSize) async throws -> [TgMessage] {
        try await client.fetchOlderMessages(chatId: chatId, fromMessageId: beforeMessageId, limit: limit)
    }

    func loadOlderMessages(chatId: Int64, beforeMessageId: Int64) async throws -> [TgMessage] {
        let older = try await client.fetchOlderMessages(chatId: chatId, fromMessageId: beforeMessageId, limit: Self.olderMessagePageSize)
        guard !older.isEmpty else { return [] }
        try store.upsert(messages: older)
        return older.sorted { $0.createdAt < $1.createdAt }
    }

    func loadUserProfilePhotoPaths(userId: Int64) async throws -> [String] {
        try await client.fetchUserProfilePhotoPaths(userId: userId, limit: 100)
    }

    func forwardMessage(fromChatId: Int64, toChatId: Int64, messageId: Int64) async throws {
        try await client.forwardMessages(fromChatId: fromChatId, toChatId: toChatId, messageIds: [messageId])
    }

    func send(chatId: Int64, text: String) async throws {
        try await client.sendMessage(chatId: chatId, text: text, replyToMessageId: nil)
    }

    func sendReply(chatId: Int64, text: String, replyToMessageId: Int64) async throws {
        try await client.sendMessage(chatId: chatId, text: text, replyToMessageId: replyToMessageId)
    }

    func sendPhoto(chatId: Int64, localPath: String, caption: String?, replyToMessageId: Int64?) async throws {
        try await client.sendPhoto(chatId: chatId, localPath: localPath, caption: caption, replyToMessageId: replyToMessageId)
    }

    func sendDocument(chatId: Int64, localPath: String, fileName: String?, mimeType: String?, caption: String?, replyToMessageId: Int64?) async throws {
        try await client.sendDocument(chatId: chatId, localPath: localPath, fileName: fileName, mimeType: mimeType, caption: caption, replyToMessageId: replyToMessageId)
    }

    func sendVoiceNote(chatId: Int64, localPath: String, duration: Int, waveform: [Int], replyToMessageId: Int64?) async throws {
        try await client.sendVoiceNote(chatId: chatId, localPath: localPath, duration: duration, waveform: waveform, replyToMessageId: replyToMessageId)
    }

    func sendVideoNote(chatId: Int64, localPath: String, duration: Int, replyToMessageId: Int64?) async throws {
        try await client.sendVideoNote(chatId: chatId, localPath: localPath, duration: duration, length: 480, replyToMessageId: replyToMessageId)
    }

    func sendSticker(chatId: Int64, sticker: TgSticker, replyToMessageId: Int64?) async throws {
        try await client.sendSticker(chatId: chatId, sticker: sticker, replyToMessageId: replyToMessageId)
    }

    func searchStickers(query: String, limit: Int = 40) async throws -> [TgSticker] {
        try await client.fetchStickerPickerItems(query: query, limit: limit)
    }

    func fetchAvailableReactions(chatId: Int64, messageId: Int64) async throws -> TgAvailableReactions {
        try await client.fetchAvailableReactions(chatId: chatId, messageId: messageId)
    }

    func addReaction(chatId: Int64, messageId: Int64, emoji: String) async throws {
        try await client.addMessageReaction(chatId: chatId, messageId: messageId, emoji: emoji)
    }

    func addReaction(chatId: Int64, messageId: Int64, item: TgReactionPickerItem) async throws {
        try await client.addMessageReaction(chatId: chatId, messageId: messageId, item: item)
    }

    func removeReaction(chatId: Int64, messageId: Int64, reaction: TgMessageReaction) async throws {
        try await client.removeMessageReaction(chatId: chatId, messageId: messageId, reaction: reaction)
    }

    func createGroup(title: String, memberUserIds: [Int64], description: String?) async throws -> Int64 {
        let chatId = try await client.createNewSupergroupChat(title: title, isChannel: false, description: description)
        if !memberUserIds.isEmpty {
            try await client.addChatMembers(chatId: chatId, userIds: memberUserIds)
        }
        return chatId
    }

    func createChannel(title: String, description: String?) async throws -> Int64 {
        try await client.createNewSupergroupChat(title: title, isChannel: true, description: description)
    }

    func openPrivateChat(userId: Int64) async throws -> Int64 {
        try await client.openPrivateChat(userId: userId)
    }

    func openChatByUsername(_ username: String) async throws -> Int64 {
        guard let chat = try await client.searchPublicChat(username: username) else {
            throw NSError(domain: "TelegramRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        return chat.id
    }

    func joinByInviteLink(_ link: String) async throws -> Int64 {
        try await client.joinChatByInviteLink(link)
    }

    func edit(chatId: Int64, messageId: Int64, text: String) async throws {
        try await client.editMessage(chatId: chatId, messageId: messageId, text: text)
    }

    func delete(chatId: Int64, messageIds: [Int64], revoke: Bool) async throws {
        try await client.deleteMessages(chatId: chatId, messageIds: messageIds, revoke: revoke)
    }

    func upsertMessages(_ messages: [TgMessage]) {
        try? store.upsert(messages: messages)
    }

    func storedMessages(chatId: Int64, limit: Int = 500) throws -> [TgMessage] {
        let messages = try store.read(chatId: chatId, limit: limit)
        guard AppSettingsStore.keepDeletedMessagesValue else {
            return messages.filter { !$0.isDeleted }
        }
        return messages
    }

    func purgeDeletedMessages(chatId: Int64) throws {
        try store.purgeDeletedMessages(chatId: chatId)
    }

    func openChat(chatId: Int64) async throws {
        try await client.openChat(chatId: chatId)
    }

    func closeChat(chatId: Int64) async throws {
        try await client.closeChat(chatId: chatId)
    }

    func refreshChatSendPermissions(chatId: Int64) async throws -> (canSend: Bool, reason: String?) {
        try await client.chatSendPermissions(chatId: chatId)
    }

    func pinMessage(chatId: Int64, messageId: Int64) async throws {
        try await client.pinChatMessage(chatId: chatId, messageId: messageId)
    }

    func loadUserProfileDetail(userId: Int64) async throws -> UserProfileDetail {
        try await client.fetchUserProfileDetail(userId: userId)
    }

    func loadUserStories(chatId: Int64) async throws -> [TgStoryItem] {
        try await client.fetchActiveStories(chatId: chatId)
    }

    func loadUserGifts(userId: Int64, limit: Int = 72) async throws -> [TgGiftItem] {
        try await client.fetchReceivedGifts(userId: userId, limit: limit)
    }

    func loadContacts() async throws -> [TgContact] {
        try await client.fetchContacts()
    }

    func importDeviceContacts(_ entries: [(phone: String, firstName: String, lastName: String)]) async throws -> Int {
        try await client.importDeviceContacts(entries)
    }

    func fetchUserDisplayName(userId: Int64) async throws -> String {
        try await client.fetchUserDisplayName(userId: userId)
    }

    func updateUsername(_ username: String) async throws {
        try await client.setUsername(username)
    }

    func uploadProfilePhoto(localPath: String) async throws {
        try await client.setProfilePhoto(localPath: localPath)
    }

    func loadPrivacySettings() async throws -> [UserPrivacySettingValue] {
        try await client.fetchUserPrivacySettings()
    }

    func updatePrivacySetting(kind: UserPrivacySettingKind, visibility: PrivacyVisibility) async throws {
        try await client.setUserPrivacySetting(kind: kind, visibility: visibility)
    }

    func searchMessagesGlobally(query: String) async throws -> [GlobalSearchMessageHit] {
        try await client.searchMessagesGlobally(query: query, limit: 40)
    }

    func searchChats(query: String) async throws -> [TgChat] {
        try await client.searchChats(query: query, limit: 30)
    }

    func searchPublicChats(query: String) async throws -> [TgChat] {
        try await client.searchPublicChats(query: query)
    }

    func updateProfileName(firstName: String, lastName: String) async throws {
        try await client.setName(firstName: firstName, lastName: lastName)
    }

    static let mediaDownloadRecentMessageLimit = 24
    static let mediaDownloadConcurrency = 2

    func downloadMedia(
        chatId: Int64,
        recentMessageLimit: Int = TelegramRepository.mediaDownloadRecentMessageLimit
    ) async throws -> [TgMessage] {
        let current = try store.read(chatId: chatId, limit: 500).sorted { $0.createdAt < $1.createdAt }
        let recent = Array(current.suffix(recentMessageLimit))

        struct DownloadJob {
            let messageId: Int64
            let fileId: Int64
        }

        var jobs: [DownloadJob] = []
        jobs.reserveCapacity(recent.count * 2)
        for message in recent {
            for attachment in message.attachments {
                guard (attachment.localPath?.isEmpty ?? true), let fileId = attachment.fileId else { continue }
                jobs.append(DownloadJob(messageId: message.id, fileId: fileId))
            }
        }

        guard !jobs.isEmpty else {
            return current
        }

        var iterator = jobs.makeIterator()
        await withTaskGroup(of: (Int64, Int64, String?).self) { group in
            var inFlight = 0

            func enqueueNext() {
                guard let job = iterator.next() else { return }
                inFlight += 1
                group.addTask { [client] in
                    let path = try? await client.downloadFile(fileId: job.fileId)
                    return (job.messageId, job.fileId, path)
                }
            }

            let initial = min(Self.mediaDownloadConcurrency, jobs.count)
            for _ in 0..<initial {
                enqueueNext()
            }

            for await result in group {
                inFlight -= 1
                if let path = result.2, !path.isEmpty {
                    try? store.setAttachmentLocalPath(
                        chatId: chatId,
                        messageId: result.0,
                        fileId: result.1,
                        localPath: path
                    )
                }
                if inFlight < Self.mediaDownloadConcurrency {
                    enqueueNext()
                }
            }
        }

        return try store.read(chatId: chatId, limit: 500).sorted { $0.createdAt < $1.createdAt }
    }

    func loadChatProfile(chatId: Int64) async throws -> ChatProfile {
        try await client.fetchChatProfile(chatId: chatId)
    }

    func loadChatMembers(chatId: Int64) async throws -> [ChatMember] {
        try await client.fetchChatMembers(chatId: chatId, limit: 80)
    }

    func loadChatMedia(chatId: Int64) async throws -> [TgMessage] {
        let media = try await client.fetchChatMedia(chatId: chatId, limit: 200)
        try store.upsert(messages: media)
        // Do not block profile UI by eagerly downloading all media files.
        // Files will download on-demand when opened (or via background message downloader).
        return try store.read(chatId: chatId).filter { !$0.attachments.isEmpty || $0.text.containsURL }
    }

    func markChatRead(chatId: Int64) async throws {
        let localMessages = try store.read(chatId: chatId)
        let ids = localMessages.map(\.id)
        try await client.markChatRead(chatId: chatId, messageIds: ids)
    }

    func markChatUnread(chatId: Int64, unread: Bool) async throws {
        try await client.markChatUnread(chatId: chatId, unread: unread)
    }

    func setChatPinned(chatId: Int64, pinned: Bool, list: TgChatListKind = .main) async throws {
        try await client.setChatPinned(chatId: chatId, pinned: pinned, list: list)
    }

    func reorderPinnedChats(chatIds: [Int64], list: TgChatListKind = .main) async throws {
        try await client.reorderPinnedChats(chatIds: chatIds, list: list)
    }

    func setChatMute(chatId: Int64, duration: ChatMuteDuration) async throws {
        try await client.setChatMute(chatId: chatId, duration: duration)
    }

    func clearChatHistory(chatId: Int64) async throws {
        try await client.clearChatHistory(chatId: chatId)
    }

    func deleteChat(chatId: Int64) async throws {
        try await client.deleteChat(chatId: chatId)
    }

    func leaveChat(chatId: Int64) async throws {
        try await client.leaveChat(chatId: chatId)
    }

    func loadMe() async throws -> TgUser {
        try await client.getMe()
    }

    func setUserBlocked(userId: Int64, isBlocked: Bool) async throws {
        try await client.setUserBlocked(userId: userId, isBlocked: isBlocked)
    }
}

private extension String {
    var containsURL: Bool {
        localizedCaseInsensitiveContains("http://")
            || localizedCaseInsensitiveContains("https://")
            || localizedCaseInsensitiveContains("t.me/")
    }
}
