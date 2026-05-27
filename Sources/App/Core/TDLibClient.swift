import Foundation

final class TDLibClient: TelegramClientProtocol {
    private let bridge: TDLibBridge
    private let lock = NSLock()

    private var authState: AuthState = .waitPhone
    private var eventHandler: ((TelegramEvent) -> Void)?
    private var receiveLoopTask: Task<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]

    init(bridge: TDLibBridge = try! TDLibBridge()) {
        self.bridge = bridge
    }

    func configure(apiId: Int, apiHash: String) async throws {
        startReceiveLoopIfNeeded()

        _ = try await sendRequest([
            "@type": "setTdlibParameters",
            "parameters": [
                "database_directory": "tdlib/db",
                "files_directory": "tdlib/files",
                "use_message_database": true,
                "use_secret_chats": false,
                "api_id": apiId,
                "api_hash": apiHash,
                "system_language_code": "en",
                "device_model": "iPhone",
                "system_version": "iOS",
                "application_version": "1.0",
                "enable_storage_optimizer": true
            ]
        ])
        _ = try await sendRequest([
            "@type": "checkDatabaseEncryptionKey",
            "encryption_key": ""
        ])
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
            if let title = chatResp["title"] as? String {
                chats.append(TgChat(id: id, title: title))
            }
        }
        return chats
    }

    func fetchMessages(chatId: Int64, limit: Int = 100) async throws -> [TgMessage] {
        let response = try await sendRequest([
            "@type": "getChatHistory",
            "chat_id": chatId,
            "limit": limit,
            "from_message_id": 0,
            "offset": 0,
            "only_local": false
        ])
        guard let items = response["messages"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseMessage($0, fallbackChatId: chatId) }
            .sorted(by: { $0.createdAt < $1.createdAt })
    }

    func sendMessage(chatId: Int64, text: String) async throws {
        _ = try await sendRequest([
            "@type": "sendMessage",
            "chat_id": chatId,
            "input_message_content": [
                "@type": "inputMessageText",
                "text": [
                    "@type": "formattedText",
                    "text": text
                ]
            ]
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

    private func startReceiveLoopIfNeeded() {
        guard receiveLoopTask == nil else { return }
        receiveLoopTask = Task.detached { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    private func sendRequest(_ body: [String: Any]) async throws -> [String: Any] {
        var payload = body
        let extra = UUID().uuidString
        payload["@extra"] = extra
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "TDLibClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "JSON encoding failed"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pendingResponses[extra] = continuation
            lock.unlock()
            bridge.send(json)
        }
    }

    private func runReceiveLoop() async {
        while !Task.isCancelled {
            guard let raw = bridge.receive(timeout: 0.1),
                  let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let extra = obj["@extra"] as? String {
                lock.lock()
                let continuation = pendingResponses.removeValue(forKey: extra)
                lock.unlock()
                if let error = tdError(from: obj) {
                    continuation?.resume(throwing: error)
                } else {
                    continuation?.resume(returning: obj)
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
            let mapped = mapAuthState(from: stateType)
            authState = mapped
            eventHandler?(.authChanged(mapped))
            return
        }

        if type == "updateNewMessage",
           let messageObj = obj["message"] as? [String: Any],
           let message = parseMessage(messageObj, fallbackChatId: 0) {
            eventHandler?(.newMessage(message))
            return
        }

        if type == "updateDeleteMessages",
           let chatId = int64Value(obj["chat_id"]),
           let idsAny = obj["message_ids"] as? [Any] {
            let ids = idsAny.compactMap(int64Value)
            if !ids.isEmpty {
                eventHandler?(.messagesDeleted(chatId: chatId, messageIds: ids))
            }
            return
        }

        if type == "updateNewChat" || type == "updateChatLastMessage" {
            eventHandler?(.chatsChanged)
        }
    }

    private func parseMessage(_ obj: [String: Any], fallbackChatId: Int64) -> TgMessage? {
        guard let id = int64Value(obj["id"]) else { return nil }
        let chatId = int64Value(obj["chat_id"]) ?? fallbackChatId
        let dateUnix = (obj["date"] as? Double) ?? Date().timeIntervalSince1970
        let isOutgoing = (obj["is_outgoing"] as? Bool) ?? false

        var text = ""
        if let content = obj["content"] as? [String: Any],
           let contentType = content["@type"] as? String {
            if contentType == "messageText",
               let textObj = content["text"] as? [String: Any],
               let rawText = textObj["text"] as? String {
                text = rawText
            } else {
                text = "[\(contentType)]"
            }
        }

        return TgMessage(
            id: id,
            chatId: chatId,
            text: text,
            outgoing: isOutgoing,
            createdAt: Date(timeIntervalSince1970: dateUnix),
            isDeleted: false,
            attachments: parseAttachments(obj["content"] as? [String: Any])
        )
    }

    private func parseAttachments(_ content: [String: Any]?) -> [TgAttachment] {
        guard let content, let contentType = content["@type"] as? String else { return [] }

        switch contentType {
        case "messagePhoto":
            guard let photo = content["photo"] as? [String: Any] else { return [] }
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .photo,
                fileId: extractFileId(from: photo["sizes"]),
                fileName: nil,
                mimeType: "image/*",
                size: nil,
                localPath: nil
            )]
        case "messageVideo":
            guard let video = content["video"] as? [String: Any] else { return [] }
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .video,
                fileId: extractFileId(from: video["video"]),
                fileName: video["file_name"] as? String,
                mimeType: video["mime_type"] as? String,
                size: int64Value(video["size"]),
                localPath: nil
            )]
        case "messageVoiceNote":
            guard let voice = content["voice_note"] as? [String: Any] else { return [] }
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .voice,
                fileId: extractFileId(from: voice["voice"]),
                fileName: nil,
                mimeType: voice["mime_type"] as? String,
                size: int64Value(voice["size"]),
                localPath: nil
            )]
        case "messageVideoNote":
            guard let note = content["video_note"] as? [String: Any] else { return [] }
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .videoNote,
                fileId: extractFileId(from: note["video"]),
                fileName: nil,
                mimeType: "video/*",
                size: int64Value(note["size"]),
                localPath: nil
            )]
        case "messageDocument":
            guard let doc = content["document"] as? [String: Any] else { return [] }
            return [TgAttachment(
                id: UUID().uuidString,
                kind: .document,
                fileId: extractFileId(from: doc["document"]),
                fileName: doc["file_name"] as? String,
                mimeType: doc["mime_type"] as? String,
                size: int64Value(doc["size"]),
                localPath: nil
            )]
        default:
            return []
        }
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
