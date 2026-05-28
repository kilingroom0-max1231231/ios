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
    var onAuthStateChanged: ((AuthState) -> Void)?
    var onMessagesChanged: ((Int64) -> Void)?
    var onChatsChanged: (() -> Void)?
    var onChatChanged: ((Int64) -> Void)?
    var onTypingChanged: ((Int64, String?) -> Void)?
    var onIncomingMessage: ((TgMessage) -> Void)?
    var onMessageReplaced: ((Int64, Int64, TgMessage) -> Void)?
    var onChatReadOutboxChanged: ((Int64, Int64) -> Void)?

    init(client: TelegramClientProtocol, store: LocalMessageStore) {
        self.client = client
        self.store = store
        self.client.setEventHandler { [weak self] event in
            guard let self else { return }
            switch event {
            case .authChanged(let state):
                self.onAuthStateChanged?(state)
            case .newMessage(let message):
                try? self.store.upsert(messages: [message])
                try? self.store.cleanupTemporaryOutgoingDuplicates(chatId: message.chatId)
                self.onIncomingMessage?(message)
                self.onMessagesChanged?(message.chatId)
                self.onChatChanged?(message.chatId)
            case .messageReplaced(let chatId, let oldMessageId, let newMessage):
                try? self.store.deleteMessage(chatId: chatId, messageId: oldMessageId)
                try? self.store.upsert(messages: [newMessage])
                try? self.store.cleanupTemporaryOutgoingDuplicates(chatId: chatId)
                self.onMessageReplaced?(chatId, oldMessageId, newMessage)
                self.onMessagesChanged?(chatId)
                self.onChatChanged?(chatId)
            case .chatReadOutboxChanged(let chatId, let lastRead):
                self.onChatReadOutboxChanged?(chatId, lastRead)
                self.onChatChanged?(chatId)
            case .messagesDeleted(let chatId, let messageIds):
                try? self.store.markDeleted(chatId: chatId, messageIds: messageIds)
                self.onMessagesChanged?(chatId)
                self.onChatChanged?(chatId)
            case .chatsChanged:
                self.onChatsChanged?()
            case .chatChanged(let chatId):
                self.onChatChanged?(chatId)
            case .chatTypingChanged(let chatId, let text):
                self.onTypingChanged?(chatId, text)
            }
        }
    }

    static func bootstrap() throws -> TelegramRepository {
        do {
            let client = try TDLibClient()
            let store = try LocalMessageStore()
            return TelegramRepository(client: client, store: store)
        } catch {
            throw TelegramRepositoryError.bootstrapFailed(error.localizedDescription)
        }
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

    func loadChats() async throws -> [TgChat] {
        try await client.fetchChats(limit: 200)
    }

    static let initialMessagePageSize = 20
    static let olderMessagePageSize = 40
    static let peekMessagePageSize = 20

    func syncMessages(chatId: Int64, limit: Int = TelegramRepository.initialMessagePageSize) async throws -> [TgMessage] {
        let remote = try await client.fetchMessages(chatId: chatId, limit: limit)
        try store.upsert(messages: remote)
        try store.cleanupTemporaryOutgoingDuplicates(chatId: chatId)
        return remote.sorted { $0.createdAt < $1.createdAt }
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

    func send(chatId: Int64, text: String) async throws -> [TgMessage] {
        try await client.sendMessage(chatId: chatId, text: text, replyToMessageId: nil)
        return try await syncMessages(chatId: chatId)
    }

    func sendReply(chatId: Int64, text: String, replyToMessageId: Int64) async throws -> [TgMessage] {
        try await client.sendMessage(chatId: chatId, text: text, replyToMessageId: replyToMessageId)
        return try await syncMessages(chatId: chatId)
    }

    func edit(chatId: Int64, messageId: Int64, text: String) async throws -> [TgMessage] {
        try await client.editMessage(chatId: chatId, messageId: messageId, text: text)
        return try await syncMessages(chatId: chatId)
    }

    func delete(chatId: Int64, messageIds: [Int64], revoke: Bool) async throws -> [TgMessage] {
        try store.markDeleted(chatId: chatId, messageIds: messageIds)
        try await client.deleteMessages(chatId: chatId, messageIds: messageIds, revoke: revoke)
        return try store.read(chatId: chatId)
    }

    func downloadMedia(chatId: Int64) async throws -> [TgMessage] {
        let current = try store.read(chatId: chatId)
        for message in current {
            for attachment in message.attachments {
                guard (attachment.localPath?.isEmpty ?? true), let fileId = attachment.fileId else { continue }
                if let path = try await client.downloadFile(fileId: fileId) {
                    try store.setAttachmentLocalPath(chatId: chatId, messageId: message.id, fileId: fileId, localPath: path)
                }
            }
        }
        return try store.read(chatId: chatId)
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

    func setChatPinned(chatId: Int64, pinned: Bool) async throws {
        try await client.setChatPinned(chatId: chatId, pinned: pinned)
    }

    func reorderPinnedChats(chatIds: [Int64]) async throws {
        try await client.reorderPinnedChats(chatIds: chatIds)
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

    func loadPrivacySettings() async throws -> [UserPrivacySettingValue] {
        var values: [UserPrivacySettingValue] = []
        for kind in UserPrivacySettingKind.allCases {
            let visibility = try await client.fetchPrivacyVisibility(for: kind)
            values.append(UserPrivacySettingValue(kind: kind, visibility: visibility))
        }
        return values
    }

    func updatePrivacySetting(_ kind: UserPrivacySettingKind, visibility: PrivacyVisibility) async throws {
        try await client.setPrivacyVisibility(for: kind, visibility: visibility)
    }

    func updateMyProfile(firstName: String, lastName: String, username: String) async throws -> TgUser {
        try await client.setMyName(firstName: firstName, lastName: lastName)
        try await client.setMyUsername(username)
        return try await client.getMe()
    }
}

private extension String {
    var containsURL: Bool {
        localizedCaseInsensitiveContains("http://")
            || localizedCaseInsensitiveContains("https://")
            || localizedCaseInsensitiveContains("t.me/")
    }
}
