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
            INSERT INTO messages(message_id, chat_id, text, outgoing, created_at, is_deleted, media_album_id, forwarded_from)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(chat_id, message_id) DO UPDATE SET
              text=excluded.text,
              outgoing=excluded.outgoing,
              created_at=excluded.created_at,
              is_deleted=excluded.is_deleted,
              media_album_id=excluded.media_album_id,
              forwarded_from=excluded.forwarded_from;
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
                if let albumId = message.mediaAlbumId {
                    sqlite3_bind_int64(stmt, 7, albumId)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
                if let forwardedFrom = message.forwardedFrom, !forwardedFrom.isEmpty {
                    sqlite3_bind_text(stmt, 8, (forwardedFrom as NSString).utf8String, -1, sqliteTransient)
                } else {
                    sqlite3_bind_null(stmt, 8)
                }
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw NSError(domain: "LocalMessageStore", code: 3, userInfo: nil)
                }

                try replaceAttachments(chatId: message.chatId, messageId: message.id, attachments: message.attachments)
            }
        }
    }

    func read(chatId: Int64, limit: Int = 200) throws -> [TgMessage] {
        try queue.sync {
            let sql = """
            SELECT message_id, chat_id, text, outgoing, created_at, is_deleted, media_album_id, forwarded_from
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
                        isEdited: false,
                        replyToMessageId: nil,
                        isDeleted: sqlite3_column_int(stmt, 5) == 1,
                        attachments: try readAttachments(chatId: chatId, messageId: sqlite3_column_int64(stmt, 0)),
                        mediaAlbumId: (sqlite3_column_type(stmt, 6) == SQLITE_NULL) ? nil : sqlite3_column_int64(stmt, 6),
                        forwardedFrom: (sqlite3_column_type(stmt, 7) == SQLITE_NULL) ? nil : readText(stmt, 7)
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

    func deleteMessage(chatId: Int64, messageId: Int64) throws {
        try queue.sync {
            let sql = "DELETE FROM messages WHERE chat_id = ? AND message_id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "LocalMessageStore", code: 15, userInfo: nil)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, chatId)
            sqlite3_bind_int64(stmt, 2, messageId)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw NSError(domain: "LocalMessageStore", code: 16, userInfo: nil)
            }
        }
    }

    func cleanupTemporaryOutgoingDuplicates(chatId: Int64) throws {
        try queue.sync {
            // Removes old temporary outgoing messages replaced by server-confirmed copies.
            let sql = """
            DELETE FROM messages
            WHERE chat_id = ?
              AND message_id < 0
              AND outgoing = 1
              AND EXISTS (
                SELECT 1
                FROM messages AS confirmed
                WHERE confirmed.chat_id = messages.chat_id
                  AND confirmed.outgoing = messages.outgoing
                  AND confirmed.text = messages.text
                  AND confirmed.message_id > 0
                  AND ABS(confirmed.created_at - messages.created_at) <= 10
              );
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "LocalMessageStore", code: 17, userInfo: nil)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, chatId)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw NSError(domain: "LocalMessageStore", code: 18, userInfo: nil)
            }
        }
    }

    private func createSchema() throws {
        if try requiresScopedSchemaRebuild() {
            _ = sqlite3_exec(db, "DROP TABLE IF EXISTS attachments;", nil, nil, nil)
            _ = sqlite3_exec(db, "DROP TABLE IF EXISTS messages;", nil, nil, nil)
        }

        let sql = """
        CREATE TABLE IF NOT EXISTS messages(
            chat_id INTEGER NOT NULL,
            message_id INTEGER NOT NULL,
            text TEXT NOT NULL,
            outgoing INTEGER NOT NULL,
            created_at REAL NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            media_album_id INTEGER,
            forwarded_from TEXT,
            PRIMARY KEY (chat_id, message_id)
        );
        CREATE INDEX IF NOT EXISTS idx_messages_chat_time ON messages(chat_id, created_at);
        CREATE TABLE IF NOT EXISTS attachments(
            id TEXT PRIMARY KEY,
            chat_id INTEGER NOT NULL,
            message_id INTEGER NOT NULL,
            kind TEXT NOT NULL,
            file_id INTEGER,
            file_name TEXT,
            mime_type TEXT,
            local_path TEXT,
            size INTEGER,
            FOREIGN KEY (chat_id, message_id) REFERENCES messages(chat_id, message_id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_attachments_message ON attachments(chat_id, message_id);
        """

        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw NSError(
                domain: "LocalMessageStore",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: sqliteErrorMessage(result)]
            )
        }
    }

    private func requiresScopedSchemaRebuild() throws -> Bool {
        guard tableExists("messages") else {
            return tableExists("attachments")
        }

        let sql = "PRAGMA table_info(messages);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        var chatIdPk = false
        var messageIdPk = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = readText(stmt, 1)
            let pk = sqlite3_column_int(stmt, 5)
            if name == "chat_id", pk > 0 { chatIdPk = true }
            if name == "message_id", pk > 0 { messageIdPk = true }
        }

        if !(chatIdPk && messageIdPk) {
            return true
        }

        if tableExists("attachments"), !columnExists("attachments", "chat_id") {
            return true
        }

        return false
    }

    private func tableExists(_ name: String) -> Bool {
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, sqliteTransient)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func columnExists(_ table: String, _ column: String) -> Bool {
        let sql = "PRAGMA table_info(\(table));"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if readText(stmt, 1) == column { return true }
        }
        return false
    }

    private func sqliteErrorMessage(_ code: Int32) -> String {
        if let message = sqlite3_errmsg(db) {
            return String(cString: message)
        }
        return "sqlite error \(code)"
    }

    private func readText(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: c)
    }

    private func replaceAttachments(chatId: Int64, messageId: Int64, attachments: [TgAttachment]) throws {
        let existingLocalPaths = try readAttachmentLocalPaths(chatId: chatId, messageId: messageId)

        var deleteStmt: OpaquePointer?
        let deleteSQL = "DELETE FROM attachments WHERE chat_id = ? AND message_id = ?;"
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
            throw NSError(domain: "LocalMessageStore", code: 8, userInfo: nil)
        }
        sqlite3_bind_int64(deleteStmt, 1, chatId)
        sqlite3_bind_int64(deleteStmt, 2, messageId)
        guard sqlite3_step(deleteStmt) == SQLITE_DONE else {
            sqlite3_finalize(deleteStmt)
            throw NSError(domain: "LocalMessageStore", code: 9, userInfo: nil)
        }
        sqlite3_finalize(deleteStmt)

        guard !attachments.isEmpty else { return }

        let insertSQL = """
        INSERT INTO attachments(id, chat_id, message_id, kind, file_id, file_name, mime_type, local_path, size)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            throw NSError(domain: "LocalMessageStore", code: 10, userInfo: nil)
        }
        defer { sqlite3_finalize(insertStmt) }

        for attachment in attachments {
            sqlite3_reset(insertStmt)
            sqlite3_bind_text(insertStmt, 1, (attachment.id as NSString).utf8String, -1, sqliteTransient)
            sqlite3_bind_int64(insertStmt, 2, chatId)
            sqlite3_bind_int64(insertStmt, 3, messageId)
            sqlite3_bind_text(insertStmt, 4, (attachment.kind.rawValue as NSString).utf8String, -1, sqliteTransient)
            if let fileId = attachment.fileId {
                sqlite3_bind_int64(insertStmt, 5, fileId)
            } else {
                sqlite3_bind_null(insertStmt, 5)
            }
            if let fileName = attachment.fileName {
                sqlite3_bind_text(insertStmt, 6, (fileName as NSString).utf8String, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(insertStmt, 6)
            }
            if let mimeType = attachment.mimeType {
                sqlite3_bind_text(insertStmt, 7, (mimeType as NSString).utf8String, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(insertStmt, 7)
            }
            let localPath = attachment.localPath ?? attachment.fileId.flatMap { existingLocalPaths[$0] }
            if let localPath {
                sqlite3_bind_text(insertStmt, 8, (localPath as NSString).utf8String, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(insertStmt, 8)
            }
            if let size = attachment.size {
                sqlite3_bind_int64(insertStmt, 9, size)
            } else {
                sqlite3_bind_null(insertStmt, 9)
            }
            guard sqlite3_step(insertStmt) == SQLITE_DONE else {
                throw NSError(domain: "LocalMessageStore", code: 11, userInfo: nil)
            }
        }
    }

    private func readAttachments(chatId: Int64, messageId: Int64) throws -> [TgAttachment] {
        let sql = """
        SELECT id, kind, file_id, file_name, mime_type, local_path, size
        FROM attachments
        WHERE chat_id = ? AND message_id = ?
        ORDER BY rowid ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "LocalMessageStore", code: 12, userInfo: nil)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatId)
        sqlite3_bind_int64(stmt, 2, messageId)
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

    private func readAttachmentLocalPaths(chatId: Int64, messageId: Int64) throws -> [Int64: String] {
        let sql = """
        SELECT file_id, local_path
        FROM attachments
        WHERE chat_id = ? AND message_id = ?
          AND file_id IS NOT NULL
          AND local_path IS NOT NULL
          AND local_path != '';
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "LocalMessageStore", code: 19, userInfo: nil)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatId)
        sqlite3_bind_int64(stmt, 2, messageId)
        var paths: [Int64: String] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            let fileId = sqlite3_column_int64(stmt, 0)
            paths[fileId] = readText(stmt, 1)
        }

        return paths
    }

    func setAttachmentLocalPath(chatId: Int64, messageId: Int64, fileId: Int64, localPath: String) throws {
        try queue.sync {
            let sql = "UPDATE attachments SET local_path = ? WHERE chat_id = ? AND message_id = ? AND file_id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw NSError(domain: "LocalMessageStore", code: 13, userInfo: nil)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (localPath as NSString).utf8String, -1, sqliteTransient)
            sqlite3_bind_int64(stmt, 2, chatId)
            sqlite3_bind_int64(stmt, 3, messageId)
            sqlite3_bind_int64(stmt, 4, fileId)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw NSError(domain: "LocalMessageStore", code: 14, userInfo: nil)
            }
        }
    }
}
