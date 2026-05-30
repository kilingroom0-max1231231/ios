import Foundation

protocol TelegramClientProtocol {
    func configure(apiId: Int, apiHash: String) async throws
    func currentAuthState() -> AuthState
    func setEventHandler(_ handler: @escaping (TelegramEvent) -> Void)
    func submitPhone(_ phone: String) async throws
    func submitCode(_ code: String) async throws
    func submitPassword(_ password: String) async throws

    func fetchChats(list: TgChatListKind, limit: Int) async throws -> [TgChat]
    func fetchChat(chatId: Int64, listKind: TgChatListKind) async throws -> TgChat?
    func fetchChatDetails(chatId: Int64, listKind: TgChatListKind) async throws -> TgChat?
    func fetchChatFolders(forceRefresh: Bool) async throws -> [TgChatFolder]
    func fetchChatFolderIncludedChatIds(folderId: Int32) async throws -> [Int64]
    func renameChatFolder(folderId: Int32, title: String) async throws
    func addChatToFolder(folderId: Int32, chatId: Int64) async throws
    func removeChatFromFolder(folderId: Int32, chatId: Int64) async throws
    func addChatToList(chatId: Int64, list: TgChatListKind) async throws
    func removeChatFromList(chatId: Int64, list: TgChatListKind) async throws
    func fetchMessages(chatId: Int64, limit: Int) async throws -> [TgMessage]
    func fetchOlderMessages(chatId: Int64, fromMessageId: Int64, limit: Int) async throws -> [TgMessage]
    func fetchMessagesByIds(chatId: Int64, messageIds: [Int64]) async throws -> [TgMessage]
    func enrichMessages(_ messages: [TgMessage]) async throws -> [TgMessage]
    func forwardMessages(fromChatId: Int64, toChatId: Int64, messageIds: [Int64]) async throws
    func sendMessage(chatId: Int64, text: String, replyToMessageId: Int64?) async throws
    func sendPhoto(chatId: Int64, localPath: String, caption: String?, replyToMessageId: Int64?) async throws
    func sendDocument(chatId: Int64, localPath: String, fileName: String?, mimeType: String?, caption: String?, replyToMessageId: Int64?) async throws
    func sendVoiceNote(chatId: Int64, localPath: String, duration: Int, waveform: [Int], replyToMessageId: Int64?) async throws
    func sendVideoNote(chatId: Int64, localPath: String, duration: Int, length: Int, replyToMessageId: Int64?) async throws
    func sendSticker(chatId: Int64, sticker: TgSticker, replyToMessageId: Int64?) async throws
    func fetchStickerPickerItems(query: String, limit: Int) async throws -> [TgSticker]
    func searchStickerSets(query: String, limit: Int) async throws -> [TgSticker]
    func fetchAvailableReactions(chatId: Int64, messageId: Int64) async throws -> TgAvailableReactions
    func addMessageReaction(chatId: Int64, messageId: Int64, emoji: String) async throws
    func addMessageReaction(chatId: Int64, messageId: Int64, item: TgReactionPickerItem) async throws
    func removeMessageReaction(chatId: Int64, messageId: Int64, reaction: TgMessageReaction) async throws
    func createNewSupergroupChat(title: String, isChannel: Bool, description: String?) async throws -> Int64
    func addChatMembers(chatId: Int64, userIds: [Int64]) async throws
    func openPrivateChat(userId: Int64) async throws -> Int64
    func searchPublicChat(username: String) async throws -> TgChat?
    func joinChatByInviteLink(_ inviteLink: String) async throws -> Int64
    func editMessage(chatId: Int64, messageId: Int64, text: String) async throws
    func deleteMessages(chatId: Int64, messageIds: [Int64], revoke: Bool) async throws
    func downloadFile(fileId: Int64) async throws -> String?
    func fetchChatProfile(chatId: Int64) async throws -> ChatProfile
    func chatPeerIsBot(chatId: Int64) async throws -> Bool
    func fetchChatMembers(chatId: Int64, limit: Int) async throws -> [ChatMember]
    func fetchChatMedia(chatId: Int64, limit: Int) async throws -> [TgMessage]
    func openChat(chatId: Int64) async throws
    func closeChat(chatId: Int64) async throws
    func markChatRead(chatId: Int64, messageIds: [Int64]) async throws
    func markChatUnread(chatId: Int64, unread: Bool) async throws
    func setChatPinned(chatId: Int64, pinned: Bool, list: TgChatListKind) async throws
    func reorderPinnedChats(chatIds: [Int64], list: TgChatListKind) async throws
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
    func chatInteractionPermissions(chatId: Int64) async throws -> (canSend: Bool, canAddReactions: Bool, reason: String?)
    func pinChatMessage(chatId: Int64, messageId: Int64) async throws
    func fetchUserProfileDetail(userId: Int64) async throws -> UserProfileDetail
    func fetchActiveStories(chatId: Int64) async throws -> [TgStoryItem]
    func fetchReceivedGifts(userId: Int64, limit: Int) async throws -> [TgGiftItem]
    func fetchContacts() async throws -> [TgContact]
    func fetchActiveSessions() async throws -> [TgActiveSession]
    func terminateSession(sessionId: Int64) async throws
    func terminateAllOtherSessions() async throws
    func importDeviceContacts(_ entries: [(phone: String, firstName: String, lastName: String)]) async throws -> Int
    func enrichChatsWithAvatarPaths(_ chats: [TgChat]) async throws -> [TgChat]
    func enrichChatsWithPremiumBadges(_ chats: [TgChat]) async throws -> [TgChat]
    func enrichChatsWithMemberStatus(_ chats: [TgChat]) async throws -> [TgChat]
    func registerPushDevice(token: Data, sandbox: Bool) async throws
    func processPushNotification() async
}
