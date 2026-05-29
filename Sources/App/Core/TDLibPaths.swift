import Foundation

enum TDLibPaths {
    static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDir = base.appendingPathComponent("TelegramUserClient", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }

    static func accountRoot(accountId: String) throws -> URL {
        let root = try applicationSupportDirectory().appendingPathComponent("accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let accountDir = root.appendingPathComponent(accountId, isDirectory: true)
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)
        return accountDir
    }

    static func databaseDirectory(accountId: String) throws -> String {
        let accountDir = try accountRoot(accountId: accountId)
        let target = accountDir.appendingPathComponent("tdlib-db", isDirectory: true)
        let legacy = try applicationSupportDirectory().appendingPathComponent("tdlib-db", isDirectory: true)
        migrateLegacyDirectoryIfNeeded(from: legacy, to: target)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target.path
    }

    static func filesDirectory(accountId: String) throws -> String {
        let accountDir = try accountRoot(accountId: accountId)
        let target = accountDir.appendingPathComponent("tdlib-files", isDirectory: true)
        let legacy = try applicationSupportDirectory().appendingPathComponent("tdlib-files", isDirectory: true)
        migrateLegacyDirectoryIfNeeded(from: legacy, to: target)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target.path
    }

    static func messagesDatabaseFilename(accountId: String) -> String {
        "messages-\(accountId).sqlite"
    }

    static func chatsCacheFilename(accountId: String) -> String {
        "chats-\(accountId).json"
    }

    private static func migrateLegacyDirectoryIfNeeded(from legacy: URL, to target: URL) {
        guard FileManager.default.fileExists(atPath: legacy.path),
              !FileManager.default.fileExists(atPath: target.path) else { return }
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: legacy, to: target)
    }
}
