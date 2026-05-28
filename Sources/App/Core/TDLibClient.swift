import Foundation

final class TDLibClient: TelegramClientProtocol, @unchecked Sendable {
    private let bridge: TDLibBridge
    private let syncQueue = DispatchQueue(label: "tdlib.client.sync")

    private var authState: AuthState = .waitPhone
    private var lastAuthorizationStateType = ""
    private var eventHandler: ((TelegramEvent) -> Void)?
    private var receiveLoopTask: Task<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var authorizationWaiters: [AuthStateWaiter] = []
    private var cachedMyUserId: Int64?
    private var userInfoCache: [Int64: (name: String, avatarPath: String?)] = [:]

    init() throws {
        self.bridge = try TDLibBridge()
    }

    func configure(apiId: Int, apiHash: String) async throws {
        guard apiId > 0, apiId <= Int(Int32.max), apiHash.count == 32 else {
            throw TDLibClientError.invalidApiCredentials
        }

        startReceiveLoopIfNeeded()
        setLogVerbosityLevel(1)

        try await waitForAuthorizationState("authorizationStateWaitTdlibParameters", timeout: 60)

        let databaseDirectory = try TDLibPaths.databaseDirectory()
        let filesDirectory = try TDLibPaths.filesDirectory()

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

    func fetchChats(limit: Int = 50) async throws -> [TgChat] {
        let response = try await sendRequest([
            "@type": "getChats",
            "chat_list": ["@type": "chatListMain"],
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
            if let chat = try await parseChatSummary(chatResp) {
                chats.append(chat)
            }
        }
        return chats.sorted(by: chatSort)
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
                let user = try await sendRequest([
                    "@type": "getUser",
                    "user_id": userId
                ])
                let username = (user["usernames"] as? [String: Any]).flatMap { $0["active_usernames"] as? [String] }?.first
                    ?? (user["username"] as? String)
                let blockState = try await resolvePrivateUserBlockState(userId: userId)
                return ChatProfile(
                    chatId: chatId,
                    title: title,
                    kind: .private,
                    avatarPath: avatarPath,
                    username: username,
                    description: nil,
                    membersCount: nil,
                    statusText: blockState.statusText ?? statusInfo.text,
                    userId: userId,
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
                            avatarPath: try await resolveChatAvatarPath(senderChat),
                            statusText: nil,
                            isOnline: nil,
                            role: memberRole(member["status"] as? [String: Any])
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

    func setChatPinned(chatId: Int64, pinned: Bool) async throws {
        _ = try await sendRequest([
            "@type": "toggleChatIsPinned",
            "chat_list": ["@type": "chatListMain"],
            "chat_id": chatId,
            "is_pinned": pinned
        ])
    }

    func reorderPinnedChats(chatIds: [Int64]) async throws {
        _ = try await sendRequest([
            "@type": "setPinnedChats",
            "chat_list": ["@type": "chatListMain"],
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
                viewCount: message.viewCount
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
            let visibility = try await fetchPrivacyVisibility(kind: kind)
            values.append(UserPrivacySettingValue(kind: kind, visibility: visibility))
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

        cachedMyUserId = id
        userInfoCache[id] = (
            name: [firstName, lastName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " "),
            avatarPath: avatarPath
        )

        return TgUser(
            id: id,
            firstName: firstName,
            lastName: lastName,
            username: username,
            phoneNumber: phoneNumber,
            avatarPath: avatarPath
        )
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

        if type == "updateNewChat" {
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
            eventHandler?(.chatTypingChanged(chatId: chatId, text: typingText(from: obj["action"] as? [String: Any])))
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
            if let messageId = int64Value(replyTo["message_id"]) {
                replyToMessageId = messageId
            } else if
                let replyType = replyTo["@type"] as? String,
                replyType == "messageReplyToMessage",
                let messageId = int64Value(replyTo["message_id"]) {
                replyToMessageId = messageId
            }
        }

        var text = ""
        if let content = obj["content"] as? [String: Any],
           let contentType = content["@type"] as? String {
            if contentType == "messageText",
               let textObj = content["text"] as? [String: Any],
               let rawText = textObj["text"] as? String {
                text = rawText
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

        var viewCount: Int?
        if let interaction = obj["interaction_info"] as? [String: Any] {
            if let views = interaction["view_count"] as? Int {
                viewCount = views
            } else if let views = int64Value(interaction["view_count"]) {
                viewCount = Int(views)
            }
        }

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
            isDeleted: false,
            attachments: parseAttachments(obj["content"] as? [String: Any]),
            mediaAlbumId: mediaAlbumId,
            forwardedFrom: forwardedFromText(obj["forward_info"] as? [String: Any]),
            senderUserId: senderUserId,
            authorSignature: signature,
            viewCount: viewCount
        )
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
            let avatarPath = try await resolveUserAvatarPath(user)
            userInfoCache[userId] = (name: displayName, avatarPath: avatarPath)
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
                viewCount: message.viewCount
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
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .sticker,
                fileId: fileInfo.id,
                fileName: nil,
                mimeType: sticker["mime_type"] as? String,
                size: fileInfo.size ?? int64Value(sticker["size"]),
                localPath: fileInfo.localPath
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
        case "messagePhoto", "messageVideo", "messageVoiceNote", "messageVideoNote", "messageAnimation", "messageSticker", "messageDocument":
            return true
        default:
            return false
        }
    }

    private func chatMemberFromUserId(_ userId: Int64, role: String?) async throws -> ChatMember {
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
        let status = (user["status"] as? [String: Any]).map(mapUserStatus)

        return ChatMember(
            id: userId,
            title: name.isEmpty ? "Пользователь" : name,
            avatarPath: try await resolveUserAvatarPath(user),
            statusText: status?.text,
            isOnline: status?.isOnline,
            role: role
        )
    }

    private func resolveUserAvatarPath(_ user: [String: Any]) async throws -> String? {
        guard
            let profilePhoto = user["profile_photo"] as? [String: Any],
            let file = (profilePhoto["big"] as? [String: Any]) ?? (profilePhoto["small"] as? [String: Any])
        else {
            return nil
        }

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

    private func resolveChatAvatarPath(_ chat: [String: Any], preferBig: Bool = false) async throws -> String? {
        guard
            let photo = chat["photo"] as? [String: Any],
            let file = preferredAvatarFile(from: photo, preferBig: preferBig)
        else {
            return nil
        }

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

    private func preferredAvatarFile(from photo: [String: Any], preferBig: Bool) -> [String: Any]? {
        if preferBig {
            return (photo["big"] as? [String: Any]) ?? (photo["small"] as? [String: Any])
        }
        return (photo["small"] as? [String: Any]) ?? (photo["big"] as? [String: Any])
    }

    private func parseChatSummary(_ chat: [String: Any]) async throws -> TgChat? {
        guard let id = int64Value(chat["id"]), let title = chat["title"] as? String else {
            return nil
        }

        let lastMessageObject = chat["last_message"] as? [String: Any]
        let lastMessage = lastMessageObject.flatMap { parseMessage($0, fallbackChatId: id) }
        let lastReadOutboxMessageId = int64Value(chat["last_read_outbox_message_id"]) ?? 0
        let unreadCount = (chat["unread_count"] as? Int) ?? Int(int64Value(chat["unread_count"]) ?? 0)
        let position = mainChatPosition(chat)
        let notification = notificationInfo(chat["notification_settings"] as? [String: Any])
        let statusInfo = try await resolveChatStatusInfo(chat)
        let sendInfo = try await resolveChatSendPermissions(chat)
        var kind = try await resolveChatKind(chat)
        var privateUserId: Int64?
        var isBlockedByMe = false
        var isBlockedByPeer = false

        if kind == .private,
           let chatType = chat["type"] as? [String: Any],
           let userId = int64Value(chatType["user_id"]) {
            privateUserId = userId
            let blockState = try await resolvePrivateUserBlockState(userId: userId)
            isBlockedByMe = blockState.blockedByMe
            isBlockedByPeer = blockState.blockedByPeer
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
        let avatarPath: String? = (kind == .savedMessages) ? nil : (try await resolveChatAvatarPath(chat))

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
            lastMessagePreview: lastMessageObject.flatMap(messagePreview) ?? lastMessage?.text,
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

    private func mainChatPosition(_ chat: [String: Any]) -> (isPinned: Bool, order: Int64?) {
        let positions = chat["positions"] as? [[String: Any]] ?? []
        for position in positions {
            guard
                let list = position["list"] as? [String: Any],
                (list["@type"] as? String) == "chatListMain"
            else { continue }

            return (
                (position["is_pinned"] as? Bool) ?? false,
                int64Value(position["order"])
            )
        }
        return (false, nil)
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

    private func typingText(from action: [String: Any]?) -> String? {
        guard let action, let type = action["@type"] as? String else { return nil }
        switch type {
        case "chatActionTyping":
            return "typing..."
        case "chatActionRecordingVoiceNote":
            return "recording voice..."
        case "chatActionRecordingVideo", "chatActionRecordingVideoNote":
            return "recording video..."
        case "chatActionUploadingPhoto":
            return "uploading photo..."
        case "chatActionUploadingVideo", "chatActionUploadingVideoNote":
            return "uploading video..."
        case "chatActionUploadingDocument":
            return "uploading file..."
        case "chatActionChoosingSticker":
            return "choosing sticker..."
        default:
            return nil
        }
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

        if typeName == "chatTypeBasicGroup" || typeName == "chatTypeSupergroup" {
            return ("группа", false)
        }

        return (nil, nil)
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
        // 1) If TDLib provided chat permissions directly (groups), trust it.
        if let permissions = chat["permissions"] as? [String: Any] {
            if let canSend = permissions["can_send_messages"] as? Bool {
                return (canSend, canSend ? nil : "Запрещено отправлять сообщения")
            }
        }

        // 2) Supergroups/channels: if it's a channel, usually нельзя писать (только постить, если админ).
        if
            let type = chat["type"] as? [String: Any],
            let typeName = type["@type"] as? String,
            typeName == "chatTypeSupergroup",
            let supergroupId = int64Value(type["supergroup_id"])
        {
            let sg = try await sendRequest([
                "@type": "getSupergroup",
                "supergroup_id": supergroupId
            ])

            let isChannel = (sg["is_channel"] as? Bool) ?? false
            if isChannel {
                // If admin with posting rights, allow.
                if
                    let status = sg["status"] as? [String: Any],
                    let statusType = status["@type"] as? String,
                    statusType.contains("Administrator"),
                    let canPost = status["can_post_messages"] as? Bool,
                    canPost == true
                {
                    return (true, nil)
                }
                return (false, "Это канал — отправка сообщений недоступна")
            }

            // Non-channel supergroup: allow by default unless restricted (we'll refine later).
            return (true, nil)
        }

        // 3) Private chats: check block state.
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
}
