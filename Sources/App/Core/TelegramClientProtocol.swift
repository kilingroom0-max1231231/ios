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
    func sendMessage(chatId: Int64, text: String) async throws
    func downloadFile(fileId: Int64) async throws -> String?
}
