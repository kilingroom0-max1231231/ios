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

    static func databaseDirectory() throws -> String {
        let dir = try applicationSupportDirectory().appendingPathComponent("tdlib-db", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    static func filesDirectory() throws -> String {
        let dir = try applicationSupportDirectory().appendingPathComponent("tdlib-files", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}
