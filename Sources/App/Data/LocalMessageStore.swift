import Foundation
import SQLite3

final class LocalMessageStore {
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let queue = DispatchQueue(label: "TelegramUserClient.LocalMessageStore")
    private var db: OpaquePointer?

    init(filename: String = "user_client.sqlite") throws {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = baseURL.appendingPathComponent("TelegramUserClient", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(filename).path

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw NSError(domain: "LocalMessageStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "sqlite open error"])
        }
        try createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    func upsert(messages: [TgMessage]) throws {
        try queue.sync {
            let sql = """
            INSERT INTO messages(message_id, chat_id, text, outgoing, created_at, is_deleted)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(message_id) DO UPDATE SET
              text=excluded.text,
              outgoing=excluded.outgoing,
              created_at=excluded.created_at,
              is_deleted=excluded.is_deleted;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "LocalMessageStore", code: 2, userInfo: nil)
            }
            defer { sqlite3_finalize(stmt) }

            for message in messages {
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, message.id)
                sqlite3_bind_int64(stmt, 2, message.chatId)
                sqlite3_bind_text(stmt, 3, (message.text as NSString).utf8String, -1, sqliteTransient)
                sqlite3_bind_int(stmt, 4, message.outgoing ? 1 : 0)
                sqlite3_bind_double(stmt, 5, message.createdAt.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 6, message.isDeleted ? 1 : 0)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw NSError(domain: "LocalMessageStore", code: 3, userInfo: nil)
                }

                try replaceAttachments(for: message.id, attachments: message.attachments)
            }
        }
    }

    func read(chatId: Int64, limit: Int = 200) throws -> [TgMessage] {
        try queue.sync {
            let sql = """
            SELECT message_id, chat_id, text, outgoing, created_at, is_deleted
            FROM messages
            WHERE chat_id = ?
            ORDER BY created_at ASC
            LIMIT ?;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "LocalMessageStore", code: 4, userInfo: nil)
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, chatId)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var out: [TgMessage] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(
                    TgMessage(
                        id: sqlite3_column_int64(stmt, 0),
                        chatId: sqlite3_column_int64(stmt, 1),
                        text: readText(stmt, 2),
                        outgoing: sqlite3_column_int(stmt, 3) == 1,
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                        isDeleted: sqlite3_column_int(stmt, 5) == 1,
                        attachments: try readAttachments(messageId: sqlite3_column_int64(stmt, 0))
                    )
                )
            }
            return out
        }
    }

    func markDeleted(chatId: Int64, messageIds: [Int64]) throws {
        guard !messageIds.isEmpty else { return }
        try queue.sync {
            let sql = "UPDATE messages SET is_deleted = 1 WHERE chat_id = ? AND message_id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "LocalMessageStore", code: 6, userInfo: nil)
            }
            defer { sqlite3_finalize(stmt) }

            for messageId in messageIds {
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, chatId)
                sqlite3_bind_int64(stmt, 2, messageId)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw NSError(domain: "LocalMessageStore", code: 7, userInfo: nil)
                }
            }
        }
    }

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            message_id INTEGER NOT NULL UNIQUE,
            chat_id INTEGER NOT NULL,
            text TEXT NOT NULL,
            outgoing INTEGER NOT NULL,
            created_at DOUBLE NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_messages_chat_time ON messages(chat_id, created_at);
        CREATE TABLE IF NOT EXISTS attachments(
            id TEXT PRIMARY KEY,
            message_id INTEGER NOT NULL,
            kind TEXT NOT NULL,
            file_id INTEGER,
            file_name TEXT,
            mime_type TEXT,
            local_path TEXT,
            size INTEGER,
            FOREIGN KEY(message_id) REFERENCES messages(message_id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_attachments_message ON attachments(message_id);
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "LocalMessageStore", code: 5, userInfo: nil)
        }
        _ = sqlite3_exec(db, "ALTER TABLE attachments ADD COLUMN local_path TEXT;", nil, nil, nil)
    }

    private func readText(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: c)
    }

    private func replaceAttachments(for messageId: Int64, attachments: [TgAttachment]) throws {
        var deleteStmt: OpaquePointer?
        let deleteSQL = "DELETE FROM attachments WHERE message_id = ?;"
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
            throw NSError(domain: "LocalMessageStore", code: 8, userInfo: nil)
        }
        sqlite3_bind_int64(deleteStmt, 1, messageId)
        guard sqlite3_step(deleteStmt) == SQLITE_DONE else {
            sqlite3_finalize(deleteStmt)
            throw NSError(domain: "LocalMessageStore", code: 9, userInfo: nil)
        }
        sqlite3_finalize(deleteStmt)

        guard !attachments.isEmpty else { return }

        let insertSQL = """
        INSERT INTO attachments(id, message_id, kind, file_id, file_name, mime_type, local_path, size)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?);
        """
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            throw NSError(domain: "LocalMessageStore", code: 10, userInfo: nil)
        }
        defer { sqlite3_finalize(insertStmt) }

        for attachment in attachments {
            sqlite3_reset(insertStmt)
            sqlite3_bind_text(insertStmt, 1, (attachment.id as NSString).utf8String, -1, sqliteTransient)
            sqlite3_bind_int64(insertStmt, 2, messageId)
            sqlite3_bind_text(insertStmt, 3, (attachment.kind.rawValue as NSString).utf8String, -1, sqliteTransient)
            if let fileId = attachment.fileId {
                sqlite3_bind_int64(insertStmt, 4, fileId)
            } else {
                sqlite3_bind_null(insertStmt, 4)
            }
            if let fileName = attachment.fileName {
                sqlite3_bind_text(insertStmt, 5, (fileName as NSString).utf8String, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(insertStmt, 5)
            }
            if let mimeType = attachment.mimeType {
                sqlite3_bind_text(insertStmt, 6, (mimeType as NSString).utf8String, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(insertStmt, 6)
            }
            if let localPath = attachment.localPath {
                sqlite3_bind_text(insertStmt, 7, (localPath as NSString).utf8String, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(insertStmt, 7)
            }
            if let size = attachment.size {
                sqlite3_bind_int64(insertStmt, 8, size)
            } else {
                sqlite3_bind_null(insertStmt, 8)
            }
            guard sqlite3_step(insertStmt) == SQLITE_DONE else {
                throw NSError(domain: "LocalMessageStore", code: 11, userInfo: nil)
            }
        }
    }

    private func readAttachments(messageId: Int64) throws -> [TgAttachment] {
        let sql = """
        SELECT id, kind, file_id, file_name, mime_type, local_path, size
        FROM attachments
        WHERE message_id = ?
        ORDER BY rowid ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "LocalMessageStore", code: 12, userInfo: nil)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, messageId)
        var out: [TgAttachment] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = readText(stmt, 0)
            let kindRaw = readText(stmt, 1)
            guard let kind = TgAttachmentKind(rawValue: kindRaw) else { continue }
            let fileId = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 2)
            let fileName = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : readText(stmt, 3)
            let mimeType = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : readText(stmt, 4)
            let localPath = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : readText(stmt, 5)
            let size = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 6)
            out.append(
                TgAttachment(
                    id: id,
                    kind: kind,
                    fileId: fileId,
                    fileName: fileName,
                    mimeType: mimeType,
                    size: size,
                    localPath: localPath
                )
            )
        }

        return out
    }

    func setAttachmentLocalPath(messageId: Int64, fileId: Int64, localPath: String) throws {
        try queue.sync {
            let sql = "UPDATE attachments SET local_path = ? WHERE message_id = ? AND file_id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "LocalMessageStore", code: 13, userInfo: nil)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (localPath as NSString).utf8String, -1, sqliteTransient)
            sqlite3_bind_int64(stmt, 2, messageId)
            sqlite3_bind_int64(stmt, 3, fileId)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw NSError(domain: "LocalMessageStore", code: 14, userInfo: nil)
            }
        }
    }
}
