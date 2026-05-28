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
    func sendMessage(chatId: Int64, text: String, replyToMessageId: Int64?) async throws
    func editMessage(chatId: Int64, messageId: Int64, text: String) async throws
    func deleteMessages(chatId: Int64, messageIds: [Int64], revoke: Bool) async throws
    func downloadFile(fileId: Int64) async throws -> String?
    func fetchChatProfile(chatId: Int64) async throws -> ChatProfile
    func fetchChatMembers(chatId: Int64, limit: Int) async throws -> [ChatMember]
    func fetchChatMedia(chatId: Int64, limit: Int) async throws -> [TgMessage]
    func markChatRead(chatId: Int64, messageIds: [Int64]) async throws
    func markChatUnread(chatId: Int64, unread: Bool) async throws
    func setChatPinned(chatId: Int64, pinned: Bool) async throws
    func reorderPinnedChats(chatIds: [Int64]) async throws
    func setChatMute(chatId: Int64, duration: ChatMuteDuration) async throws
    func clearChatHistory(chatId: Int64) async throws
    func deleteChat(chatId: Int64) async throws
    func leaveChat(chatId: Int64) async throws
}
