import Foundation

struct AccountSession: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var phone: String?
    var userId: Int64?
    var avatarPath: String?
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        phone: String? = nil,
        userId: Int64? = nil,
        avatarPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.phone = phone
        self.userId = userId
        self.avatarPath = avatarPath
        self.createdAt = createdAt
    }
}

@MainActor
final class AccountSessionStore: ObservableObject {
    static let shared = AccountSessionStore()
    static let maxAccounts = 5

    @Published private(set) var sessions: [AccountSession] = []
    @Published var activeAccountId: String

    private let fileURL: URL
    private let legacyDefaultId = "default"

    private init() {
        let base = (try? TDLibPaths.applicationSupportDirectory()) ?? FileManager.default.temporaryDirectory
        fileURL = base.appendingPathComponent("accounts.json")
        let loaded = Self.load(from: fileURL)
        if loaded.sessions.isEmpty {
            let initial = AccountSession(id: legacyDefaultId, title: AppText.tr("Аккаунт 1", "Account 1"))
            sessions = [initial]
            activeAccountId = initial.id
            persist()
        } else {
            sessions = loaded.sessions
            activeAccountId = loaded.activeAccountId
        }
    }

    func session(id: String) -> AccountSession? {
        sessions.first { $0.id == id }
    }

    func canAddAccount() -> Bool {
        sessions.count < Self.maxAccounts
    }

    @discardableResult
    func addAccount(title: String? = nil) -> AccountSession? {
        guard canAddAccount() else { return nil }
        let index = sessions.count + 1
        let session = AccountSession(
            title: title ?? AppText.tr("Аккаунт \(index)", "Account \(index)")
        )
        sessions.append(session)
        persist()
        return session
    }

    func removeAccount(id: String) {
        guard sessions.count > 1 else { return }
        sessions.removeAll { $0.id == id }
        if activeAccountId == id {
            activeAccountId = sessions[0].id
        }
        persist()
        deleteAccountFiles(accountId: id)
    }

    func setActiveAccount(id: String) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeAccountId = id
        persist()
    }

    func updateActiveAccount(
        title: String? = nil,
        phone: String? = nil,
        userId: Int64? = nil,
        avatarPath: String? = nil
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == activeAccountId }) else { return }
        if let title, !title.isEmpty { sessions[index].title = title }
        if let phone { sessions[index].phone = phone }
        if let userId { sessions[index].userId = userId }
        if let avatarPath { sessions[index].avatarPath = avatarPath }
        persist()
    }

    private func persist() {
        let payload = Persisted(sessions: sessions, activeAccountId: activeAccountId)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> Persisted {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data),
              !decoded.sessions.isEmpty else {
            return Persisted(sessions: [], activeAccountId: "")
        }
        return decoded
    }

    private func deleteAccountFiles(accountId: String) {
        guard let root = try? TDLibPaths.accountRoot(accountId: accountId) else { return }
        try? FileManager.default.removeItem(at: root)
        let base = (try? TDLibPaths.applicationSupportDirectory()) ?? FileManager.default.temporaryDirectory
        let messages = base.appendingPathComponent(TDLibPaths.messagesDatabaseFilename(accountId: accountId))
        let chats = base.appendingPathComponent(TDLibPaths.chatsCacheFilename(accountId: accountId))
        try? FileManager.default.removeItem(at: messages)
        try? FileManager.default.removeItem(at: chats)
    }

    private struct Persisted: Codable {
        let sessions: [AccountSession]
        let activeAccountId: String
    }
}
