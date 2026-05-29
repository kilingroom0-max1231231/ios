import Foundation

final class TDLibClient: TelegramClientProtocol, @unchecked Sendable {
    private let bridge: TDLibBridge
    private let accountId: String
    private let syncQueue = DispatchQueue(label: "tdlib.client.sync")

    private var authState: AuthState = .waitPhone
    private var lastAuthorizationStateType = ""
    private var eventHandler: ((TelegramEvent) -> Void)?
    private var receiveLoopTask: Task<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var authorizationWaiters: [AuthStateWaiter] = []
    private var cachedMyUserId: Int64?
    private var userInfoCache: [Int64: (name: String, avatarPath: String?, isPremium: Bool, premiumBadgePath: String?)] = [:]
    private var customEmojiPathCache: [Int64: String] = [:]
    private var cachedChatFolders: [TgChatFolder] = []

    init(accountId: String = "default") throws {
        self.accountId = accountId
        self.bridge = try TDLibBridge()
    }

    func configure(apiId: Int, apiHash: String) async throws {
        guard apiId > 0, apiId <= Int(Int32.max), apiHash.count == 32 else {
            throw TDLibClientError.invalidApiCredentials
        }

        startReceiveLoopIfNeeded()
        setLogVerbosityLevel(1)

        try await waitForAuthorizationState("authorizationStateWaitTdlibParameters", timeout: 60)

        let databaseDirectory = try TDLibPaths.databaseDirectory(accountId: accountId)
        let filesDirectory = try TDLibPaths.filesDirectory(accountId: accountId)

        // TDLib 1.8.6+ requires flat fields at root — nested "parameters" makes api_id=0.
        _ = try await sendRequest([
            "@type": "setTdlibParameters",
            "use_test_dc": false,
            "database_directory": databaseDirectory,
            "files_directory": filesDirectory,
            "database_encryption_key": "",
            "use_file_database": true,
            "use_chat_info_database": true,
            "use_message_database": true,
            "use_secret_chats": false,
            "api_id": apiId,
            "api_hash": apiHash,
            "system_language_code": "ru",
            "device_model": "iPhone",
            "system_version": "iOS",
            "application_version": "1.0",
            "enable_storage_optimizer": true,
            "ignore_file_names": false
        ])

        try await waitForAuthorizationState(
            matching: [
                "authorizationStateWaitEncryptionKey",
                "authorizationStateWaitPhoneNumber",
                "authorizationStateWaitCode",
                "authorizationStateWaitPassword",
                "authorizationStateReady"
            ],
            timeout: 60
        )

        if currentAuthorizationStateType() == "authorizationStateWaitEncryptionKey" {
            _ = try await sendRequest([
                "@type": "checkDatabaseEncryptionKey",
                "encryption_key": ""
            ])
            try await waitForAuthorizationState(
                matching: [
                    "authorizationStateWaitPhoneNumber",
                    "authorizationStateWaitCode",
                    "authorizationStateWaitPassword",
                    "authorizationStateReady"
                ],
                timeout: 60
            )
        }
    }

    private func setLogVerbosityLevel(_ level: Int) {
        let payload = """
        {"@type":"setLogVerbosityLevel","new_verbosity_level":\(level)}
        """
        bridge.send(payload)
    }

    func currentAuthState() -> AuthState {
        authState
    }

    func setEventHandler(_ handler: @escaping (TelegramEvent) -> Void) {
        eventHandler = handler
    }

    func submitPhone(_ phone: String) async throws {
        _ = try await sendRequest([
            "@type": "setAuthenticationPhoneNumber",
            "phone_number": phone
        ])
    }

    func submitCode(_ code: String) async throws {
        _ = try await sendRequest([
            "@type": "checkAuthenticationCode",
            "code": code
        ])
    }

    func submitPassword(_ password: String) async throws {
        _ = try await sendRequest([
            "@type": "checkAuthenticationPassword",
            "password": password
        ])
    }

    func fetchChats(list: TgChatListKind = .main, limit: Int = 50) async throws -> [TgChat] {
        let response = try await sendRequest([
            "@type": "getChats",
            "chat_list": list.tdlibDictionary,
            "limit": limit
        ])
        guard let ids = response["chat_ids"] as? [Any] else { return [] }

        var chats: [TgChat] = []
        for anyId in ids {
            guard let id = int64Value(anyId) else { continue }
            let chatResp = try await sendRequest([
                "@type": "getChat",
                "chat_id": id
            ])
            if let chat = try await parseChatSummary(chatResp, listKind: list) {
                chats.append(chat)
            }
        }
        return chats.sorted(by: chatSort)
    }

    func fetchChatFolders(forceRefresh: Bool = false) async throws -> [TgChatFolder] {
        if !forceRefresh {
            let cached = syncQueue.sync { cachedChatFolders }
            if !cached.isEmpty {
                return cached
            }
        }

        let response = try await sendRequest(["@type": "getChatFolders"])
        var parsed = try await resolveChatFolders(from: response)
        parsed = await enrichChatFoldersWithDetails(parsed)
        syncQueue.async { [parsed] in
            self.cachedChatFolders = parsed
        }
        return parsed
    }

    func fetchChatFolderIncludedChatIds(folderId: Int32) async throws -> [Int64] {
        let folder = try await sendRequest([
            "@type": "getChatFolder",
            "chat_folder_id": NSNumber(value: folderId)
        ])
        let included = folder["included_chat_ids"] as? [Any] ?? []
        return included.compactMap(int64Value)
    }

    func renameChatFolder(folderId: Int32, title: String) async throws {
        var folder = try await sendRequest([
            "@type": "getChatFolder",
            "chat_folder_id": NSNumber(value: folderId)
        ])
        folder["name"] = chatFolderNameDict(title)
        _ = try await sendRequest([
            "@type": "editChatFolder",
            "chat_folder_id": NSNumber(value: folderId),
            "folder": chatFolderPayload(from: folder)
        ])
        invalidateChatFoldersCache()
    }

    func addChatToFolder(folderId: Int32, chatId: Int64) async throws {
        var folder = try await sendRequest([
            "@type": "getChatFolder",
            "chat_folder_id": NSNumber(value: folderId)
        ])
        var included = (folder["included_chat_ids"] as? [Any])?.compactMap(int64Value) ?? []
        if !included.contains(chatId) {
            included.append(chatId)
        }
        folder["included_chat_ids"] = included.map { NSNumber(value: $0) }
        var excluded = (folder["excluded_chat_ids"] as? [Any])?.compactMap(int64Value) ?? []
        excluded.removeAll { $0 == chatId }
        folder["excluded_chat_ids"] = excluded.map { NSNumber(value: $0) }
        _ = try await sendRequest([
            "@type": "editChatFolder",
            "chat_folder_id": NSNumber(value: folderId),
            "folder": chatFolderPayload(from: folder)
        ])
        _ = try? await addChatToList(chatId: chatId, list: .folder(folderId))
        invalidateChatFoldersCache()
    }

    func removeChatFromFolder(folderId: Int32, chatId: Int64) async throws {
        var folder = try await sendRequest([
            "@type": "getChatFolder",
            "chat_folder_id": NSNumber(value: folderId)
        ])
        var included = (folder["included_chat_ids"] as? [Any])?.compactMap(int64Value) ?? []
        included.removeAll { $0 == chatId }
        folder["included_chat_ids"] = included.map { NSNumber(value: $0) }
        _ = try await sendRequest([
            "@type": "editChatFolder",
            "chat_folder_id": NSNumber(value: folderId),
            "folder": chatFolderPayload(from: folder)
        ])
        _ = try? await removeChatFromList(chatId: chatId, list: .folder(folderId))
        invalidateChatFoldersCache()
    }

    private func invalidateChatFoldersCache() {
        syncQueue.async {
            self.cachedChatFolders = []
        }
    }

    private func chatFolderNameDict(_ title: String) -> [String: Any] {
        [
            "@type": "chatFolderName",
            "text": formattedTextDict(title),
            "animate_custom_emoji": false
        ]
    }

    private func chatFolderPayload(from folder: [String: Any]) -> [String: Any] {
        var payload = folder
        if (payload["@type"] as? String) != "chatFolder" {
            payload["@type"] = "chatFolder"
        }
        return payload
    }

    private func enrichChatFoldersWithDetails(_ folders: [TgChatFolder]) async -> [TgChatFolder] {
        var result: [TgChatFolder] = []
        for folder in folders {
            if !isGenericFolderTitle(folder.title) {
                result.append(folder)
                continue
            }
            if let full = try? await sendRequest([
                "@type": "getChatFolder",
                "chat_folder_id": NSNumber(value: folder.id)
            ]), let detailed = parseChatFolder(full, folderId: folder.id) {
                result.append(detailed)
            } else {
                result.append(folder)
            }
        }
        return result
    }

    private func isGenericFolderTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed == AppText.tr("Папка", "Folder")
            || trimmed == "Folder"
    }

    private func chatFoldersPayload(from response: [String: Any]) -> [String: Any] {
        if (response["@type"] as? String) == "chatFolders" {
            return response
        }
        if let nested = response["chat_folders"] as? [String: Any] {
            return nested
        }
        return response
    }

    private func loadChatFoldersFromInfos(_ infos: [[String: Any]]) async -> [TgChatFolder] {
        var result: [TgChatFolder] = []
        var seen = Set<Int32>()
        for info in infos {
            guard let id = int32Value(info["id"]), seen.insert(id).inserted else { continue }
            if let full = try? await sendRequest([
                "@type": "getChatFolder",
                "chat_folder_id": NSNumber(value: id)
            ]), let folder = parseChatFolder(full, folderId: id) {
                result.append(folder)
            } else if let folder = parseChatFolder(info) {
                result.append(folder)
            }
        }
        return result
    }

    func addChatToList(chatId: Int64, list: TgChatListKind) async throws {
        _ = try await sendRequest([
            "@type": "addChatToList",
            "chat_id": chatId,
            "chat_list": list.tdlibDictionary
        ])
    }

    func removeChatFromList(chatId: Int64, list: TgChatListKind) async throws {
        _ = try await sendRequest([
            "@type": "removeChatFromList",
            "chat_id": chatId,
            "chat_list": list.tdlibDictionary
        ])
    }

    func enrichChatsWithAvatarPaths(_ chats: [TgChat]) async throws -> [TgChat] {
        let targets = chats.filter {
            $0.kind != .savedMessages && ($0.avatarPath?.isEmpty ?? true)
        }
        guard !targets.isEmpty else { return chats }

        var pathsByChatId: [Int64: String] = [:]
        pathsByChatId.reserveCapacity(targets.count)

        let batchSize = 6
        var index = targets.startIndex
        while index < targets.endIndex {
            let end = targets.index(index, offsetBy: batchSize, limitedBy: targets.endIndex) ?? targets.endIndex
            let batch = Array(targets[index..<end])
            await withTaskGroup(of: (Int64, String?).self) { group in
                for chat in batch {
                    group.addTask { [weak self] in
                        guard let self else { return (chat.id, nil) }
                        guard let chatResp = try? await self.sendRequest([
                            "@type": "getChat",
                            "chat_id": chat.id
                        ]) else {
                            return (chat.id, nil)
                        }
                        let path = try? await self.resolveChatAvatarPath(chatResp, downloadIfMissing: true)
                        return (chat.id, path)
                    }
                }
                for await (chatId, path) in group {
                    if let path, !path.isEmpty {
                        pathsByChatId[chatId] = path
                    }
                }
            }
            index = end
        }

        return chats.map { chat in
            guard let path = pathsByChatId[chat.id] else { return chat }
            var updated = chat
            updated.avatarPath = path
            return updated
        }
    }

    func enrichChatsWithPremiumBadges(_ chats: [TgChat]) async throws -> [TgChat] {
        let targets = chats.filter {
            $0.kind == .private && $0.peerIsPremium && ($0.peerPremiumBadgePath?.isEmpty ?? true)
        }
        guard !targets.isEmpty else { return chats }

        var pathsByChatId: [Int64: String] = [:]
        pathsByChatId.reserveCapacity(targets.count)

        let batchSize = 4
        var index = targets.startIndex
        while index < targets.endIndex {
            let end = targets.index(index, offsetBy: batchSize, limitedBy: targets.endIndex) ?? targets.endIndex
            let batch = Array(targets[index..<end])
            await withTaskGroup(of: (Int64, String?).self) { group in
                for chat in batch {
                    guard let userId = chat.privateUserId else { continue }
                    group.addTask { [weak self] in
                        guard let self else { return (chat.id, nil) }
                        guard let meta = try? await self.loadUserMeta(userId: userId),
                              let path = meta.premiumBadgePath,
                              !path.isEmpty else {
                            return (chat.id, nil)
                        }
                        return (chat.id, path)
                    }
                }
                for await (chatId, path) in group {
                    if let path, !path.isEmpty {
                        pathsByChatId[chatId] = path
                    }
                }
            }
            index = end
        }

        return chats.map { chat in
            guard let path = pathsByChatId[chat.id] else { return chat }
            var updated = chat
            updated.peerPremiumBadgePath = path
            return updated
        }
    }

    func registerPushDevice(token: Data, sandbox: Bool) async throws {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        _ = try await sendRequest([
            "@type": "registerDevice",
            "token": tokenString,
            "other_user_ids": [],
            "are_push_notifications_enabled": true
        ])
        _ = sandbox
    }

    func processPushNotification() async {
        _ = try? await sendRequest([
            "@type": "processPushNotification"
        ])
    }

    func fetchMessages(chatId: Int64, limit: Int = 500) async throws -> [TgMessage] {
        let response = try await sendRequest([
            "@type": "getChatHistory",
            "chat_id": chatId,
            "limit": limit,
            "from_message_id": 0,
            "offset": 0,
            "only_local": false
        ])
        guard let items = response["messages"] as? [[String: Any]] else { return [] }
        let parsed = items.compactMap { parseMessage($0, fallbackChatId: chatId) }
        let enriched = try await enrichMessagesWithSenderInfo(parsed)
        let withReadState = try await applyReadOutboxStatus(messages: enriched, chatId: chatId)
        return withReadState.sorted(by: { $0.createdAt < $1.createdAt })
    }

    func enrichMessages(_ messages: [TgMessage]) async throws -> [TgMessage] {
        try await enrichMessagesWithSenderInfo(messages)
    }

    func fetchOlderMessages(chatId: Int64, fromMessageId: Int64, limit: Int = 200) async throws -> [TgMessage] {
        let response = try await sendRequest([
            "@type": "getChatHistory",
            "chat_id": chatId,
            "limit": limit,
            "from_message_id": fromMessageId,
            "offset": 0,
            "only_local": false
        ])
        guard let items = response["messages"] as? [[String: Any]] else { return [] }
        let parsed = items.compactMap { parseMessage($0, fallbackChatId: chatId) }
        let enriched = try await enrichMessagesWithSenderInfo(parsed)
        let withReadState = try await applyReadOutboxStatus(messages: enriched, chatId: chatId)
        return withReadState.sorted(by: { $0.createdAt < $1.createdAt })
    }

    func fetchMessagesByIds(chatId: Int64, messageIds: [Int64]) async throws -> [TgMessage] {
        guard !messageIds.isEmpty else { return [] }
        let response = try await sendRequest([
            "@type": "getMessages",
            "chat_id": chatId,
            "message_ids": messageIds
        ])
        guard let items = response["messages"] as? [[String: Any]] else { return [] }
        let parsed = items.compactMap { parseMessage($0, fallbackChatId: chatId) }
        let enriched = try await enrichMessagesWithSenderInfo(parsed)
        return try await applyReadOutboxStatus(messages: enriched, chatId: chatId)
    }

    func forwardMessages(fromChatId: Int64, toChatId: Int64, messageIds: [Int64]) async throws {
        guard !messageIds.isEmpty else { return }
        _ = try await sendRequest([
            "@type": "forwardMessages",
            "from_chat_id": fromChatId,
            "chat_id": toChatId,
            "message_ids": messageIds,
            "send_copy": false,
            "remove_caption": false,
            "only_preview": false
        ])
    }

    func sendMessage(chatId: Int64, text: String, replyToMessageId: Int64?) async throws {
        var body: [String: Any] = [
            "@type": "sendMessage",
            "chat_id": chatId,
            "input_message_content": [
                "@type": "inputMessageText",
                "text": [
                    "@type": "formattedText",
                    "text": text
                ]
            ]
        ]

        if let replyToMessageId {
            body["reply_to"] = [
                "@type": "inputMessageReplyToMessage",
                "message_id": replyToMessageId
            ]
        }

        _ = try await sendRequest(body)
    }

    func sendPhoto(chatId: Int64, localPath: String, caption: String?, replyToMessageId: Int64?) async throws {
        try ensureLocalFileExists(localPath)
        var content: [String: Any] = [
            "@type": "inputMessagePhoto",
            "photo": inputFileLocal(localPath),
            "added_sticker_file_ids": [] as [Int],
            "width": 0,
            "height": 0
        ]
        if let caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content["caption"] = formattedTextDict(caption)
        }
        try await sendMessageContent(chatId: chatId, content: content, replyToMessageId: replyToMessageId)
    }

    func sendDocument(chatId: Int64, localPath: String, fileName: String?, mimeType: String?, caption: String?, replyToMessageId: Int64?) async throws {
        try ensureLocalFileExists(localPath)
        var content: [String: Any] = [
            "@type": "inputMessageDocument",
            "document": inputFileLocal(localPath),
            "disable_content_type_detection": false
        ]
        if let caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content["caption"] = formattedTextDict(caption)
        }
        _ = fileName
        _ = mimeType
        try await sendMessageContent(chatId: chatId, content: content, replyToMessageId: replyToMessageId)
    }

    func sendVoiceNote(chatId: Int64, localPath: String, duration: Int, waveform: [Int], replyToMessageId: Int64?) async throws {
        try ensureLocalFileExists(localPath)
        let content: [String: Any] = [
            "@type": "inputMessageVoiceNote",
            "voice_note": inputFileLocal(localPath),
            "duration": max(1, duration),
            "waveform": waveform.isEmpty ? defaultVoiceWaveform() : waveform
        ]
        try await sendMessageContent(chatId: chatId, content: content, replyToMessageId: replyToMessageId)
    }

    func sendVideoNote(chatId: Int64, localPath: String, duration: Int, length: Int = 480, replyToMessageId: Int64?) async throws {
        try ensureLocalFileExists(localPath)
        let content: [String: Any] = [
            "@type": "inputMessageVideoNote",
            "video_note": inputFileLocal(localPath),
            "duration": max(1, duration),
            "length": length
        ]
        try await sendMessageContent(chatId: chatId, content: content, replyToMessageId: replyToMessageId)
    }

    func sendSticker(chatId: Int64, sticker: TgSticker, replyToMessageId: Int64?) async throws {
        let ready = try await ensureStickerReadyForSend(sticker)
        let content: [String: Any] = [
            "@type": "inputMessageSticker",
            "sticker": inputFileId(ready.fileId),
            "emoji": ready.emoji,
            "width": ready.width,
            "height": ready.height
        ]
        try await sendMessageContent(chatId: chatId, content: content, replyToMessageId: replyToMessageId)
    }

    func fetchStickerPickerItems(query: String, limit: Int = 40) async throws -> [TgSticker] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [TgSticker] = []
        var seen = Set<Int64>()

        if trimmed.isEmpty {
            let installed = try await loadInstalledStickerPickerItems(limit: limit)
            for sticker in installed where seen.insert(sticker.fileId).inserted {
                result.append(sticker)
            }
        }

        if result.count < limit {
            let searched = try await searchStickers(query: trimmed.isEmpty ? "👍" : trimmed, limit: limit)
            for sticker in searched where seen.insert(sticker.fileId).inserted {
                result.append(sticker)
            }
        }

        return Array(result.prefix(limit))
    }

    func searchStickerSets(query: String, limit: Int = 24) async throws -> [TgSticker] {
        try await fetchStickerPickerItems(query: query, limit: limit)
    }

    private func searchStickers(query: String, limit: Int) async throws -> [TgSticker] {
        let response = try await sendRequest([
            "@type": "searchStickers",
            "sticker_type": ["@type": "stickerTypeRegular"],
            "emoji": query,
            "query": query,
            "limit": limit,
            "offset": 0
        ])
        let stickers = response["stickers"] as? [[String: Any]] ?? []
        var result: [TgSticker] = []
        for sticker in stickers {
            if let item = await parseStickerForPicker(sticker) {
                result.append(item)
            }
        }
        return result
    }

    private func loadInstalledStickerPickerItems(limit: Int) async throws -> [TgSticker] {
        let response = try await sendRequest([
            "@type": "getInstalledStickerSets",
            "sticker_type": ["@type": "stickerTypeRegular"]
        ])
        let sets = response["sticker_sets"] as? [[String: Any]]
            ?? response["sets"] as? [[String: Any]]
            ?? []
        var result: [TgSticker] = []
        for setInfo in sets.prefix(5) {
            guard let name = setInfo["name"] as? String, !name.isEmpty else { continue }
            let setResponse = try await sendRequest([
                "@type": "getStickerSet",
                "name": name,
                "offset": 0,
                "limit": min(40, limit)
            ])
            let stickers = setResponse["stickers"] as? [[String: Any]] ?? []
            for sticker in stickers {
                if let item = await parseStickerForPicker(sticker) {
                    result.append(item)
                }
                if result.count >= limit { break }
            }
            if result.count >= limit { break }
        }
        return result
    }

    func fetchAvailableReactions(chatId: Int64, messageId: Int64) async throws -> TgAvailableReactions {
        let response = try await sendRequest([
            "@type": "getMessageAvailableReactions",
            "chat_id": chatId,
            "message_id": messageId,
            "row_size": 25
        ])
        var parsed = parseAvailableReactionsInfo(response)
        if parsed.items.count < 16 {
            if let global = try? await sendRequest(["@type": "getAvailableReactions"]) {
                let merged = mergeReactionPickerItems(
                    parsed.items,
                    parseAvailableReactionItems(global)
                )
                parsed = TgAvailableReactions(items: merged, maxReactionCount: parsed.maxReactionCount)
            }
        }
        let enriched = await enrichReactionPickerItems(parsed.items)
        return TgAvailableReactions(items: enriched, maxReactionCount: parsed.maxReactionCount)
    }

    func addMessageReaction(chatId: Int64, messageId: Int64, emoji: String) async throws {
        try await addMessageReaction(
            chatId: chatId,
            messageId: messageId,
            item: TgReactionPickerItem(key: emoji, emoji: emoji, customEmojiId: nil, imagePath: nil)
        )
    }

    func addMessageReaction(chatId: Int64, messageId: Int64, item: TgReactionPickerItem) async throws {
        _ = try await sendRequest([
            "@type": "addMessageReaction",
            "chat_id": chatId,
            "message_id": messageId,
            "reaction_type": reactionTypeDict(for: TgMessageReaction(
                key: item.key,
                emoji: item.emoji,
                count: 1,
                isChosen: false
            )),
            "is_big": false,
            "update_recent_reactions": true
        ])
    }

    func removeMessageReaction(chatId: Int64, messageId: Int64, reaction: TgMessageReaction) async throws {
        _ = try await sendRequest([
            "@type": "removeMessageReaction",
            "chat_id": chatId,
            "message_id": messageId,
            "reaction_type": reactionTypeDict(for: reaction)
        ])
    }

    private func reactionTypeDict(for reaction: TgMessageReaction) -> [String: Any] {
        if reaction.key.hasPrefix("custom:"),
           let id = Int64(reaction.key.dropFirst("custom:".count)) {
            return [
                "@type": "reactionTypeCustomEmoji",
                "custom_emoji_id": NSNumber(value: id)
            ]
        }
        return [
            "@type": "reactionTypeEmoji",
            "emoji": reaction.emoji
        ]
    }

    private func parseAvailableReactionsInfo(_ response: [String: Any]) -> TgAvailableReactions {
        let payload: [String: Any]
        if let nested = response["available_reactions"] as? [String: Any] {
            payload = nested
        } else {
            payload = response
        }

        let items = parseAvailableReactionItems(payload)
        let type = payload["@type"] as? String
        var maxCount = 1
        if type == "availableReactionsSome" {
            maxCount = max(1, Int(int32Value(payload["max_reaction_count"]) ?? 1))
        } else if type == "availableReactionsAll" {
            maxCount = max(3, Int(int32Value(payload["max_reaction_count"]) ?? 11))
        } else {
            maxCount = max(1, Int(int32Value(payload["max_reaction_count"]) ?? 1))
        }
        let fallbackItems = defaultReactionPickerItems()
        return TgAvailableReactions(
            items: items.isEmpty ? fallbackItems : items,
            maxReactionCount: maxCount
        )
    }

    private func defaultReactionPickerItems() -> [TgReactionPickerItem] {
        ["👍", "❤️", "🔥", "🤣", "😍", "😮", "😢", "🎉", "🙏", "👏", "💯", "🤝", "⚡️", "🥰", "😡", "🤔", "👎", "🖤", "💔", "🤩"]
            .map { TgReactionPickerItem(key: $0, emoji: $0, customEmojiId: nil, imagePath: nil) }
    }

    private func mergeReactionPickerItems(
        _ primary: [TgReactionPickerItem],
        _ extra: [TgReactionPickerItem]
    ) -> [TgReactionPickerItem] {
        var seen = Set(primary.map(\.key))
        var merged = primary
        for item in extra where seen.insert(item.key).inserted {
            merged.append(item)
        }
        return merged
    }

    private func enrichReactionPickerItems(_ items: [TgReactionPickerItem]) async -> [TgReactionPickerItem] {
        let customIds = items.compactMap(\.customEmojiId)
        guard !customIds.isEmpty else { return items }
        let paths = await fetchCustomEmojiPathsMap(customEmojiIds: customIds)
        return items.map { item in
            guard let id = item.customEmojiId, let path = paths[id] else { return item }
            return TgReactionPickerItem(
                key: item.key,
                emoji: item.emoji,
                customEmojiId: id,
                imagePath: path
            )
        }
    }

    private func fetchCustomEmojiPathsMap(customEmojiIds: [Int64]) async -> [Int64: String] {
        var result: [Int64: String] = [:]
        let chunkSize = 40
        var index = 0
        while index < customEmojiIds.count {
            let chunk = Array(customEmojiIds[index..<min(index + chunkSize, customEmojiIds.count)])
            index += chunkSize
            guard let response = try? await sendRequest([
                "@type": "getCustomEmojiStickers",
                "custom_emoji_ids": chunk.map { NSNumber(value: $0) }
            ]) else { continue }
            let stickers = response["stickers"] as? [[String: Any]] ?? []
            for (index, sticker) in stickers.enumerated() {
                let id = index < chunk.count
                    ? chunk[index]
                    : int64Value(sticker["custom_emoji_id"])
                guard let id else { continue }
                let media = await resolveStickerMediaPaths(from: sticker, downloadIfMissing: true)
                if let animationPath = media.animationPath, !animationPath.isEmpty {
                    result[id] = animationPath
                } else if let displayPath = media.displayPath, !displayPath.isEmpty {
                    result[id] = displayPath
                }
            }
        }
        return result
    }

    func createNewSupergroupChat(title: String, isChannel: Bool, description: String?) async throws -> Int64 {
        var body: [String: Any] = [
            "@type": "createNewSupergroupChat",
            "title": title,
            "is_channel": isChannel,
            "for_import": false
        ]
        if let description, !description.isEmpty {
            body["description"] = description
        }
        let response = try await sendRequest(body)
        guard let chatId = int64Value(response["id"]) else {
            throw NSError(domain: "TDLibClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create chat"])
        }
        return chatId
    }

    func addChatMembers(chatId: Int64, userIds: [Int64]) async throws {
        for userId in userIds {
            _ = try await sendRequest([
                "@type": "addChatMember",
                "chat_id": chatId,
                "user_id": userId,
                "forward_limit": 0
            ])
        }
    }

    func openPrivateChat(userId: Int64) async throws -> Int64 {
        let response = try await sendRequest([
            "@type": "createPrivateChat",
            "user_id": userId,
            "force": false
        ])
        guard let chatId = int64Value(response["id"]) else {
            throw NSError(domain: "TDLibClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to open private chat"])
        }
        return chatId
    }

    func searchPublicChat(username: String) async throws -> TgChat? {
        let normalized = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !normalized.isEmpty else { return nil }
        let response = try await sendRequest([
            "@type": "searchPublicChat",
            "username": normalized
        ])
        return try await parseChatSummary(response, listKind: .main)
    }

    func joinChatByInviteLink(_ inviteLink: String) async throws -> Int64 {
        let response = try await sendRequest([
            "@type": "joinChatByInviteLink",
            "invite_link": inviteLink.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        guard let chatId = int64Value(response["id"]) else {
            throw NSError(domain: "TDLibClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to join chat"])
        }
        return chatId
    }

    private func sendMessageContent(chatId: Int64, content: [String: Any], replyToMessageId: Int64?) async throws {
        var body: [String: Any] = [
            "@type": "sendMessage",
            "chat_id": chatId,
            "input_message_content": content,
            "options": [
                "@type": "messageSendOptions",
                "disable_notification": false,
                "from_background": false,
                "protect_content": false
            ]
        ]
        if let replyToMessageId {
            body["reply_to"] = [
                "@type": "inputMessageReplyToMessage",
                "message_id": replyToMessageId
            ]
        }
        _ = try await sendRequest(body)
    }

    private func inputFileLocal(_ path: String) -> [String: Any] {
        let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
        return ["@type": "inputFileLocal", "path": absolute]
    }

    private func ensureLocalFileExists(_ path: String) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "TDLibClient",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "File not found: \(url.lastPathComponent)"]
            )
        }
    }

    private func ensureStickerReadyForSend(_ sticker: TgSticker) async throws -> TgSticker {
        if sticker.fileId > 0 {
            _ = try? await sendRequest([
                "@type": "downloadFile",
                "file_id": sticker.fileId,
                "priority": 32,
                "offset": 0,
                "limit": 0,
                "synchronous": true
            ])
        }
        return sticker
    }

    private func inputFileId(_ fileId: Int64) -> [String: Any] {
        ["@type": "inputFileId", "id": NSNumber(value: fileId)]
    }

    private func defaultVoiceWaveform() -> [Int] {
        Array(repeating: 15, count: 32)
    }

    private func formattedTextDict(_ text: String) -> [String: Any] {
        ["@type": "formattedText", "text": text]
    }

    private func parseStickerForPicker(_ sticker: [String: Any]) async -> TgSticker? {
        let media = await resolveStickerMediaPaths(from: sticker, downloadIfMissing: true)
        let fileObject = sticker["sticker"] as? [String: Any]
        guard let fileId = int64Value(fileObject?["id"]) else { return nil }
        let emoji = (sticker["emoji"] as? String) ?? "🙂"
        let width = (sticker["width"] as? Int) ?? Int(int32Value(sticker["width"]) ?? 512)
        let height = (sticker["height"] as? Int) ?? Int(int32Value(sticker["height"]) ?? 512)
        return TgSticker(
            fileId: fileId,
            emoji: emoji,
            width: max(1, width),
            height: max(1, height),
            displayPath: media.displayPath,
            animationPath: media.animationPath,
            isAnimated: media.isAnimated,
            localPath: nil
        )
    }

    private func resolveChatFolders(from response: [String: Any]) async throws -> [TgChatFolder] {
        if let infos = response["chat_folders"] as? [[String: Any]] {
            return await loadChatFoldersFromInfos(infos)
        }

        let payload = chatFoldersPayload(from: response)
        var result: [TgChatFolder] = []
        var seen = Set<Int32>()

        if let folders = payload["folders"] as? [[String: Any]] {
            for folderJson in folders {
                guard let folder = parseChatFolder(folderJson), seen.insert(folder.id).inserted else { continue }
                result.append(folder)
            }
        }

        if let ids = payload["chat_folder_ids"] as? [Any] {
            for anyId in ids {
                guard let folderId = int32Value(anyId), !seen.contains(folderId) else { continue }
                let folderResp = try await sendRequest([
                    "@type": "getChatFolder",
                    "chat_folder_id": folderId
                ])
                guard let folder = parseChatFolder(folderResp, folderId: folderId), seen.insert(folder.id).inserted else { continue }
                result.append(folder)
            }
        }

        if let mainFolderId = int32Value(payload["main_chat_folder_id"]), result.count > 1 {
            result.removeAll { $0.id == mainFolderId }
        }
        return await enrichChatFoldersWithDetails(result)
    }

    private func parseAvailableReactionItems(_ response: [String: Any]) -> [TgReactionPickerItem] {
        var items: [TgReactionPickerItem] = []
        var seen = Set<String>()

        func item(from entry: [String: Any]) -> TgReactionPickerItem? {
            let type = (entry["type"] as? [String: Any]) ?? (entry["reaction"] as? [String: Any])
            if let type, let typeName = type["@type"] as? String {
                switch typeName {
                case "reactionTypeEmoji":
                    if let emoji = type["emoji"] as? String, !emoji.isEmpty {
                        return TgReactionPickerItem(key: emoji, emoji: emoji, customEmojiId: nil, imagePath: nil)
                    }
                case "reactionTypeCustomEmoji":
                    if let customId = int64Value(type["custom_emoji_id"]) {
                        let key = "custom:\(customId)"
                        return TgReactionPickerItem(key: key, emoji: "✨", customEmojiId: customId, imagePath: nil)
                    }
                default:
                    break
                }
            }
            if let emoji = entry["emoji"] as? String, !emoji.isEmpty {
                return TgReactionPickerItem(key: emoji, emoji: emoji, customEmojiId: nil, imagePath: nil)
            }
            return nil
        }

        func collect(from list: [[String: Any]]?) {
            guard let list else { return }
            for entry in list {
                guard let parsed = item(from: entry),
                      seen.insert(parsed.key).inserted else { continue }
                items.append(parsed)
            }
        }

        collect(from: response["reactions"] as? [[String: Any]])
        collect(from: response["top_reactions"] as? [[String: Any]])
        collect(from: response["recent_reactions"] as? [[String: Any]])
        collect(from: response["popular_reactions"] as? [[String: Any]])

        if items.isEmpty, let available = response["available_reactions"] as? [String: Any] {
            collect(from: available["reactions"] as? [[String: Any]])
            collect(from: available["top_reactions"] as? [[String: Any]])
            collect(from: available["recent_reactions"] as? [[String: Any]])
            collect(from: available["popular_reactions"] as? [[String: Any]])
        }

        return items
    }

    func editMessage(chatId: Int64, messageId: Int64, text: String) async throws {
        _ = try await sendRequest([
            "@type": "editMessageText",
            "chat_id": chatId,
            "message_id": messageId,
            "input_message_content": [
                "@type": "inputMessageText",
                "text": [
                    "@type": "formattedText",
                    "text": text
                ]
            ]
        ])
    }

    func deleteMessages(chatId: Int64, messageIds: [Int64], revoke: Bool) async throws {
        guard !messageIds.isEmpty else { return }
        _ = try await sendRequest([
            "@type": "deleteMessages",
            "chat_id": chatId,
            "message_ids": messageIds,
            "revoke": revoke
        ])
    }

    func downloadFile(fileId: Int64) async throws -> String? {
        let response = try await sendRequest([
            "@type": "downloadFile",
            "file_id": fileId,
            "priority": 32,
            "offset": 0,
            "limit": 0,
            "synchronous": true
        ])
        if let local = response["local"] as? [String: Any],
           (local["is_downloading_completed"] as? Bool) == true,
           let path = local["path"] as? String,
           !path.isEmpty {
            return path
        }
        return nil
    }

    func fetchChatProfile(chatId: Int64) async throws -> ChatProfile {
        let chat = try await sendRequest([
            "@type": "getChat",
            "chat_id": chatId
        ])

        let title = (chat["title"] as? String) ?? "Чат"
        let avatarPath = try await resolveChatAvatarPath(chat, preferBig: true)
        let statusInfo = try await resolveChatStatusInfo(chat)

        guard
            let type = chat["type"] as? [String: Any],
            let typeName = type["@type"] as? String
        else {
            return ChatProfile(
                chatId: chatId,
                title: title,
                kind: .unknown,
                avatarPath: avatarPath,
                username: nil,
                description: nil,
                membersCount: nil,
                statusText: statusInfo.text
            )
        }

        switch typeName {
        case "chatTypePrivate":
            if let userId = int64Value(type["user_id"]) {
                let meta = try await loadUserMeta(userId: userId)
                let blockState = try await resolvePrivateUserBlockState(userId: userId)
                return ChatProfile(
                    chatId: chatId,
                    title: title,
                    kind: .private,
                    avatarPath: avatarPath,
                    username: meta.username,
                    description: meta.bio,
                    membersCount: nil,
                    statusText: blockState.statusText ?? statusInfo.text,
                    userId: userId,
                    phoneNumber: meta.phoneNumber,
                    personalChannel: meta.personalChannel,
                    isPremium: meta.isPremium,
                    premiumBadgePath: meta.premiumBadgePath,
                    hasActiveStories: meta.hasActiveStories,
                    giftCount: meta.giftCount,
                    isBlockedByMe: blockState.blockedByMe,
                    isBlockedByPeer: blockState.blockedByPeer
                )
            }
            fallthrough
        case "chatTypeBasicGroup":
            if let groupId = int64Value(type["basic_group_id"]) {
                let group = try await sendRequest([
                    "@type": "getBasicGroup",
                    "basic_group_id": groupId
                ])
                let members = (group["member_count"] as? Int)
                return ChatProfile(
                    chatId: chatId,
                    title: title,
                    kind: .basicGroup,
                    avatarPath: avatarPath,
                    username: nil,
                    description: nil,
                    membersCount: members,
                    statusText: nil
                )
            }
            fallthrough
        case "chatTypeSupergroup":
            if let sgId = int64Value(type["supergroup_id"]) {
                let sg = try await sendRequest([
                    "@type": "getSupergroup",
                    "supergroup_id": sgId
                ])
                let isChannel = (sg["is_channel"] as? Bool) ?? false
                let username = sg["username"] as? String
                let members = sg["member_count"] as? Int
                let desc = sg["description"] as? String
                return ChatProfile(
                    chatId: chatId,
                    title: title,
                    kind: isChannel ? .channel : .supergroup,
                    avatarPath: avatarPath,
                    username: username,
                    description: desc,
                    membersCount: members,
                    statusText: nil
                )
            }
            fallthrough
        default:
            return ChatProfile(
                chatId: chatId,
                title: title,
                kind: .unknown,
                avatarPath: avatarPath,
                username: nil,
                description: nil,
                membersCount: nil,
                statusText: statusInfo.text
            )
        }
    }

    func fetchChatMembers(chatId: Int64, limit: Int = 50) async throws -> [ChatMember] {
        let chat = try await sendRequest([
            "@type": "getChat",
            "chat_id": chatId
        ])

        guard
            let type = chat["type"] as? [String: Any],
            let typeName = type["@type"] as? String
        else {
            return []
        }

        switch typeName {
        case "chatTypePrivate":
            guard let userId = int64Value(type["user_id"]) else { return [] }
            return [try await chatMemberFromUserId(userId, role: nil)]

        case "chatTypeBasicGroup":
            guard let groupId = int64Value(type["basic_group_id"]) else { return [] }
            let full = try await sendRequest([
                "@type": "getBasicGroupFullInfo",
                "basic_group_id": groupId
            ])
            let members = full["members"] as? [[String: Any]] ?? []
            var result: [ChatMember] = []
            for member in members.prefix(limit) {
                guard let userId = int64Value(member["user_id"]) else { continue }
                result.append(try await chatMemberFromUserId(userId, role: memberRole(member["status"] as? [String: Any])))
            }
            return result

        case "chatTypeSupergroup":
            guard let supergroupId = int64Value(type["supergroup_id"]) else { return [] }
            let response = try await sendRequest([
                "@type": "getSupergroupMembers",
                "supergroup_id": supergroupId,
                "filter": ["@type": "supergroupMembersFilterRecent"],
                "offset": 0,
                "limit": limit
            ])
            let members = response["members"] as? [[String: Any]] ?? []
            var result: [ChatMember] = []
            for member in members {
                guard
                    let sender = member["member_id"] as? [String: Any],
                    let senderType = sender["@type"] as? String
                else { continue }

                if senderType == "messageSenderUser", let userId = int64Value(sender["user_id"]) {
                    result.append(try await chatMemberFromUserId(userId, role: memberRole(member["status"] as? [String: Any])))
                } else if senderType == "messageSenderChat", let senderChatId = int64Value(sender["chat_id"]) {
                    let senderChat = try await sendRequest([
                        "@type": "getChat",
                        "chat_id": senderChatId
                    ])
                    result.append(
                        ChatMember(
                            id: senderChatId,
                            title: (senderChat["title"] as? String) ?? "Чат",
                            username: nil,
                            avatarPath: try await resolveChatAvatarPath(senderChat),
                            statusText: nil,
                            isOnline: nil,
                            isPremium: false,
                            premiumBadgePath: nil,
                            role: memberRole(member["status"] as? [String: Any]),
                            isUser: false
                        )
                    )
                }
            }
            return result

        default:
            return []
        }
    }

    func fetchChatMedia(chatId: Int64, limit: Int = 200) async throws -> [TgMessage] {
        let messages = try await fetchMessages(chatId: chatId, limit: limit)
        return messages.filter { message in
            !message.attachments.isEmpty || message.text.containsURL
        }
    }

    func openChat(chatId: Int64) async throws {
        _ = try await sendRequest([
            "@type": "openChat",
            "chat_id": chatId
        ])
    }

    func closeChat(chatId: Int64) async throws {
        _ = try await sendRequest([
            "@type": "closeChat",
            "chat_id": chatId
        ])
    }

    func markChatRead(chatId: Int64, messageIds: [Int64]) async throws {
        guard !messageIds.isEmpty else { return }
        _ = try await sendRequest([
            "@type": "viewMessages",
            "chat_id": chatId,
            "message_ids": messageIds,
            "force_read": true
        ])
    }

    func markChatUnread(chatId: Int64, unread: Bool) async throws {
        _ = try await sendRequest([
            "@type": "toggleChatIsMarkedAsUnread",
            "chat_id": chatId,
            "is_marked_as_unread": unread
        ])
    }

    func setChatPinned(chatId: Int64, pinned: Bool, list: TgChatListKind = .main) async throws {
        _ = try await sendRequest([
            "@type": "toggleChatIsPinned",
            "chat_list": list.tdlibDictionary,
            "chat_id": chatId,
            "is_pinned": pinned
        ])
    }

    func reorderPinnedChats(chatIds: [Int64], list: TgChatListKind = .main) async throws {
        _ = try await sendRequest([
            "@type": "setPinnedChats",
            "chat_list": list.tdlibDictionary,
            "chat_ids": chatIds
        ])
    }

    func setChatMute(chatId: Int64, duration: ChatMuteDuration) async throws {
        _ = try await sendRequest([
            "@type": "setChatNotificationSettings",
            "chat_id": chatId,
            "notification_settings": chatNotificationSettings(muteFor: duration.seconds)
        ])
    }

    func clearChatHistory(chatId: Int64) async throws {
        _ = try await sendRequest([
            "@type": "deleteChatHistory",
            "chat_id": chatId,
            "remove_from_chat_list": false,
            "revoke": false
        ])
    }

    func deleteChat(chatId: Int64) async throws {
        _ = try await sendRequest([
            "@type": "deleteChatHistory",
            "chat_id": chatId,
            "remove_from_chat_list": true,
            "revoke": false
        ])
    }

    func leaveChat(chatId: Int64) async throws {
        _ = try await sendRequest([
            "@type": "leaveChat",
            "chat_id": chatId
        ])
    }

    func fetchUserProfilePhotoPaths(userId: Int64, limit: Int = 100) async throws -> [String] {
        let response = try await sendRequest([
            "@type": "getUserProfilePhotos",
            "user_id": userId,
            "offset": 0,
            "limit": limit
        ])

        let photoItems = response["photos"] as? [[String: Any]] ?? []
        guard !photoItems.isEmpty else {
            return []
        }

        return try await withThrowingTaskGroup(of: (Int, String?).self) { group in
            for (index, photo) in photoItems.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (index, nil) }
                    let path = try await self.resolveProfilePhotoFilePath(photo)
                    return (index, path)
                }
            }
            var indexed: [(Int, String)] = []
            for try await item in group {
                if let path = item.1 {
                    indexed.append((item.0, path))
                }
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func applyReadOutboxStatus(messages: [TgMessage], chatId: Int64) async throws -> [TgMessage] {
        let chat = try await sendRequest([
            "@type": "getChat",
            "chat_id": chatId
        ])
        let lastReadOutbox = int64Value(chat["last_read_outbox_message_id"]) ?? 0
        return messages.map { message in
            guard message.outgoing else { return message }
            let isRead = message.id <= lastReadOutbox
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
                viewCount: message.viewCount,
                reactions: message.reactions
            )
        }
    }

    func searchChats(query: String, limit: Int = 30) async throws -> [TgChat] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let response = try await sendRequest([
            "@type": "searchChats",
            "query": trimmed,
            "limit": limit
        ])
        let chatIds = (response["chat_ids"] as? [Any] ?? []).compactMap(int64Value)
        var chats: [TgChat] = []
        for chatId in chatIds {
            let chat = try await sendRequest([
                "@type": "getChat",
                "chat_id": chatId
            ])
            if let summary = try await parseChatSummary(chat) {
                chats.append(summary)
            }
        }
        return chats
    }

    func searchPublicChats(query: String) async throws -> [TgChat] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let response = try await sendRequest([
            "@type": "searchPublicChats",
            "query": trimmed
        ])
        let chatIds = (response["chat_ids"] as? [Any] ?? []).compactMap(int64Value)
        var chats: [TgChat] = []
        for chatId in chatIds {
            let chat = try await sendRequest([
                "@type": "getChat",
                "chat_id": chatId
            ])
            if let summary = try await parseChatSummary(chat) {
                chats.append(summary)
            }
        }
        return chats
    }

    func setName(firstName: String, lastName: String) async throws {
        _ = try await sendRequest([
            "@type": "setName",
            "first_name": firstName,
            "last_name": lastName
        ])
    }

    func setUsername(_ username: String) async throws {
        _ = try await sendRequest([
            "@type": "setUsername",
            "username": username
        ])
    }

    func setProfilePhoto(localPath: String) async throws {
        _ = try await sendRequest([
            "@type": "setProfilePhoto",
            "profile_photo": [
                "@type": "inputProfilePhotoStatic",
                "photo": [
                    "@type": "inputFileLocal",
                    "path": localPath
                ]
            ]
        ])
    }

    func fetchUserPrivacySettings() async throws -> [UserPrivacySettingValue] {
        var values: [UserPrivacySettingValue] = []
        for kind in UserPrivacySettingKind.allCases {
            do {
                let visibility = try await fetchPrivacyVisibility(kind: kind)
                values.append(UserPrivacySettingValue(kind: kind, visibility: visibility))
            } catch {
                values.append(UserPrivacySettingValue(kind: kind, visibility: .contacts))
            }
        }
        return values
    }

    func setUserPrivacySetting(kind: UserPrivacySettingKind, visibility: PrivacyVisibility) async throws {
        let ruleType: String
        switch visibility {
        case .everybody:
            ruleType = "userPrivacySettingRuleAllowAll"
        case .contacts:
            ruleType = "userPrivacySettingRuleAllowContacts"
        case .nobody:
            ruleType = "userPrivacySettingRuleRestrictAll"
        }

        _ = try await sendRequest([
            "@type": "setUserPrivacySettingRules",
            "setting": [
                "@type": kind.tdlibType
            ],
            "rules": [
                [
                    "@type": ruleType
                ]
            ]
        ])
    }

    func searchMessagesGlobally(query: String, limit: Int = 20) async throws -> [GlobalSearchMessageHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let response = try await sendRequest([
            "@type": "searchMessages",
            "chat_list": [
                "@type": "chatListMain"
            ],
            "query": trimmed,
            "offset": "",
            "limit": limit,
            "min_date": 0,
            "max_date": 0
        ])

        guard let items = response["messages"] as? [[String: Any]] else { return [] }
        var hits: [GlobalSearchMessageHit] = []
        var chatTitles: [Int64: String] = [:]

        for item in items {
            guard let message = parseMessage(item, fallbackChatId: 0) else { continue }
            let chatId = message.chatId
            if chatTitles[chatId] == nil {
                let chat = try await sendRequest([
                    "@type": "getChat",
                    "chat_id": chatId
                ])
                chatTitles[chatId] = (chat["title"] as? String) ?? AppText.tr("Чат", "Chat")
            }
            let title = chatTitles[chatId] ?? AppText.tr("Чат", "Chat")
            hits.append(
                GlobalSearchMessageHit(
                    id: "\(chatId)-\(message.id)",
                    chatTitle: title,
                    message: message
                )
            )
        }

        return hits
    }

    private func fetchPrivacyVisibility(kind: UserPrivacySettingKind) async throws -> PrivacyVisibility {
        let response = try await sendRequest([
            "@type": "getUserPrivacySettingRules",
            "setting": [
                "@type": kind.tdlibType
            ]
        ])
        let rules = response["rules"] as? [[String: Any]] ?? []
        return parsePrivacyVisibility(from: rules)
    }

    private func parsePrivacyVisibility(from rules: [[String: Any]]) -> PrivacyVisibility {
        for rule in rules {
            guard let type = rule["@type"] as? String else { continue }
            switch type {
            case "userPrivacySettingRuleAllowAll":
                return .everybody
            case "userPrivacySettingRuleAllowContacts":
                return .contacts
            case "userPrivacySettingRuleRestrictAll":
                return .nobody
            default:
                continue
            }
        }
        return .contacts
    }

    private func resolveProfilePhotoFilePath(_ photo: [String: Any]) async throws -> String? {
        let file = preferredAvatarFile(from: photo, preferBig: true)
        guard let file else { return nil }

        if
            let local = file["local"] as? [String: Any],
            let path = local["path"] as? String,
            !path.isEmpty {
            return path
        }

        if let fileId = int64Value(file["id"]) {
            return try await downloadFile(fileId: fileId)
        }
        return nil
    }

    func setUserBlocked(userId: Int64, isBlocked: Bool) async throws {
        let sender: [String: Any] = [
            "@type": "messageSenderUser",
            "user_id": userId
        ]
        do {
            _ = try await sendRequest([
                "@type": "toggleMessageSenderIsBlocked",
                "sender_id": sender,
                "is_blocked": isBlocked
            ])
        } catch {
            if isBlocked {
                _ = try await sendRequest([
                    "@type": "blockUser",
                    "user_id": userId
                ])
            } else {
                _ = try await sendRequest([
                    "@type": "unblockUser",
                    "user_id": userId
                ])
            }
        }
    }

    func getMe() async throws -> TgUser {
        let user = try await sendRequest([
            "@type": "getMe"
        ])

        let id = int64Value(user["id"]) ?? 0
        let firstName = user["first_name"] as? String ?? ""
        let lastName = user["last_name"] as? String ?? ""
        let username = user["username"] as? String
        let phoneNumber = user["phone_number"] as? String
        let avatarPath = try await resolveUserAvatarPath(user)

        let isPremium = (user["is_premium"] as? Bool) ?? false
        cachedMyUserId = id
        let premiumBadgePath = await resolvePremiumBadgeImagePath(user: user)
        userInfoCache[id] = (
            name: [firstName, lastName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " "),
            avatarPath: avatarPath,
            isPremium: isPremium,
            premiumBadgePath: premiumBadgePath
        )

        return TgUser(
            id: id,
            firstName: firstName,
            lastName: lastName,
            username: username,
            phoneNumber: phoneNumber,
            avatarPath: avatarPath,
            isPremium: isPremium,
            premiumBadgePath: premiumBadgePath
        )
    }

    func fetchUserProfileDetail(userId: Int64) async throws -> UserProfileDetail {
        let user = try await sendRequest([
            "@type": "getUser",
            "user_id": userId
        ])
        let meta = try await loadUserMeta(userId: userId)
        let blockState = try await resolvePrivateUserBlockState(userId: userId)
        let status = (user["status"] as? [String: Any]).map(mapUserStatus)

        let privateChat = try await sendRequest([
            "@type": "createPrivateChat",
            "user_id": userId,
            "force": false
        ])
        let privateChatId = int64Value(privateChat["id"]) ?? userId

        let firstName = user["first_name"] as? String ?? ""
        let lastName = user["last_name"] as? String ?? ""
        let displayName = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return UserProfileDetail(
            userId: userId,
            privateChatId: privateChatId,
            displayName: displayName.isEmpty ? (meta.username.map { "@\($0)" } ?? "User") : displayName,
            username: meta.username,
            phoneNumber: meta.phoneNumber,
            bio: meta.bio,
            avatarPath: try await resolveUserAvatarPath(user),
            personalChannel: meta.personalChannel,
            statusText: blockState.statusText ?? status?.text,
            isOnline: status?.isOnline ?? false,
            isPremium: meta.isPremium,
            premiumBadgePath: meta.premiumBadgePath,
            hasActiveStories: meta.hasActiveStories,
            giftCount: meta.giftCount,
            isBlockedByMe: blockState.blockedByMe,
            isBlockedByPeer: blockState.blockedByPeer,
            isSelf: userId == cachedMyUserId
        )
    }

    func fetchContacts() async throws -> [TgContact] {
        let response = try await sendRequest([
            "@type": "getContacts"
        ])
        let userIds = (response["user_ids"] as? [Any])?.compactMap(int64Value) ?? []
        guard !userIds.isEmpty else { return [] }

        return await withTaskGroup(of: TgContact?.self) { group in
            for userId in userIds {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return try? await self.buildContact(userId: userId)
                }
            }
            var contacts: [TgContact] = []
            contacts.reserveCapacity(userIds.count)
            for await contact in group {
                if let contact {
                    contacts.append(contact)
                }
            }
            return contacts.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    func importDeviceContacts(_ entries: [(phone: String, firstName: String, lastName: String)]) async throws -> Int {
        guard !entries.isEmpty else { return 0 }
        var importedTotal = 0
        let chunkSize = 200
        var index = entries.startIndex
        while index < entries.endIndex {
            let end = entries.index(index, offsetBy: chunkSize, limitedBy: entries.endIndex) ?? entries.endIndex
            let chunk = Array(entries[index..<end])
            let contactsPayload: [[String: Any]] = chunk.map { entry in
                [
                    "@type": "contact",
                    "phone_number": entry.phone,
                    "first_name": entry.firstName,
                    "last_name": entry.lastName
                ]
            }
            let response = try await sendRequest([
                "@type": "importContacts",
                "contacts": contactsPayload
            ])
            importedTotal += (response["importer_count"] as? Int) ?? Int(int64Value(response["importer_count"]) ?? 0)
            index = end
        }
        return importedTotal
    }

    private func buildContact(userId: Int64) async throws -> TgContact {
        let user = try await sendRequest([
            "@type": "getUser",
            "user_id": userId
        ])
        let firstName = user["first_name"] as? String ?? ""
        let lastName = user["last_name"] as? String ?? ""
        let displayName = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let username = activeUsername(from: user)
        let phone = (user["phone_number"] as? String).flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let isPremium = (user["is_premium"] as? Bool) ?? false
        let premiumBadgePath = await resolvePremiumBadgeImagePath(user: user)
        let privateChat = try await sendRequest([
            "@type": "createPrivateChat",
            "user_id": userId,
            "force": false
        ])
        let privateChatId = int64Value(privateChat["id"]) ?? userId
        return TgContact(
            userId: userId,
            displayName: displayName.isEmpty ? (username.map { "@\($0)" } ?? "User") : displayName,
            phoneNumber: phone,
            username: username,
            avatarPath: try await resolveUserAvatarPath(user),
            isPremium: isPremium,
            premiumBadgePath: premiumBadgePath,
            privateChatId: privateChatId
        )
    }

    func fetchActiveStories(chatId: Int64) async throws -> [TgStoryItem] {
        _ = try? await sendRequest([
            "@type": "openChat",
            "chat_id": chatId
        ])

        let response = try await sendRequest([
            "@type": "getChatActiveStories",
            "chat_id": chatId
        ])
        let maxReadStoryId = int64Value(response["max_read_story_id"]) ?? 0
        let stories = response["stories"] as? [[String: Any]] ?? []

        return await withTaskGroup(of: TgStoryItem?.self) { group in
            for story in stories {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return await self.buildStoryItem(
                        summary: story,
                        chatId: chatId,
                        maxReadStoryId: maxReadStoryId
                    )
                }
            }

            var items: [TgStoryItem] = []
            for await item in group {
                if let item {
                    items.append(item)
                }
            }
            return items.sorted { $0.date < $1.date }
        }
    }

    private func buildStoryItem(
        summary: [String: Any],
        chatId: Int64,
        maxReadStoryId: Int64
    ) async -> TgStoryItem? {
        guard let storyId = int64Value(summary["story_id"]) ?? int64Value(summary["id"]) else { return nil }
        let dateUnix = (summary["send_date"] as? Double)
            ?? (summary["date"] as? Double)
            ?? Date().timeIntervalSince1970
        let isViewed = maxReadStoryId > 0 && storyId <= maxReadStoryId
        var previewPath: String?
        var mediaPath: String?
        var isVideo = false
        var caption = ""

        guard let full = try? await sendRequest([
            "@type": "getStory",
            "story_list": [
                "@type": "storyListChat",
                "chat_id": chatId
            ],
            "story_id": storyId,
            "only_active": true
        ]) else {
            return TgStoryItem(
                id: storyId,
                chatId: chatId,
                date: Date(timeIntervalSince1970: dateUnix),
                caption: "",
                previewPath: nil,
                mediaPath: nil,
                isVideo: false,
                isViewed: isViewed
            )
        }

        caption = formattedText(from: full["caption"] as? [String: Any])
        if let content = full["content"] as? [String: Any],
           let contentType = content["@type"] as? String {
            switch contentType {
            case "storyContentPhoto":
                if let photo = content["photo"] as? [String: Any] {
                    previewPath = await resolveFilePath(from: photo, downloadIfMissing: true)
                    mediaPath = previewPath
                }
            case "storyContentVideo":
                isVideo = true
                if let video = content["video"] as? [String: Any] {
                    if let videoFile = video["video"] as? [String: Any] {
                        mediaPath = await resolveFilePath(from: videoFile, downloadIfMissing: true)
                    } else {
                        mediaPath = await resolveFilePath(from: video, downloadIfMissing: true)
                    }
                    if let thumbnail = video["thumbnail"] as? [String: Any] {
                        previewPath = await resolveFilePath(from: thumbnail, downloadIfMissing: true)
                    } else if let preview = video["preview"] as? [String: Any] {
                        previewPath = await resolveFilePath(from: preview, downloadIfMissing: true)
                    }
                }
            default:
                break
            }
        }

        return TgStoryItem(
            id: storyId,
            chatId: chatId,
            date: Date(timeIntervalSince1970: dateUnix),
            caption: caption,
            previewPath: previewPath,
            mediaPath: mediaPath,
            isVideo: isVideo,
            isViewed: isViewed
        )
    }

    private func resolveFilePath(from file: [String: Any], downloadIfMissing: Bool) async -> String? {
        if let path = localCompletedFilePath(from: file) {
            return path
        }
        guard downloadIfMissing, let fileId = int64Value(file["id"]) else {
            return nil
        }
        return try? await downloadFile(fileId: fileId)
    }

    private func stickerFormatType(_ sticker: [String: Any]) -> String {
        (sticker["format"] as? [String: Any])?["@type"] as? String ?? ""
    }

    private func isPremiumStickerObject(_ sticker: [String: Any]) -> Bool {
        guard let fullType = sticker["full_type"] as? [String: Any],
              let type = fullType["@type"] as? String else {
            return false
        }
        return type == "stickerFullTypePremium" || type.contains("Premium")
    }

    private func resolveStickerMediaPaths(
        from stickerWrapper: [String: Any],
        downloadIfMissing: Bool
    ) async -> (displayPath: String?, animationPath: String?, isAnimated: Bool) {
        let format = stickerFormatType(stickerWrapper)
        let isAnimated = format == "stickerFormatWebm"

        var displayPath: String?
        var animationPath: String?

        if let thumbnail = stickerWrapper["thumbnail"] as? [String: Any] {
            displayPath = await resolveFilePath(from: thumbnail, downloadIfMissing: downloadIfMissing)
        }

        if let stickerFile = stickerWrapper["sticker"] as? [String: Any] {
            let mainPath = await resolveFilePath(from: stickerFile, downloadIfMissing: downloadIfMissing)
            switch format {
            case "stickerFormatWebm":
                animationPath = mainPath
                displayPath = displayPath ?? mainPath
            case "stickerFormatTgs":
                animationPath = mainPath
                if displayPath == nil {
                    displayPath = mainPath
                }
            case "stickerFormatWebp":
                displayPath = mainPath ?? displayPath
                animationPath = nil
            default:
                displayPath = mainPath ?? displayPath
            }
        }

        return (displayPath, animationPath, isAnimated)
    }

    func fetchReceivedGifts(userId: Int64, limit: Int = 100) async throws -> [TgGiftItem] {
        var offset = ""
        var items: [TgGiftItem] = []
        var page = 0

        while items.count < limit {
            let pageLimit = min(100, limit - items.count)
            let response = try await sendRequest([
                "@type": "getReceivedGifts",
                "business_connection_id": "",
                "owner_id": [
                    "@type": "messageSenderUser",
                    "user_id": userId
                ],
                "collection_id": 0,
                "exclude_unsaved": false,
                "exclude_saved": false,
                "exclude_unlimited": false,
                "exclude_upgradable": false,
                "exclude_non_upgradable": false,
                "exclude_upgraded": false,
                "exclude_without_colors": false,
                "exclude_hosted": false,
                "sort_by_price": false,
                "offset": offset,
                "limit": pageLimit
            ])

            let gifts = response["gifts"] as? [[String: Any]] ?? []
            for (index, entry) in gifts.enumerated() {
                guard let sentGift = entry["gift"] as? [String: Any] else { continue }

                let receivedId = (entry["received_gift_id"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let giftId: String
                if let receivedId, !receivedId.isEmpty {
                    giftId = "\(receivedId)-\(index)"
                } else {
                    giftId = "\(userId)-\(page)-\(index)"
                }

                let presentation = await resolveSentGiftPresentation(sentGift)
                var senderName = entry["sender_name"] as? String
                var senderUserId: Int64?
                var senderAvatarPath: String?
                var senderIsPremium = false
                var senderPremiumBadgePath: String?

                if let sender = entry["sender_id"] as? [String: Any],
                   let senderType = sender["@type"] as? String,
                   senderType == "messageSenderUser",
                   let senderId = int64Value(sender["user_id"]) {
                    senderUserId = senderId
                    if let user = try? await sendRequest([
                        "@type": "getUser",
                        "user_id": senderId
                    ]) {
                        let firstName = user["first_name"] as? String ?? ""
                        let lastName = user["last_name"] as? String ?? ""
                        let name = [firstName, lastName]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                        if !name.isEmpty {
                            senderName = name
                        } else if let username = activeUsername(from: user) {
                            senderName = "@\(username)"
                        }
                        senderAvatarPath = try? await resolveUserAvatarPath(user)
                        senderIsPremium = (user["is_premium"] as? Bool) ?? false
                        senderPremiumBadgePath = await resolvePremiumBadgeImagePath(user: user)
                    }
                }

                items.append(
                    TgGiftItem(
                        id: giftId,
                        title: presentation.title,
                        subtitle: senderName,
                        stickerPath: presentation.stickerPath,
                        animationPath: presentation.animationPath,
                        isAnimated: presentation.isAnimated,
                        senderUserId: senderUserId,
                        senderName: senderName,
                        senderAvatarPath: senderAvatarPath,
                        senderIsPremium: senderIsPremium,
                        senderPremiumBadgePath: senderPremiumBadgePath
                    )
                )
            }

            let nextOffset = (response["next_offset"] as? String) ?? ""
            if gifts.isEmpty || nextOffset.isEmpty {
                break
            }
            offset = nextOffset
            page += 1
        }

        return items
    }

    private func resolveSentGiftPresentation(_ sentGift: [String: Any]) async -> (
        title: String,
        stickerPath: String?,
        animationPath: String?,
        isAnimated: Bool
    ) {
        let type = sentGift["@type"] as? String ?? ""
        var title = AppText.tr("Подарок", "Gift")
        var stickerObject: [String: Any]?

        switch type {
        case "sentGiftRegular":
            if let gift = sentGift["gift"] as? [String: Any] {
                title = (gift["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? title
                stickerObject = gift["sticker"] as? [String: Any]
            }
        case "sentGiftUpgraded":
            if let upgraded = sentGift["upgraded_gift"] as? [String: Any] {
                title = (upgraded["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? (upgraded["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? title
                stickerObject = (upgraded["model"] as? [String: Any]) ?? (upgraded["sticker"] as? [String: Any])
            }
        default:
            if let gift = sentGift["gift"] as? [String: Any] {
                title = (gift["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? title
                stickerObject = gift["sticker"] as? [String: Any]
            } else {
                stickerObject = sentGift["sticker"] as? [String: Any]
            }
        }

        guard let stickerObject else {
            return (title, nil, nil, false)
        }
        let media = await resolveStickerMediaPaths(from: stickerObject, downloadIfMissing: true)
        return (title, media.displayPath, media.animationPath, media.isAnimated)
    }

    private func startReceiveLoopIfNeeded() {
        guard receiveLoopTask == nil else { return }
        receiveLoopTask = Task.detached { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    private func waitForAuthorizationState(_ type: String, timeout: TimeInterval) async throws {
        try await waitForAuthorizationState(matching: [type], timeout: timeout)
    }

    private func currentAuthorizationStateType() -> String {
        syncQueue.sync { lastAuthorizationStateType }
    }

    private func waitForAuthorizationState(matching types: [String], timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let waiterID = UUID()
            syncQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: TDLibClientError.deallocated)
                    return
                }

                if types.contains(self.lastAuthorizationStateType) {
                    continuation.resume()
                    return
                }

                self.authorizationWaiters.append(
                    AuthStateWaiter(id: waiterID, matching: Set(types), continuation: continuation)
                )

                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self else { return }
                    self.syncQueue.async {
                        guard let index = self.authorizationWaiters.firstIndex(where: { $0.id == waiterID }) else {
                            return
                        }
                        let waiter = self.authorizationWaiters.remove(at: index)
                        waiter.continuation.resume(throwing: TDLibClientError.authorizationTimeout)
                    }
                }
            }
        }
    }

    private func sendRequest(_ body: [String: Any]) async throws -> [String: Any] {
        var payload = body
        let extra = UUID().uuidString
        payload["@extra"] = extra
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TDLibClientError.jsonEncodingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            syncQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: TDLibClientError.deallocated)
                    return
                }
                self.pendingResponses[extra] = continuation
                self.bridge.send(json)
            }
        }
    }

    private func runReceiveLoop() async {
        while !Task.isCancelled {
            guard let raw = bridge.receive(timeout: 0.2),
                  let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let extra = obj["@extra"] as? String {
                syncQueue.async { [weak self] in
                    guard let self else { return }
                    let continuation = self.pendingResponses.removeValue(forKey: extra)
                    if let error = self.tdError(from: obj) {
                        continuation?.resume(throwing: error)
                    } else {
                        continuation?.resume(returning: obj)
                    }
                }
            }

            handleUpdate(obj)
        }
    }

    private func handleUpdate(_ obj: [String: Any]) {
        guard let type = obj["@type"] as? String else { return }

        if type == "updateAuthorizationState",
           let stateObj = obj["authorization_state"] as? [String: Any],
           let stateType = stateObj["@type"] as? String {
            syncQueue.async { [weak self] in
                guard let self else { return }
                self.lastAuthorizationStateType = stateType
                let mapped = self.mapAuthState(from: stateType)
                self.authState = mapped

                var remaining: [AuthStateWaiter] = []
                for waiter in self.authorizationWaiters {
                    if waiter.matching.contains(stateType) {
                        waiter.continuation.resume()
                    } else {
                        remaining.append(waiter)
                    }
                }
                self.authorizationWaiters = remaining
            }
            eventHandler?(.authChanged(mapAuthState(from: stateType)))
            return
        }

        if type == "updateNewMessage",
           let messageObj = obj["message"] as? [String: Any],
           let message = parseMessage(messageObj, fallbackChatId: 0) {
            Task {
                let enriched = (try? await self.enrichMessagesWithSenderInfo([message]))?.first ?? message
                self.eventHandler?(.newMessage(enriched))
            }
            return
        }

        if type == "updateMessageInteractionInfo",
           let chatId = int64Value(obj["chat_id"]),
           let messageId = int64Value(obj["message_id"]),
           let interaction = obj["interaction_info"] as? [String: Any] {
            let reactions = parseMessageReactions(interaction)
            let viewCount = parseInteractionViewCount(interaction)
            eventHandler?(.messageInteractionUpdated(
                chatId: chatId,
                messageId: messageId,
                reactions: reactions,
                viewCount: viewCount
            ))
            return
        }

        if type == "updateMessageSendSucceeded",
           let oldMessageId = int64Value(obj["old_message_id"]),
           let messageObj = obj["message"] as? [String: Any],
           let message = parseMessage(messageObj, fallbackChatId: 0) {
            Task {
                let enriched = (try? await self.enrichMessagesWithSenderInfo([message]))?.first ?? message
                self.eventHandler?(.messageReplaced(chatId: enriched.chatId, oldMessageId: oldMessageId, newMessage: enriched))
            }
            return
        }

        if type == "updateDeleteMessages",
           let chatId = int64Value(obj["chat_id"]),
           let idsAny = obj["message_ids"] as? [Any] {
            let isPermanent = (obj["is_permanent"] as? Bool) ?? false
            let fromCache = (obj["from_cache"] as? Bool) ?? false
            let ids = idsAny.compactMap(int64Value)
            if isPermanent, !fromCache, !ids.isEmpty {
                eventHandler?(.messagesDeleted(chatId: chatId, messageIds: ids))
            }
            return
        }

        if type == "updateChatFolders" {
            Task {
                let folders: [TgChatFolder]
                if let infos = obj["chat_folders"] as? [[String: Any]] {
                    folders = await self.loadChatFoldersFromInfos(infos)
                } else if let raw = obj["chat_folders"] as? [String: Any] {
                    folders = (try? await self.resolveChatFolders(from: raw)) ?? []
                } else {
                    folders = []
                }
                self.syncQueue.async {
                    self.cachedChatFolders = folders
                }
                self.eventHandler?(.chatsChanged)
            }
            return
        }

        if type == "updateNewChat" {
            eventHandler?(.chatsChanged)
            return
        }

        if type == "updateUser",
           let user = obj["user"] as? [String: Any],
           let userId = int64Value(user["id"]) {
            if let emojiStatus = user["emoji_status"] as? [String: Any],
               let emojiId = customEmojiId(from: emojiStatus) {
                customEmojiPathCache.removeValue(forKey: emojiId)
            }
            userInfoCache.removeValue(forKey: userId)
            eventHandler?(.chatsChanged)
            return
        }

        if type == "updateChatLastMessage",
           let chatId = int64Value(obj["chat_id"]) {
            eventHandler?(.chatChanged(chatId))
            return
        }

        if [
            "updateChatReadInbox",
            "updateChatReadOutbox",
            "updateChatUnreadMentionCount",
            "updateChatUnreadReactionCount",
            "updateChatNotificationSettings",
            "updateChatPosition",
            "updateChatIsMarkedAsUnread",
            "updateChatDraftMessage",
            "updateChatTitle",
            "updateChatPhoto",
            "updateChatDefaultDisableNotification"
        ].contains(type),
           let chatId = int64Value(obj["chat_id"]) {
            eventHandler?(.chatChanged(chatId))
            return
        }

        if (type == "updateUserChatAction" || type == "updateChatAction"),
           let chatId = int64Value(obj["chat_id"]) {
            let userId = int64Value(obj["user_id"])
            let actionKey = typingActionKey(from: obj["action"] as? [String: Any])
            eventHandler?(.chatTypingChanged(chatId: chatId, userId: userId, actionKey: actionKey))
        }
    }

    private func parseMessage(_ obj: [String: Any], fallbackChatId: Int64) -> TgMessage? {
        guard let id = int64Value(obj["id"]) else { return nil }
        let chatId = int64Value(obj["chat_id"]) ?? fallbackChatId
        let dateUnix = (obj["date"] as? Double) ?? Date().timeIntervalSince1970
        let isOutgoing = (obj["is_outgoing"] as? Bool) ?? false
        let editDate = int64Value(obj["edit_date"]) ?? 0
        let isEdited = editDate > 0
        let mediaAlbumId = int64Value(obj["media_album_id"])

        var replyToMessageId: Int64?
        if let replyTo = obj["reply_to"] as? [String: Any] {
            replyToMessageId = int64Value(replyTo["message_id"])
        }

        var isDeleted = false
        var text = ""
        if let content = obj["content"] as? [String: Any],
           let contentType = content["@type"] as? String {
            if contentType == "messageDeleted" {
                isDeleted = true
            } else if contentType == "messageText",
               let textObj = content["text"] as? [String: Any],
               let rawText = textObj["text"] as? String {
                text = rawText
            } else if let service = serviceMessageText(contentType: contentType, content: content) {
                text = service
            } else if let captionObj = content["caption"] as? [String: Any],
                      let caption = captionObj["text"] as? String {
                text = caption
            } else if isRenderableAttachmentContent(contentType) {
                text = ""
            } else {
                text = "[\(contentType)]"
            }
        }

        var senderUserId: Int64?
        if let sender = obj["sender_id"] as? [String: Any],
           (sender["@type"] as? String) == "messageSenderUser" {
            senderUserId = int64Value(sender["user_id"])
        }

        let interaction = obj["interaction_info"] as? [String: Any]
        let viewCount = parseInteractionViewCount(interaction)
        let reactions = parseMessageReactions(interaction)

        let authorSignature = (obj["author_signature"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = (authorSignature?.isEmpty == false) ? authorSignature : nil

        return TgMessage(
            id: id,
            chatId: chatId,
            text: text,
            outgoing: isOutgoing,
            createdAt: Date(timeIntervalSince1970: dateUnix),
            isEdited: isEdited,
            replyToMessageId: replyToMessageId,
            isDeleted: isDeleted,
            attachments: parseAttachments(obj["content"] as? [String: Any]),
            mediaAlbumId: mediaAlbumId,
            forwardedFrom: forwardedFromText(obj["forward_info"] as? [String: Any]),
            senderUserId: senderUserId,
            authorSignature: signature,
            viewCount: viewCount,
            reactions: reactions
        )
    }

    private func parseInteractionViewCount(_ interaction: [String: Any]?) -> Int? {
        guard let interaction else { return nil }
        if let views = interaction["view_count"] as? Int {
            return views
        }
        if let views = int64Value(interaction["view_count"]) {
            return Int(views)
        }
        return nil
    }

    private func parseMessageReactions(_ interaction: [String: Any]?) -> [TgMessageReaction] {
        guard
            let reactionsRoot = interaction?["reactions"] as? [String: Any],
            let items = reactionsRoot["reactions"] as? [[String: Any]]
        else {
            return []
        }

        var merged: [String: TgMessageReaction] = [:]
        for item in items {
            guard let type = item["type"] as? [String: Any],
                  let typeName = type["@type"] as? String else { continue }
            let count = max(1, Int(int32Value(item["total_count"]) ?? 1))
            let isChosen = (item["is_chosen"] as? Bool) ?? false

            let parsed: TgMessageReaction?
            switch typeName {
            case "reactionTypeEmoji":
                guard let emoji = type["emoji"] as? String, !emoji.isEmpty else { continue }
                parsed = TgMessageReaction(key: emoji, emoji: emoji, count: count, isChosen: isChosen)
            case "reactionTypeCustomEmoji":
                guard let customId = int64Value(type["custom_emoji_id"]) else { continue }
                let key = "custom:\(customId)"
                parsed = TgMessageReaction(key: key, emoji: "⭐", count: count, isChosen: isChosen)
            default:
                parsed = nil
            }
            guard let parsed else { continue }
            if let existing = merged[parsed.key] {
                merged[parsed.key] = TgMessageReaction(
                    key: parsed.key,
                    emoji: parsed.emoji,
                    count: max(existing.count, parsed.count),
                    isChosen: existing.isChosen || parsed.isChosen
                )
            } else {
                merged[parsed.key] = parsed
            }
        }
        return merged.values.sorted { $0.key < $1.key }
    }

    private func enrichMessagesWithSenderInfo(_ messages: [TgMessage]) async throws -> [TgMessage] {
        var missingUserIds = Set<Int64>()
        for message in messages where !message.outgoing {
            if let userId = message.senderUserId, userInfoCache[userId] == nil {
                missingUserIds.insert(userId)
            }
        }

        for userId in missingUserIds {
            let user = try await sendRequest([
                "@type": "getUser",
                "user_id": userId
            ])
            let firstName = user["first_name"] as? String ?? ""
            let lastName = user["last_name"] as? String ?? ""
            let name = [firstName, lastName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let username = (user["username"] as? String).flatMap { $0.isEmpty ? nil : "@\($0)" }
            let displayName = name.isEmpty ? (username ?? "User") : name
            let avatarPath = try await resolveUserAvatarPath(user, downloadIfMissing: false)
            let premiumBadgePath = await resolvePremiumBadgeImagePath(user: user)
            userInfoCache[userId] = (
                name: displayName,
                avatarPath: avatarPath,
                isPremium: (user["is_premium"] as? Bool) ?? false,
                premiumBadgePath: premiumBadgePath
            )
        }

        return messages.map { message in
            guard let userId = message.senderUserId,
                  let cached = userInfoCache[userId] else {
                return message
            }
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
                attachments: message.attachments,
                mediaAlbumId: message.mediaAlbumId,
                forwardedFrom: message.forwardedFrom,
                senderUserId: message.senderUserId,
                senderName: message.senderName ?? cached.name,
                senderAvatarPath: message.senderAvatarPath ?? cached.avatarPath,
                authorSignature: message.authorSignature,
                viewCount: message.viewCount,
                reactions: message.reactions
            )
        }
    }

    private func forwardedFromText(_ forwardInfo: [String: Any]?) -> String? {
        guard
            let origin = forwardInfo?["origin"] as? [String: Any],
            let type = origin["@type"] as? String
        else { return nil }

        switch type {
        case "messageOriginUser":
            return origin["sender_name"] as? String ?? "пользователь"
        case "messageOriginHiddenUser":
            return origin["sender_name"] as? String ?? "скрытый пользователь"
        case "messageOriginChat":
            return origin["sender_chat_title"] as? String ?? "чат"
        case "messageOriginChannel":
            return origin["chat_title"] as? String ?? "канал"
        default:
            return nil
        }
    }

    private func parseAttachments(_ content: [String: Any]?) -> [TgAttachment] {
        guard let content, let contentType = content["@type"] as? String else { return [] }

        switch contentType {
        case "messagePhoto":
            guard let photo = content["photo"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: photo["sizes"])
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .photo,
                fileId: fileInfo.id,
                fileName: nil,
                mimeType: "image/*",
                size: fileInfo.size,
                localPath: fileInfo.localPath
            )]
        case "messageVideo":
            guard let video = content["video"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: video["video"])
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .video,
                fileId: fileInfo.id,
                fileName: video["file_name"] as? String,
                mimeType: video["mime_type"] as? String,
                size: fileInfo.size ?? int64Value(video["size"]),
                localPath: fileInfo.localPath
            )]
        case "messageVoiceNote":
            guard let voice = content["voice_note"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: voice["voice"])
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .voice,
                fileId: fileInfo.id,
                fileName: nil,
                mimeType: voice["mime_type"] as? String,
                size: fileInfo.size ?? int64Value(voice["size"]),
                localPath: fileInfo.localPath
            )]
        case "messageVideoNote":
            guard let note = content["video_note"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: note["video"])
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .videoNote,
                fileId: fileInfo.id,
                fileName: nil,
                mimeType: "video/*",
                size: fileInfo.size ?? int64Value(note["size"]),
                localPath: fileInfo.localPath
            )]
        case "messageAnimation":
            guard let animation = content["animation"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: animation["animation"])
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .animation,
                fileId: fileInfo.id,
                fileName: animation["file_name"] as? String,
                mimeType: animation["mime_type"] as? String,
                size: fileInfo.size ?? int64Value(animation["size"]),
                localPath: fileInfo.localPath
            )]
        case "messageSticker":
            guard let sticker = content["sticker"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: sticker["sticker"])
            let format = stickerFormatType(sticker)
            let animPath = format == "stickerFormatWebm" ? fileInfo.localPath : nil
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .sticker,
                fileId: fileInfo.id,
                fileName: nil,
                mimeType: sticker["mime_type"] as? String,
                size: fileInfo.size ?? int64Value(sticker["size"]),
                localPath: format == "stickerFormatWebm" ? nil : fileInfo.localPath,
                animationPath: animPath,
                isPremiumSticker: isPremiumStickerObject(sticker)
            )]
        case "messageGift":
            guard let gift = content["gift"] as? [String: Any],
                  let sticker = gift["sticker"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: sticker["sticker"])
            let format = stickerFormatType(sticker)
            let animPath = format == "stickerFormatWebm" ? fileInfo.localPath : nil
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .gift,
                fileId: fileInfo.id,
                fileName: gift["title"] as? String,
                mimeType: sticker["mime_type"] as? String,
                size: fileInfo.size ?? int64Value(sticker["size"]),
                localPath: format == "stickerFormatWebm" ? nil : fileInfo.localPath,
                animationPath: animPath
            )]
        case "messageDocument":
            guard let doc = content["document"] as? [String: Any] else { return [] }
            let fileInfo = extractFileInfo(from: doc["document"])
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .document,
                fileId: fileInfo.id,
                fileName: doc["file_name"] as? String,
                mimeType: doc["mime_type"] as? String,
                size: fileInfo.size ?? int64Value(doc["size"]),
                localPath: fileInfo.localPath
            )]
        default:
            return []
        }
    }

    private func extractFileInfo(from source: Any?) -> (id: Int64?, localPath: String?, size: Int64?) {
        if let file = source as? [String: Any] {
            return fileInfo(file)
        }
        if let sizes = source as? [[String: Any]] {
            for item in sizes.reversed() {
                if let photo = item["photo"] as? [String: Any] {
                    return fileInfo(photo)
                }
            }
        }
        return (nil, nil, nil)
    }

    private func fileInfo(_ file: [String: Any]) -> (id: Int64?, localPath: String?, size: Int64?) {
        let local = file["local"] as? [String: Any]
        let path = (local?["path"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let size = int64Value(file["size"]) ?? int64Value(file["expected_size"])
        return (int64Value(file["id"]), path, size)
    }

    private func extractFileId(from source: Any?) -> Int64? {
        if let file = source as? [String: Any],
           let id = int64Value(file["id"]) {
            return id
        }
        if let sizes = source as? [[String: Any]] {
            for item in sizes.reversed() {
                if let photo = item["photo"] as? [String: Any],
                   let id = int64Value(photo["id"]) {
                    return id
                }
            }
        }
        return nil
    }

    private func isRenderableAttachmentContent(_ contentType: String) -> Bool {
        switch contentType {
        case "messagePhoto", "messageVideo", "messageVoiceNote", "messageVideoNote", "messageAnimation", "messageSticker", "messageGift", "messageDocument":
            return true
        default:
            return false
        }
    }

    private func serviceMessageText(contentType: String, content: [String: Any]) -> String? {
        switch contentType {
        case "messagePinMessage":
            return AppText.tr("📌 Закрепил(а) сообщение", "📌 Pinned a message")
        case "messageChatJoinByLink":
            return AppText.tr("🔗 Вступил(а) по ссылке-приглашению", "🔗 Joined via invite link")
        case "messageChatJoinByRequest":
            return AppText.tr("✅ Заявка на вступление одобрена", "✅ Join request approved")
        case "messageChatAddMembers":
            let count = (content["member_user_ids"] as? [Any])?.count ?? 0
            return count > 1
                ? AppText.tr("👥 Добавил(а) участников: \(count)", "👥 Added members: \(count)")
                : AppText.tr("👤 Добавил(а) участника", "👤 Added a member")
        case "messageChatDeleteMember":
            return AppText.tr("🚫 Удалил(а) участника", "🚫 Removed a member")
        case "messageChatChangeTitle":
            if let title = content["title"] as? String, !title.isEmpty {
                return AppText.tr("✏️ Изменил(а) название на «\(title)»", "✏️ Changed title to “\(title)”")
            }
            return AppText.tr("✏️ Изменил(а) название чата", "✏️ Changed chat title")
        case "messageChatChangePhoto":
            return AppText.tr("🖼️ Обновил(а) фото чата", "🖼️ Updated chat photo")
        case "messageChatDeletePhoto":
            return AppText.tr("🗑️ Удалил(а) фото чата", "🗑️ Removed chat photo")
        case "messageChatSetTheme":
            return AppText.tr("🎨 Изменил(а) тему чата", "🎨 Changed chat theme")
        default:
            return nil
        }
    }

    private struct UserMeta {
        let username: String?
        let phoneNumber: String?
        let personalChannel: ProfileLinkedChannel?
        let isPremium: Bool
        let premiumBadgePath: String?
        let hasActiveStories: Bool
        let giftCount: Int
        let bio: String?
    }

    private func loadUserMeta(userId: Int64) async throws -> UserMeta {
        let user = try await sendRequest([
            "@type": "getUser",
            "user_id": userId
        ])
        let full = try? await sendRequest([
            "@type": "getUserFullInfo",
            "user_id": userId
        ])
        let giftCount = (full?["gift_count"] as? Int) ?? Int(int64Value(full?["gift_count"]) ?? 0)
        let isPremium = (user["is_premium"] as? Bool) ?? false
        let premiumBadgePath = await resolvePremiumBadgeImagePath(user: user, fullInfo: full)
        let phone = (user["phone_number"] as? String).flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var personalChannel: ProfileLinkedChannel?
        if let channelId = int64Value(full?["personal_channel_id"]), channelId != 0 {
            personalChannel = try? await resolveLinkedChannel(chatId: channelId)
        }
        return UserMeta(
            username: activeUsername(from: user),
            phoneNumber: phone,
            personalChannel: personalChannel,
            isPremium: isPremium,
            premiumBadgePath: premiumBadgePath,
            hasActiveStories: (user["has_active_stories"] as? Bool) ?? false,
            giftCount: max(0, giftCount),
            bio: formattedText(from: full?["bio"] as? [String: Any])
        )
    }

    private func resolveLinkedChannel(chatId: Int64) async throws -> ProfileLinkedChannel? {
        let chat = try await sendRequest([
            "@type": "getChat",
            "chat_id": chatId
        ])
        let title = (chat["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }

        var username: String?
        if let type = chat["type"] as? [String: Any],
           (type["@type"] as? String) == "chatTypeSupergroup",
           let supergroupId = int64Value(type["supergroup_id"]) {
            let supergroup = try? await sendRequest([
                "@type": "getSupergroup",
                "supergroup_id": supergroupId
            ])
            username = supergroup?["username"] as? String
        }

        let avatarPath = try? await resolveChatAvatarPath(chat, preferBig: false)
        return ProfileLinkedChannel(
            chatId: chatId,
            title: title,
            username: username?.isEmpty == false ? username : nil,
            avatarPath: avatarPath
        )
    }

    private func resolvePremiumBadgeImagePath(user: [String: Any], fullInfo: [String: Any]? = nil) async -> String? {
        guard (user["is_premium"] as? Bool) == true else { return nil }
        let emojiStatus = (user["emoji_status"] as? [String: Any])
            ?? (fullInfo?["emoji_status"] as? [String: Any])
        guard let customEmojiId = customEmojiId(from: emojiStatus) else {
            return nil
        }
        if let cached = customEmojiPathCache[customEmojiId] {
            return cached
        }
        guard let path = try? await fetchCustomEmojiImagePath(customEmojiId: customEmojiId) else {
            return nil
        }
        customEmojiPathCache[customEmojiId] = path
        return path
    }

    private func customEmojiId(from emojiStatus: [String: Any]?) -> Int64? {
        guard let emojiStatus else { return nil }

        if let direct = int64Value(emojiStatus["custom_emoji_id"]) {
            return direct
        }

        let typeObject = (emojiStatus["type"] as? [String: Any]) ?? emojiStatus
        guard let typeName = typeObject["@type"] as? String else {
            return int64Value(emojiStatus["custom_emoji_id"])
        }

        switch typeName {
        case "emojiStatusTypeCustomEmoji":
            return int64Value(typeObject["custom_emoji_id"])
        case "emojiStatus":
            return customEmojiId(from: typeObject)
        default:
            return nil
        }
    }

    private func fetchCustomEmojiImagePath(customEmojiId: Int64) async throws -> String? {
        let response = try await sendRequest([
            "@type": "getCustomEmojiStickers",
            "custom_emoji_ids": [NSNumber(value: customEmojiId)]
        ])
        let stickers = response["stickers"] as? [[String: Any]] ?? []
        guard let sticker = stickers.first else { return nil }

        let media = await resolveStickerMediaPaths(from: sticker, downloadIfMissing: true)
        if let animationPath = media.animationPath, !animationPath.isEmpty {
            return animationPath
        }
        return media.displayPath
    }

    private func activeUsername(from user: [String: Any]) -> String? {
        if let usernames = user["usernames"] as? [String: Any],
           let active = usernames["active_usernames"] as? [String],
           let first = active.first,
           !first.isEmpty {
            return first
        }
        if let username = user["username"] as? String, !username.isEmpty {
            return username
        }
        return nil
    }

    private func formattedText(from obj: [String: Any]?) -> String {
        guard let obj else { return "" }
        return (obj["text"] as? String) ?? ""
    }

    private func chatMemberFromUserId(_ userId: Int64, role: String?) async throws -> ChatMember {
        let user = try await sendRequest([
            "@type": "getUser",
            "user_id": userId
        ])
        let meta = try await loadUserMeta(userId: userId)
        let firstName = user["first_name"] as? String ?? ""
        let lastName = user["last_name"] as? String ?? ""
        let name = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let status = (user["status"] as? [String: Any]).map(mapUserStatus)

        return ChatMember(
            id: userId,
            title: name.isEmpty ? "Пользователь" : name,
            username: meta.username,
            avatarPath: try await resolveUserAvatarPath(user),
            statusText: status?.text,
            isOnline: status?.isOnline,
            isPremium: meta.isPremium,
            premiumBadgePath: meta.premiumBadgePath,
            role: role,
            isUser: true
        )
    }

    private func localCompletedFilePath(from file: [String: Any]) -> String? {
        guard
            let local = file["local"] as? [String: Any],
            (local["is_downloading_completed"] as? Bool) == true,
            let path = local["path"] as? String,
            !path.isEmpty
        else {
            return nil
        }
        return path
    }

    private func resolveUserAvatarPath(
        _ user: [String: Any],
        downloadIfMissing: Bool = true
    ) async throws -> String? {
        guard
            let profilePhoto = user["profile_photo"] as? [String: Any],
            let file = (profilePhoto["big"] as? [String: Any]) ?? (profilePhoto["small"] as? [String: Any])
        else {
            return nil
        }

        if let path = localCompletedFilePath(from: file) {
            return path
        }

        guard downloadIfMissing, let fileId = int64Value(file["id"]) else {
            return nil
        }
        return try await downloadFile(fileId: fileId)
    }

    private func memberRole(_ status: [String: Any]?) -> String? {
        guard let statusType = status?["@type"] as? String else { return nil }
        switch statusType {
        case "chatMemberStatusCreator": return "Owner"
        case "chatMemberStatusAdministrator": return "Admin"
        case "chatMemberStatusRestricted": return "Restricted"
        case "chatMemberStatusBanned": return "Banned"
        default: return nil
        }
    }

    private func resolveChatAvatarPath(
        _ chat: [String: Any],
        preferBig: Bool = false,
        downloadIfMissing: Bool = true
    ) async throws -> String? {
        guard
            let photo = chat["photo"] as? [String: Any],
            let file = preferredAvatarFile(from: photo, preferBig: preferBig)
        else {
            return nil
        }

        if let path = localCompletedFilePath(from: file) {
            return path
        }

        guard downloadIfMissing, let fileId = int64Value(file["id"]) else {
            return nil
        }
        return try await downloadFile(fileId: fileId)
    }

    private func preferredAvatarFile(from photo: [String: Any], preferBig: Bool) -> [String: Any]? {
        if preferBig {
            return (photo["big"] as? [String: Any]) ?? (photo["small"] as? [String: Any])
        }
        return (photo["small"] as? [String: Any]) ?? (photo["big"] as? [String: Any])
    }

    private func parseChatSummary(_ chat: [String: Any], listKind: TgChatListKind = .main) async throws -> TgChat? {
        guard let id = int64Value(chat["id"]), let title = chat["title"] as? String else {
            return nil
        }

        let lastMessageObject = chat["last_message"] as? [String: Any]
        let lastMessage = lastMessageObject.flatMap { parseMessage($0, fallbackChatId: id) }
        let lastReadOutboxMessageId = int64Value(chat["last_read_outbox_message_id"]) ?? 0
        let unreadCount = (chat["unread_count"] as? Int) ?? Int(int64Value(chat["unread_count"]) ?? 0)
        let position = chatPosition(chat, listKind: listKind)
        let notification = notificationInfo(chat["notification_settings"] as? [String: Any])
        let statusInfo = try await resolveChatStatusInfo(chat)
        let sendInfo = try await resolveChatSendPermissions(chat)
        var kind = try await resolveChatKind(chat)
        var privateUserId: Int64?
        var isBlockedByMe = false
        var isBlockedByPeer = false

        var peerIsPremium = false
        var peerPremiumBadgePath: String?
        var peerUsername: String?
        if kind == .private,
           let chatType = chat["type"] as? [String: Any],
           let userId = int64Value(chatType["user_id"]) {
            privateUserId = userId
            let blockState = try await resolvePrivateUserBlockState(userId: userId)
            isBlockedByMe = blockState.blockedByMe
            isBlockedByPeer = blockState.blockedByPeer
            if let meta = try? await loadUserMeta(userId: userId) {
                peerIsPremium = meta.isPremium
                peerPremiumBadgePath = meta.premiumBadgePath
                peerUsername = meta.username
            }
        }

        if (chat["is_saved_messages"] as? Bool) == true {
            kind = .savedMessages
        } else if kind == .private,
                  let chatType = chat["type"] as? [String: Any],
                  let userId = int64Value(chatType["user_id"]),
                  userId == cachedMyUserId {
            kind = .savedMessages
        }

        let effectiveTitle = (kind == .savedMessages) ? AppText.tr("Избранное", "Saved Messages") : title
        let avatarPath: String? = (kind == .savedMessages)
            ? nil
            : (try await resolveChatAvatarPath(chat, downloadIfMissing: false))

        var finalSendInfo = sendInfo
        if isBlockedByMe {
            finalSendInfo = (false, AppText.tr("Вы заблокировали этого пользователя", "You blocked this user"))
        } else if isBlockedByPeer {
            finalSendInfo = (false, AppText.tr("Пользователь ограничил вас", "This user restricted you"))
        }

        var displayStatus = statusInfo.text
        if isBlockedByMe {
            displayStatus = AppText.tr("Заблокирован вами", "Blocked by you")
        } else if isBlockedByPeer {
            displayStatus = AppText.tr("Ограничил(а) вас", "Restricted you")
        }

        return TgChat(
            id: id,
            title: effectiveTitle,
            lastMessagePreview: lastMessage.map { AppText.chatListPreview(for: $0) },
            lastMessageId: lastMessage?.id,
            lastMessageDate: lastMessage?.createdAt,
            lastMessageOutgoing: lastMessage?.outgoing ?? false,
            lastMessageRead: (lastMessage?.outgoing == true) && ((lastMessage?.id ?? 0) <= lastReadOutboxMessageId),
            avatarPath: avatarPath,
            statusText: displayStatus,
            isOnline: isBlockedByMe || isBlockedByPeer ? false : statusInfo.isOnline,
            canSendMessages: finalSendInfo.canSend,
            sendRestrictionText: finalSendInfo.reason,
            unreadCount: unreadCount,
            kind: kind,
            isPinned: position.isPinned,
            pinOrder: position.order,
            isMuted: notification.isMuted,
            muteUntil: notification.muteUntil,
            isMarkedUnread: (chat["is_marked_as_unread"] as? Bool) ?? false,
            draftText: draftText(from: chat["draft_message"] as? [String: Any]),
            typingText: nil,
            privateUserId: privateUserId,
            peerIsPremium: peerIsPremium,
            peerPremiumBadgePath: peerPremiumBadgePath,
            peerUsername: peerUsername,
            isBlockedByMe: isBlockedByMe,
            isBlockedByPeer: isBlockedByPeer,
            lastReadOutboxMessageId: lastReadOutboxMessageId
        )
    }

    private func chatSort(_ lhs: TgChat, _ rhs: TgChat) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }
        if lhs.isPinned, rhs.isPinned {
            return (lhs.pinOrder ?? 0) > (rhs.pinOrder ?? 0)
        }
        return (lhs.lastMessageDate ?? .distantPast) > (rhs.lastMessageDate ?? .distantPast)
    }

    private func chatPosition(_ chat: [String: Any], listKind: TgChatListKind) -> (isPinned: Bool, order: Int64?) {
        let positions = chat["positions"] as? [[String: Any]] ?? []
        for position in positions {
            guard let list = position["list"] as? [String: Any] else { continue }
            guard (list["@type"] as? String) == listKind.listTypeName else { continue }
            if case .folder(let folderId) = listKind {
                guard int32Value(list["chat_folder_id"]) == folderId else { continue }
            }

            return (
                (position["is_pinned"] as? Bool) ?? false,
                int64Value(position["order"])
            )
        }
        return (false, nil)
    }

    private func parseChatFolder(_ json: [String: Any], folderId: Int32? = nil) -> TgChatFolder? {
        if let info = json["info"] as? [String: Any], let parsed = parseChatFolder(info, folderId: folderId) {
            return parsed
        }
        guard let id = int32Value(json["id"]) ?? int32Value(json["chat_folder_id"]) ?? folderId else { return nil }
        let titleRaw = parseFolderTitle(from: json)
        let title = titleRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false) ? title! : AppText.tr("Папка", "Folder")
        var iconEmoji: String?
        if let icon = json["icon"] as? [String: Any] {
            let iconType = icon["@type"] as? String
            if iconType == "chatFolderIconEmoji", let emoji = icon["emoji"] as? String {
                let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { iconEmoji = trimmed }
            } else if let emoji = icon["emoji"] as? String {
                let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed.count <= 4 {
                    iconEmoji = trimmed
                }
            }
        }
        let colorId = (json["color_id"] as? Int) ?? Int(int32Value(json["color_id"]) ?? 0)
        return TgChatFolder(id: id, title: resolvedTitle, iconEmoji: iconEmoji, colorId: colorId)
    }

    private func parseFolderTitle(from json: [String: Any]) -> String? {
        if let nameWrapper = json["name"] as? [String: Any] {
            if (nameWrapper["@type"] as? String) == "chatFolderName",
               let textObject = nameWrapper["text"] as? [String: Any] {
                let text = formattedText(from: textObject)
                if !text.isEmpty { return text }
            }
            let direct = formattedText(from: nameWrapper)
            if !direct.isEmpty { return direct }
            if let text = nameWrapper["text"] as? String, !text.isEmpty { return text }
        }
        if let name = json["name"] as? String, !name.isEmpty { return name }
        if let title = json["title"] as? String, !title.isEmpty { return title }
        return nil
    }

    private func notificationInfo(_ settings: [String: Any]?) -> (isMuted: Bool, muteUntil: Date?) {
        guard let settings else { return (false, nil) }
        let muteFor = Int(int64Value(settings["mute_for"]) ?? 0)
        guard muteFor > 0 else { return (false, nil) }

        if muteFor > 366 * 24 * 60 * 60 {
            return (true, nil)
        }
        return (true, Date().addingTimeInterval(TimeInterval(muteFor)))
    }

    private func draftText(from draft: [String: Any]?) -> String? {
        guard let draft else { return nil }
        let content = (draft["input_message_text"] as? [String: Any])
            ?? (draft["input_message_content"] as? [String: Any])
        guard
            let textObject = content?["text"] as? [String: Any],
            let text = textObject["text"] as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return text
    }

    private func messagePreview(_ message: [String: Any]) -> String? {
        guard
            let content = message["content"] as? [String: Any],
            let contentType = content["@type"] as? String
        else {
            return nil
        }

        if contentType == "messageDeleted" {
            return AppText.tr("Удалённое сообщение", "Deleted message")
        }

        if contentType == "messageText",
           let textObject = content["text"] as? [String: Any],
           let text = textObject["text"] as? String,
           !text.isEmpty {
            return text
        }

        if let captionObject = content["caption"] as? [String: Any],
           let caption = captionObject["text"] as? String,
           !caption.isEmpty {
            return caption
        }

        switch contentType {
        case "messagePhoto": return "Фото"
        case "messageVideo": return "Видео"
        case "messageVoiceNote": return "Голосовое сообщение"
        case "messageVideoNote": return "Видеосообщение"
        case "messageAnimation": return "GIF"
        case "messageSticker": return "Стикер"
        case "messageDocument": return "Файл"
        default: return nil
        }
    }

    private func chatNotificationSettings(muteFor: Int) -> [String: Any] {
        [
            "@type": "chatNotificationSettings",
            "use_default_mute_for": false,
            "mute_for": muteFor,
            "use_default_sound": true,
            "sound_id": 0,
            "use_default_show_preview": true,
            "show_preview": true,
            "use_default_disable_pinned_message_notifications": true,
            "disable_pinned_message_notifications": false,
            "use_default_disable_mention_notifications": true,
            "disable_mention_notifications": false
        ]
    }

    private func typingActionKey(from action: [String: Any]?) -> String? {
        guard let action, let type = action["@type"] as? String else { return nil }
        switch type {
        case "chatActionCancel":
            return nil
        case "chatActionTyping":
            return "typing"
        case "chatActionRecordingVoiceNote":
            return "recording_voice"
        case "chatActionRecordingVideo", "chatActionRecordingVideoNote":
            return "recording_video"
        case "chatActionUploadingPhoto":
            return "uploading_photo"
        case "chatActionUploadingVideo", "chatActionUploadingVideoNote":
            return "uploading_video"
        case "chatActionUploadingDocument":
            return "uploading_file"
        case "chatActionChoosingSticker":
            return "choosing_sticker"
        default:
            return nil
        }
    }

    func fetchUserDisplayName(userId: Int64) async throws -> String {
        if let cached = userInfoCache[userId] {
            return cached.name
        }
        let user = try await sendRequest([
            "@type": "getUser",
            "user_id": userId
        ])
        let firstName = user["first_name"] as? String ?? ""
        let lastName = user["last_name"] as? String ?? ""
        let name = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let username = (user["username"] as? String).flatMap { $0.isEmpty ? nil : "@\($0)" }
        let displayName = name.isEmpty ? (username ?? "User") : name
        let avatarPath = try await resolveUserAvatarPath(user)
        let premiumBadgePath = await resolvePremiumBadgeImagePath(user: user)
        userInfoCache[userId] = (
            name: displayName,
            avatarPath: avatarPath,
            isPremium: (user["is_premium"] as? Bool) ?? false,
            premiumBadgePath: premiumBadgePath
        )
        return displayName
    }

    func chatSendPermissions(chatId: Int64) async throws -> (canSend: Bool, reason: String?) {
        let chat = try await sendRequest([
            "@type": "getChat",
            "chat_id": chatId
        ])
        let resolved = try await resolveChatSendPermissions(chat)
        return (resolved.canSend ?? true, resolved.reason)
    }

    func pinChatMessage(chatId: Int64, messageId: Int64) async throws {
        _ = try await sendRequest([
            "@type": "pinChatMessage",
            "chat_id": chatId,
            "message_id": messageId,
            "disable_notification": false,
            "only_for_self": false
        ])
    }

    private func resolveChatStatusInfo(_ chat: [String: Any]) async throws -> (text: String?, isOnline: Bool?) {
        guard
            let type = chat["type"] as? [String: Any],
            let typeName = type["@type"] as? String
        else {
            return (nil, nil)
        }

        if typeName == "chatTypePrivate", let userId = int64Value(type["user_id"]) {
            let userResp = try await sendRequest([
                "@type": "getUser",
                "user_id": userId
            ])
            if let status = userResp["status"] as? [String: Any] {
                return mapUserStatus(status)
            }
            return ("был(а) недавно", false)
        }

        if typeName == "chatTypeBasicGroup" {
            if let groupId = int64Value(type["basic_group_id"]) {
                let group = try await sendRequest([
                    "@type": "getBasicGroup",
                    "basic_group_id": groupId
                ])
                let count = memberCount(from: group)
                return (memberCountLabel(count, isChannel: false), false)
            }
            return (AppText.tr("группа", "group"), false)
        }

        if typeName == "chatTypeSupergroup" {
            guard let supergroupId = int64Value(type["supergroup_id"]) else {
                return (AppText.tr("группа", "group"), false)
            }
            let supergroup = try await sendRequest([
                "@type": "getSupergroup",
                "supergroup_id": supergroupId
            ])
            let isChannel = (supergroup["is_channel"] as? Bool) ?? false
            let count = memberCount(from: supergroup)
            return (memberCountLabel(count, isChannel: isChannel), false)
        }

        return (nil, nil)
    }

    private func memberCount(from object: [String: Any]) -> Int {
        if let value = object["member_count"] as? Int {
            return value
        }
        return Int(int64Value(object["member_count"]) ?? 0)
    }

    private func memberCountLabel(_ count: Int, isChannel: Bool) -> String {
        let formatted = Self.compactCount(count)
        if isChannel {
            return AppText.tr("\(formatted) подписчиков", "\(formatted) subscribers")
        }
        return AppText.tr("\(formatted) участников", "\(formatted) members")
    }

    private static func compactCount(_ value: Int) -> String {
        let count = max(0, value)
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if count >= 10_000 {
            return String(format: "%.0fK", Double(count) / 1_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    private func resolveChatKind(_ chat: [String: Any]) async throws -> ChatKind {
        guard
            let type = chat["type"] as? [String: Any],
            let typeName = type["@type"] as? String
        else {
            return .unknown
        }

        switch typeName {
        case "chatTypePrivate":
            return .private
        case "chatTypeBasicGroup":
            return .basicGroup
        case "chatTypeSupergroup":
            guard let supergroupId = int64Value(type["supergroup_id"]) else {
                return .supergroup
            }
            let supergroup = try await sendRequest([
                "@type": "getSupergroup",
                "supergroup_id": supergroupId
            ])
            return ((supergroup["is_channel"] as? Bool) ?? false) ? .channel : .supergroup
        default:
            return .unknown
        }
    }

    private func resolveChatSendPermissions(_ chat: [String: Any]) async throws -> (canSend: Bool?, reason: String?) {
        let isChannel = (try? await resolveChatKind(chat)) == .channel

        // For channels, supergroup.status is the most reliable source for owner/admin posting rights.
        if isChannel,
           let selfStatus = try await resolveSupergroupSelfStatus(chat),
           let access = sendAccessFromMemberStatus(selfStatus, isChannel: true) {
            return access
        }

        if let chatId = int64Value(chat["id"]),
           let memberAccess = try await resolveMyMemberSendAccess(chatId: chatId, chat: chat) {
            return memberAccess
        }

        if isChannel {
            return (false, AppText.tr("Это канал — писать могут только администраторы", "Only admins can post in this channel"))
        }

        // Groups: TDLib chat.permissions applies to ordinary members.
        if let permissions = chat["permissions"] as? [String: Any] {
            if let canSend = permissions["can_send_messages"] as? Bool {
                return (canSend, canSend ? nil : AppText.tr("Запрещено отправлять сообщения", "Sending messages is not allowed"))
            }
        }

        // Private chats: check block state.
        if
            let type = chat["type"] as? [String: Any],
            let typeName = type["@type"] as? String,
            typeName == "chatTypePrivate",
            let userId = int64Value(type["user_id"])
        {
            let blockState = try await resolvePrivateUserBlockState(userId: userId)
            if blockState.blockedByMe {
                return (false, AppText.tr("Вы заблокировали этого пользователя", "You blocked this user"))
            }
            if blockState.blockedByPeer {
                return (false, AppText.tr("Пользователь ограничил вас", "This user restricted you"))
            }
        }

        return (true, nil)
    }

    private func resolveSupergroupSelfStatus(_ chat: [String: Any]) async throws -> [String: Any]? {
        guard
            let type = chat["type"] as? [String: Any],
            (type["@type"] as? String) == "chatTypeSupergroup",
            let supergroupId = int64Value(type["supergroup_id"])
        else {
            return nil
        }

        let supergroup = try await sendRequest([
            "@type": "getSupergroup",
            "supergroup_id": supergroupId
        ])
        return supergroup["status"] as? [String: Any]
    }

    private func administratorRights(from status: [String: Any]) -> [String: Any]? {
        status["rights"] as? [String: Any]
    }

    private func canPostInChannel(from status: [String: Any]) -> Bool {
        if let rights = administratorRights(from: status) {
            if (rights["can_post_messages"] as? Bool) == true { return true }
            if (rights["can_manage_chat"] as? Bool) == true { return true }
        }
        return (status["can_post_messages"] as? Bool) == true
    }

    private func canSendMessagesInChat(from status: [String: Any]) -> Bool {
        if let rights = administratorRights(from: status) {
            if (rights["can_send_messages"] as? Bool) == true { return true }
            if (rights["can_manage_chat"] as? Bool) == true { return true }
            if (rights["can_post_messages"] as? Bool) == true { return true }
        }
        return (status["can_send_messages"] as? Bool) == true
    }

    private func sendAccessFromMemberStatus(
        _ status: [String: Any],
        isChannel: Bool
    ) -> (canSend: Bool?, reason: String?)? {
        guard let statusType = status["@type"] as? String else { return nil }

        switch statusType {
        case "chatMemberStatusCreator":
            return (true, nil)
        case "chatMemberStatusAdministrator":
            if isChannel {
                if canPostInChannel(from: status) || canSendMessagesInChat(from: status) {
                    return (true, nil)
                }
                return (false, AppText.tr("Нет прав на публикацию в канале", "No permission to post in this channel"))
            }
            let canSend = canSendMessagesInChat(from: status)
            return (canSend, canSend ? nil : AppText.tr("Запрещено отправлять сообщения", "Sending messages is not allowed"))
        case "chatMemberStatusMember":
            if isChannel {
                return (false, AppText.tr("Это канал — писать могут только администраторы", "Only admins can post in this channel"))
            }
            return (true, nil)
        case "chatMemberStatusRestricted":
            let canSend = (status["can_send_messages"] as? Bool) ?? false
            let canPost = canPostInChannel(from: status)
            if isChannel, canPost || canSend {
                return (true, nil)
            }
            return (canSend, canSend ? nil : AppText.tr("Запрещено отправлять сообщения", "Sending messages is not allowed"))
        case "chatMemberStatusLeft", "chatMemberStatusBanned":
            return (false, AppText.tr("Вы не участник этого чата", "You are not a member of this chat"))
        default:
            return nil
        }
    }

    private func resolveMyMemberSendAccess(
        chatId: Int64,
        chat: [String: Any]
    ) async throws -> (canSend: Bool?, reason: String?)? {
        guard let myId = cachedMyUserId else { return nil }

        let member: [String: Any]
        do {
            member = try await sendRequest([
                "@type": "getChatMember",
                "chat_id": chatId,
                "member_id": [
                    "@type": "messageSenderUser",
                    "user_id": myId
                ]
            ])
        } catch {
            return nil
        }

        guard let status = member["status"] as? [String: Any] else {
            return nil
        }

        let isChannel = try await resolveChatKind(chat) == .channel
        return sendAccessFromMemberStatus(status, isChannel: isChannel)
    }

    private struct PrivateUserBlockState {
        let blockedByMe: Bool
        let blockedByPeer: Bool
        let statusText: String?
    }

    private func resolvePrivateUserBlockState(userId: Int64) async throws -> PrivateUserBlockState {
        if userId == cachedMyUserId {
            return PrivateUserBlockState(blockedByMe: false, blockedByPeer: false, statusText: nil)
        }

        let user = try await sendRequest([
            "@type": "getUser",
            "user_id": userId
        ])
        let haveAccess = (user["have_access"] as? Bool) ?? true

        let fullInfo = try await sendRequest([
            "@type": "getUserFullInfo",
            "user_id": userId
        ])
        let blockedByMe = (fullInfo["is_blocked"] as? Bool) ?? false

        var blockedByPeer = false
        if !haveAccess {
            blockedByPeer = true
        }

        if let restrictions = user["restriction_reason"] as? [[String: Any]], !restrictions.isEmpty {
            blockedByPeer = true
        }

        let statusText: String?
        if blockedByMe {
            statusText = AppText.tr("Заблокирован вами", "Blocked by you")
        } else if blockedByPeer {
            statusText = AppText.tr("Ограничил(а) вас", "Restricted you")
        } else {
            statusText = nil
        }

        return PrivateUserBlockState(
            blockedByMe: blockedByMe,
            blockedByPeer: blockedByPeer,
            statusText: statusText
        )
    }

    private func mapUserStatus(_ status: [String: Any]) -> (text: String, isOnline: Bool) {
        let statusType = status["@type"] as? String ?? ""
        switch statusType {
        case "userStatusOnline":
            return ("в сети", true)
        case "userStatusOffline":
            if let wasOnline = int64Value(status["was_online"]), wasOnline > 0 {
                return ("был(а) в сети \(relativeTimeText(fromUnix: wasOnline))", false)
            }
            return ("был(а) недавно", false)
        case "userStatusRecently":
            return ("был(а) недавно", false)
        case "userStatusLastWeek":
            return ("был(а) на этой неделе", false)
        case "userStatusLastMonth":
            return ("был(а) в этом месяце", false)
        default:
            return ("скрыт(а)", false)
        }
    }

    private func relativeTimeText(fromUnix value: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(value))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func mapAuthState(from tdType: String) -> AuthState {
        switch tdType {
        case "authorizationStateWaitPhoneNumber": return .waitPhone
        case "authorizationStateWaitCode": return .waitCode
        case "authorizationStateWaitPassword": return .waitPassword
        case "authorizationStateReady": return .ready
        default: return authState
        }
    }

    private func int64Value(_ any: Any?) -> Int64? {
        if let value = any as? Int64 { return value }
        if let value = any as? Int { return Int64(value) }
        if let value = any as? NSNumber { return value.int64Value }
        if let value = any as? String { return Int64(value) }
        return nil
    }

    private func int32Value(_ any: Any?) -> Int32? {
        if let value = any as? Int32 { return value }
        if let value = any as? Int { return Int32(value) }
        if let value = any as? NSNumber { return value.int32Value }
        if let value = any as? String { return Int32(value) }
        return nil
    }

    private func tdError(from obj: [String: Any]) -> Error? {
        guard (obj["@type"] as? String) == "error" else { return nil }
        let code = (obj["code"] as? Int) ?? -1
        let message = (obj["message"] as? String) ?? "TDLib error"
        return NSError(domain: "TDLibClient", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private struct AuthStateWaiter {
    let id: UUID
    let matching: Set<String>
    let continuation: CheckedContinuation<Void, Error>
}

enum TDLibClientError: LocalizedError {
    case deallocated
    case jsonEncodingFailed
    case authorizationTimeout
    case invalidApiCredentials

    var errorDescription: String? {
        switch self {
        case .deallocated:
            return "TDLib client was closed"
        case .jsonEncodingFailed:
            return "Failed to encode TDLib request"
        case .authorizationTimeout:
            return "Timed out waiting for TDLib authorization state"
        case .invalidApiCredentials:
            return "Invalid API credentials format"
        }
    }
}

private extension String {
    var containsURL: Bool {
        localizedCaseInsensitiveContains("http://")
            || localizedCaseInsensitiveContains("https://")
            || localizedCaseInsensitiveContains("t.me/")
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
