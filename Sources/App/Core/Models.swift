import Foundation

enum TgAttachmentKind: String, Equatable {
    case photo
    case video
    case voice
    case videoNote
    case animation
    case sticker
    case document
}

struct TgAttachment: Identifiable, Equatable {
    let id: String
    let kind: TgAttachmentKind
    let fileId: Int64?
    let fileName: String?
    let mimeType: String?
    let size: Int64?
    let localPath: String?
}

struct TgChat: Identifiable, Equatable, Codable {
    let id: Int64
    let title: String
    var lastMessagePreview: String?
    var lastMessageId: Int64?
    var lastMessageDate: Date?
    var lastMessageOutgoing: Bool
    var lastMessageRead: Bool
    var avatarPath: String?
    var statusText: String?
    var isOnline: Bool?
    var canSendMessages: Bool?
    var sendRestrictionText: String?
    var unreadCount: Int
    var kind: ChatKind
    var isPinned: Bool
    var pinOrder: Int64?
    var isMuted: Bool
    var muteUntil: Date?
    var isMarkedUnread: Bool
    var draftText: String?
    var typingText: String?
    var privateUserId: Int64?
    var isBlockedByMe: Bool
    var isBlockedByPeer: Bool
    var lastReadOutboxMessageId: Int64

    init(
        id: Int64,
        title: String,
        lastMessagePreview: String? = nil,
        lastMessageId: Int64? = nil,
        lastMessageDate: Date? = nil,
        lastMessageOutgoing: Bool = false,
        lastMessageRead: Bool = false,
        avatarPath: String? = nil,
        statusText: String? = nil,
        isOnline: Bool? = nil,
        canSendMessages: Bool? = nil,
        sendRestrictionText: String? = nil,
        unreadCount: Int = 0,
        kind: ChatKind = .unknown,
        isPinned: Bool = false,
        pinOrder: Int64? = nil,
        isMuted: Bool = false,
        muteUntil: Date? = nil,
        isMarkedUnread: Bool = false,
        draftText: String? = nil,
        typingText: String? = nil,
        privateUserId: Int64? = nil,
        isBlockedByMe: Bool = false,
        isBlockedByPeer: Bool = false,
        lastReadOutboxMessageId: Int64 = 0
    ) {
        self.id = id
        self.title = title
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageId = lastMessageId
        self.lastMessageDate = lastMessageDate
        self.lastMessageOutgoing = lastMessageOutgoing
        self.lastMessageRead = lastMessageRead
        self.avatarPath = avatarPath
        self.statusText = statusText
        self.isOnline = isOnline
        self.canSendMessages = canSendMessages
        self.sendRestrictionText = sendRestrictionText
        self.unreadCount = unreadCount
        self.kind = kind
        self.isPinned = isPinned
        self.pinOrder = pinOrder
        self.isMuted = isMuted
        self.muteUntil = muteUntil
        self.isMarkedUnread = isMarkedUnread
        self.draftText = draftText
        self.typingText = typingText
        self.privateUserId = privateUserId
        self.isBlockedByMe = isBlockedByMe
        self.isBlockedByPeer = isBlockedByPeer
        self.lastReadOutboxMessageId = lastReadOutboxMessageId
    }
}

struct TgMessage: Identifiable, Equatable {
    let id: Int64
    let chatId: Int64
    let text: String
    let outgoing: Bool
    let createdAt: Date
    let isEdited: Bool
    let replyToMessageId: Int64?
    let isDeleted: Bool
    let isReadByPeer: Bool
    let attachments: [TgAttachment]
    let mediaAlbumId: Int64?
    let forwardedFrom: String?
    let senderUserId: Int64?
    let senderName: String?
    let senderAvatarPath: String?
    let authorSignature: String?
    let viewCount: Int?

    init(
        id: Int64,
        chatId: Int64,
        text: String,
        outgoing: Bool,
        createdAt: Date,
        isEdited: Bool,
        replyToMessageId: Int64?,
        isDeleted: Bool,
        isReadByPeer: Bool = false,
        attachments: [TgAttachment],
        mediaAlbumId: Int64?,
        forwardedFrom: String?,
        senderUserId: Int64? = nil,
        senderName: String? = nil,
        senderAvatarPath: String? = nil,
        authorSignature: String? = nil,
        viewCount: Int? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.text = text
        self.outgoing = outgoing
        self.createdAt = createdAt
        self.isEdited = isEdited
        self.replyToMessageId = replyToMessageId
        self.isDeleted = isDeleted
        self.isReadByPeer = isReadByPeer
        self.attachments = attachments
        self.mediaAlbumId = mediaAlbumId
        self.forwardedFrom = forwardedFrom
        self.senderUserId = senderUserId
        self.senderName = senderName
        self.senderAvatarPath = senderAvatarPath
        self.authorSignature = authorSignature
        self.viewCount = viewCount
    }

    func markedDeleted() -> TgMessage {
        TgMessage(
            id: id,
            chatId: chatId,
            text: text,
            outgoing: outgoing,
            createdAt: createdAt,
            isEdited: isEdited,
            replyToMessageId: replyToMessageId,
            isDeleted: true,
            isReadByPeer: isReadByPeer,
            attachments: attachments,
            mediaAlbumId: mediaAlbumId,
            forwardedFrom: forwardedFrom,
            senderUserId: senderUserId,
            senderName: senderName,
            senderAvatarPath: senderAvatarPath,
            authorSignature: authorSignature,
            viewCount: viewCount
        )
    }

    /// Merges a fresher server/store copy with fields already shown in the UI.
    func mergingPreservingDisplayFields(from previous: TgMessage?) -> TgMessage {
        guard let previous else { return self }
        let mergedForward = Self.nonEmpty(forwardedFrom) ?? Self.nonEmpty(previous.forwardedFrom)
        return TgMessage(
            id: id,
            chatId: chatId,
            text: text,
            outgoing: outgoing,
            createdAt: createdAt,
            isEdited: isEdited || previous.isEdited,
            replyToMessageId: replyToMessageId ?? previous.replyToMessageId,
            isDeleted: isDeleted || previous.isDeleted,
            isReadByPeer: isReadByPeer || previous.isReadByPeer,
            attachments: attachments.isEmpty ? previous.attachments : attachments,
            mediaAlbumId: mediaAlbumId ?? previous.mediaAlbumId,
            forwardedFrom: mergedForward,
            senderUserId: senderUserId ?? previous.senderUserId,
            senderName: senderName ?? previous.senderName,
            senderAvatarPath: senderAvatarPath ?? previous.senderAvatarPath,
            authorSignature: authorSignature ?? previous.authorSignature,
            viewCount: viewCount ?? previous.viewCount
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct TgUser: Identifiable, Equatable {
    let id: Int64
    let firstName: String
    let lastName: String
    let username: String?
    let phoneNumber: String?
    let avatarPath: String?

    var displayName: String {
        let name = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty { return name }
        if let username, !username.isEmpty { return "@\(username)" }
        return "User"
    }
}

enum ChatKind: String, Equatable, Codable {
    case `private`
    case savedMessages
    case basicGroup
    case supergroup
    case channel
    case unknown
}

enum ChatMuteDuration: Equatable {
    case off
    case oneHour
    case eightHours
    case forever

    var seconds: Int {
        switch self {
        case .off: return 0
        case .oneHour: return 60 * 60
        case .eightHours: return 8 * 60 * 60
        case .forever: return 367 * 24 * 60 * 60
        }
    }
}

struct ChatProfile: Equatable {
    let chatId: Int64
    let title: String
    let kind: ChatKind
    let avatarPath: String?
    let username: String?
    let description: String?
    let membersCount: Int?
    let statusText: String?
    let userId: Int64?
    let isBlockedByMe: Bool
    let isBlockedByPeer: Bool

    init(
        chatId: Int64,
        title: String,
        kind: ChatKind,
        avatarPath: String?,
        username: String?,
        description: String?,
        membersCount: Int?,
        statusText: String?,
        userId: Int64? = nil,
        isBlockedByMe: Bool = false,
        isBlockedByPeer: Bool = false
    ) {
        self.chatId = chatId
        self.title = title
        self.kind = kind
        self.avatarPath = avatarPath
        self.username = username
        self.description = description
        self.membersCount = membersCount
        self.statusText = statusText
        self.userId = userId
        self.isBlockedByMe = isBlockedByMe
        self.isBlockedByPeer = isBlockedByPeer
    }
}

struct ChatMember: Identifiable, Equatable {
    let id: Int64
    let title: String
    let avatarPath: String?
    let statusText: String?
    let isOnline: Bool?
    let role: String?
}

enum ChatMediaCategory: String, CaseIterable, Identifiable {
    case photos
    case videos
    case voices
    case files
    case links

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: return "Фото"
        case .videos: return "Видео"
        case .voices: return "Voice"
        case .files: return "Files"
        case .links: return "Links"
        }
    }
}

enum AuthState: Equatable {
    case waitPhone
    case waitCode
    case waitPassword
    case ready
}

struct IncomingMessageToast: Identifiable, Equatable {
    let id = UUID()
    let chatId: Int64
    let title: String
    let preview: String
    let avatarPath: String?
}

typealias IncomingMessageBanner = IncomingMessageToast

enum TelegramEvent {
    case authChanged(AuthState)
    case newMessage(TgMessage)
    case messageReplaced(chatId: Int64, oldMessageId: Int64, newMessage: TgMessage)
    case messagesDeleted(chatId: Int64, messageIds: [Int64])
    case chatsChanged
    case chatChanged(Int64)
    case chatTypingChanged(chatId: Int64, text: String?)
}
