import Foundation

final class LocalChatStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "TelegramUserClient.LocalChatStore")

    init(filename: String = "chats_cache.json") throws {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = baseURL.appendingPathComponent("TelegramUserClient", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(filename)
    }

    func read() throws -> [TgChat] {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return [] }
            return try Self.decoder.decode([TgChat].self, from: data)
        }
    }

    func write(chats: [TgChat]) throws {
        try queue.sync {
            let data = try Self.encoder.encode(chats)
            try data.write(to: fileURL, options: .atomic)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
