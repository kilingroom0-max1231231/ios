import Foundation

enum AppText {
    static var isRussian: Bool {
        AppLanguageStore.shared.isRussian
    }

    static func tr(_ ru: String, _ en: String) -> String {
        isRussian ? ru : en
    }

    static func typingStatus(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case "typing...":
            return tr("печатает…", "typing…")
        case "recording voice...":
            return tr("записывает голосовое…", "recording voice…")
        case "recording video...":
            return tr("записывает видео…", "recording video…")
        case "uploading photo...":
            return tr("отправляет фото…", "sending photo…")
        case "uploading video...":
            return tr("отправляет видео…", "sending video…")
        case "uploading file...":
            return tr("отправляет файл…", "sending file…")
        case "choosing sticker...":
            return tr("выбирает стикер…", "choosing sticker…")
        default:
            return raw
        }
    }

    static func chatListPreview(for message: TgMessage) -> String {
        let body = messageBodyLabel(message)
        if message.isDeleted {
            if body.isEmpty {
                return tr("Удалённое сообщение", "Deleted message")
            }
            return tr("Удалено: \(body)", "Deleted: \(body)")
        }
        if !body.isEmpty { return body }
        return tr("Новое сообщение", "New message")
    }

    private static func messageBodyLabel(_ message: TgMessage) -> String {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        guard let first = message.attachments.first else { return "" }
        switch first.kind {
        case .photo: return tr("Фото", "Photo")
        case .video: return tr("Видео", "Video")
        case .voice: return tr("Голосовое", "Voice message")
        case .document: return first.fileName ?? tr("Файл", "File")
        default: return tr("Медиа", "Media")
        }
    }
}

