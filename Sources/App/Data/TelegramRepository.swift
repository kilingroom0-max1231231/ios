import Foundation

final class TelegramRepository {
    private let client: TelegramClientProtocol
    private let store: LocalMessageStore
    var onAuthStateChanged: ((AuthState) -> Void)?
    var onMessagesChanged: ((Int64) -> Void)?
    var onChatsChanged: (() -> Void)?

    init(client: TelegramClientProtocol = TDLibClient(), store: LocalMessageStore = try! LocalMessageStore()) {
        self.client = client
        self.store = store
        self.client.setEventHandler { [weak self] event in
            guard let self else { return }
            switch event {
            case .authChanged(let state):
                self.onAuthStateChanged?(state)
            case .newMessage(let message):
                try? self.store.upsert(messages: [message])
                self.onMessagesChanged?(message.chatId)
            case .messagesDeleted(let chatId, let messageIds):
                try? self.store.markDeleted(chatId: chatId, messageIds: messageIds)
                self.onMessagesChanged?(chatId)
            case .chatsChanged:
                self.onChatsChanged?()
            }
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
        try await client.fetchChats(limit: 50)
    }

    func syncMessages(chatId: Int64) async throws -> [TgMessage] {
        let remote = try await client.fetchMessages(chatId: chatId, limit: 100)
        try store.upsert(messages: remote)
        return try store.read(chatId: chatId)
    }

    func send(chatId: Int64, text: String) async throws -> [TgMessage] {
        try await client.sendMessage(chatId: chatId, text: text)
        return try await syncMessages(chatId: chatId)
    }

    func downloadMedia(chatId: Int64) async throws -> [TgMessage] {
        let current = try store.read(chatId: chatId)
        for message in current {
            for attachment in message.attachments {
                guard attachment.localPath == nil, let fileId = attachment.fileId else { continue }
                if let path = try await client.downloadFile(fileId: fileId) {
                    try store.setAttachmentLocalPath(messageId: message.id, fileId: fileId, localPath: path)
                }
            }
        }
        return try store.read(chatId: chatId)
    }
}
