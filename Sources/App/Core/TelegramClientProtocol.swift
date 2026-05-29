import Foundation

protocol TelegramClientProtocol {
    func configure(apiId: Int, apiHash: String) async throws
    func currentAuthState() -> AuthState
    func setEventHandler(_ handler: @escaping (TelegramEvent) -> Void)
    func submitPhone(_ phone: String) async throws
    func submitCode(_ code: String) async throws
    func submitPassword(_ password: String) async throws

    func fetchChats(limit: Int) async throws -> [TgChat]
    func fetchMessages(chatId: Int64, limit: Int) async throws -> [TgMessage]
    func fetchOlderMessages(chatId: Int64, fromMessageId: Int64, limit: Int) async throws -> [TgMessage]
    func enrichMessages(_ messages: [TgMessage]) async throws -> [TgMessage]
    func forwardMessages(fromChatId: Int64, toChatId: Int64, messageIds: [Int64]) async throws
    func sendMessage(chatId: Int64, text: String, replyToMessageId: Int64?) async throws
    func editMessage(chatId: Int64, messageId: Int64, text: String) async throws
    func deleteMessages(chatId: Int64, messageIds: [Int64], revoke: Bool) async throws
    func downloadFile(fileId: Int64) async throws -> String?
    func fetchChatProfile(chatId: Int64) async throws -> ChatProfile
    func fetchChatMembers(chatId: Int64, limit: Int) async throws -> [ChatMember]
    func fetchChatMedia(chatId: Int64, limit: Int) async throws -> [TgMessage]
    func openChat(chatId: Int64) async throws
    func closeChat(chatId: Int64) async throws
    func markChatRead(chatId: Int64, messageIds: [Int64]) async throws
    func markChatUnread(chatId: Int64, unread: Bool) async throws
    func setChatPinned(chatId: Int64, pinned: Bool) async throws
    func reorderPinnedChats(chatIds: [Int64]) async throws
    func setChatMute(chatId: Int64, duration: ChatMuteDuration) async throws
    func clearChatHistory(chatId: Int64) async throws
    func deleteChat(chatId: Int64) async throws
    func leaveChat(chatId: Int64) async throws

    func getMe() async throws -> TgUser
    func setUserBlocked(userId: Int64, isBlocked: Bool) async throws
    func fetchUserProfilePhotoPaths(userId: Int64, limit: Int) async throws -> [String]
    func searchChats(query: String, limit: Int) async throws -> [TgChat]
    func searchPublicChats(query: String) async throws -> [TgChat]
    func setName(firstName: String, lastName: String) async throws
    func setUsername(_ username: String) async throws
    func setProfilePhoto(localPath: String) async throws
    func fetchUserPrivacySettings() async throws -> [UserPrivacySettingValue]
    func setUserPrivacySetting(kind: UserPrivacySettingKind, visibility: PrivacyVisibility) async throws
    func searchMessagesGlobally(query: String, limit: Int) async throws -> [GlobalSearchMessageHit]
    func fetchUserDisplayName(userId: Int64) async throws -> String
    func chatSendPermissions(chatId: Int64) async throws -> (canSend: Bool, reason: String?)
    func pinChatMessage(chatId: Int64, messageId: Int64) async throws
    func fetchUserProfileDetail(userId: Int64) async throws -> UserProfileDetail
    func fetchActiveStories(chatId: Int64) async throws -> [TgStoryItem]
    func fetchReceivedGifts(userId: Int64, limit: Int) async throws -> [TgGiftItem]
}
