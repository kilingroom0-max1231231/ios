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
        if let action = typingActionPhrase(raw) {
            return action
        }
        return raw
    }

    /// Group/supergroup: "Иван печатает…", "Иван и Петр печатают…", "4 печатают…"
    static func groupTypingStatus(names: [String], actionKey: String) -> String? {
        let verb = typingActionPhrase(actionKey) ?? tr("печатает…", "typing…")
        let verbMany = typingActionPhraseMany(actionKey) ?? tr("печатают…", "are typing…")
        let cleaned = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        switch cleaned.count {
        case 0:
            return verb
        case 1:
            return "\(cleaned[0]) \(verb)"
        case 2:
            return tr("\(cleaned[0]) и \(cleaned[1]) \(verbMany)", "\(cleaned[0]) and \(cleaned[1]) \(verbMany)")
        default:
            return tr("\(cleaned.count) \(verbMany)", "\(cleaned.count) \(verbMany)")
        }
    }

    private static func typingActionPhrase(_ key: String) -> String? {
        switch key {
        case "typing", "typing...":
            return tr("печатает…", "typing…")
        case "recording_voice", "recording voice...":
            return tr("записывает голосовое…", "recording voice…")
        case "recording_video", "recording video...":
            return tr("записывает видео…", "recording video…")
        case "uploading_photo", "uploading photo...":
            return tr("отправляет фото…", "sending photo…")
        case "uploading_video", "uploading video...":
            return tr("отправляет видео…", "sending video…")
        case "uploading_file", "uploading file...":
            return tr("отправляет файл…", "sending file…")
        case "choosing_sticker", "choosing sticker...":
            return tr("выбирает стикер…", "choosing sticker…")
        default:
            return nil
        }
    }

    private static func typingActionPhraseMany(_ key: String) -> String? {
        switch key {
        case "typing", "typing...":
            return tr("печатают…", "are typing…")
        case "recording_voice", "recording voice...":
            return tr("записывают голосовое…", "are recording voice…")
        case "recording_video", "recording video...":
            return tr("записывают видео…", "are recording video…")
        case "uploading_photo", "uploading photo...":
            return tr("отправляют фото…", "are sending photos…")
        case "uploading_video", "uploading video...":
            return tr("отправляют видео…", "are sending videos…")
        case "uploading_file", "uploading file...":
            return tr("отправляют файл…", "are sending files…")
        case "choosing_sticker", "choosing sticker...":
            return tr("выбирают стикер…", "are choosing stickers…")
        default:
            return nil
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

