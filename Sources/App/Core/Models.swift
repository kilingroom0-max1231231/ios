import Foundation

enum TgAttachmentKind: String, Equatable {
    case photo
    case video
    case voice
    case videoNote
    case animation
    case sticker
    case gift
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
    let animationPath: String?
    let isPremiumSticker: Bool

    init(
        id: String,
        kind: TgAttachmentKind,
        fileId: Int64?,
        fileName: String?,
        mimeType: String?,
        size: Int64?,
        localPath: String?,
        animationPath: String? = nil,
        isPremiumSticker: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.fileId = fileId
        self.fileName = fileName
        self.mimeType = mimeType
        self.size = size
        self.localPath = localPath
        self.animationPath = animationPath
        self.isPremiumSticker = isPremiumSticker
    }

    var isAnimatedSticker: Bool {
        guard let animationPath, !animationPath.isEmpty else { return false }
        let ext = URL(fileURLWithPath: animationPath).pathExtension.lowercased()
        return ext == "webm" || ext == "mp4" || ext == "mov"
    }
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
    var canAddReactions: Bool?
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
    var peerIsPremium: Bool
    var peerPremiumBadgePath: String?
    var peerUsername: String?
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
        canAddReactions: Bool? = nil,
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
        peerIsPremium: Bool = false,
        peerPremiumBadgePath: String? = nil,
        peerUsername: String? = nil,
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
        self.canAddReactions = canAddReactions
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
        self.peerIsPremium = peerIsPremium
        self.peerPremiumBadgePath = peerPremiumBadgePath
        self.peerUsername = peerUsername
        self.isBlockedByMe = isBlockedByMe
        self.isBlockedByPeer = isBlockedByPeer
        self.lastReadOutboxMessageId = lastReadOutboxMessageId
    }
}

struct TgMessageReaction: Identifiable, Equatable, Codable {
    /// Stable key: emoji or `custom:<id>`.
    let key: String
    let emoji: String
    let count: Int
    let isChosen: Bool
    var customEmojiId: Int64?
    var imagePath: String?

    init(key: String, emoji: String, count: Int, isChosen: Bool, customEmojiId: Int64? = nil, imagePath: String? = nil) {
        self.key = key
        self.emoji = emoji
        self.count = count
        self.isChosen = isChosen
        self.customEmojiId = customEmojiId
        self.imagePath = imagePath
    }

    var id: String { key }

    var isCustomEmoji: Bool { customEmojiId != nil }
}

struct TgReactionPickerItem: Identifiable, Equatable, Hashable {
    /// Emoji character or `custom:<id>`.
    let key: String
    /// Unicode fallback for standard emoji.
    let emoji: String
    let customEmojiId: Int64?
    let imagePath: String?

    var id: String { key }

    var isCustomEmoji: Bool { customEmojiId != nil }
}

struct TgAvailableReactions: Equatable {
    let items: [TgReactionPickerItem]
    /// How many reactions the current user may set on one message (1 without Premium, more with Premium).
    let maxReactionCount: Int

    var emojis: [String] {
        items.filter { !$0.isCustomEmoji }.map(\.emoji)
    }
}

struct TgForwardOrigin: Equatable {
    enum Kind: Equatable {
        case user(userId: Int64)
        case hiddenUser
        case chat(chatId: Int64)
        case channel(chatId: Int64)
    }

    let kind: Kind
    let displayName: String

    var isNavigable: Bool {
        switch kind {
        case .hiddenUser: return false
        default: return true
        }
    }
}

struct TgActiveSession: Identifiable, Equatable {
    let id: Int64
    let isCurrent: Bool
    let platform: String
    let systemVersion: String
    let applicationName: String
    let applicationVersion: String
    let deviceModel: String
    let ip: String
    let country: String
    let region: String
    let logInDate: Date
    let lastActiveDate: Date

    var title: String {
        let model = deviceModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { return model }
        let app = applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.isEmpty ? AppText.tr("Неизвестное устройство", "Unknown device") : app
    }

    var subtitle: String {
        let app = applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let platformLabel = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        return [app, platformLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var locationText: String {
        let parts = [region, country].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if parts.isEmpty { return ip }
        let location = parts.joined(separator: ", ")
        return ip.isEmpty ? location : "\(location) · \(ip)"
    }
}

struct TgMessageTextEntity: Equatable {
    let offset: Int
    let length: Int
    let url: URL
}

struct TgInlineKeyboardButton: Identifiable, Equatable {
    let id: String
    let text: String
    let action: TgInlineKeyboardAction
}

struct TgInlineKeyboardRow: Identifiable, Equatable {
    let id: String
    let buttons: [TgInlineKeyboardButton]
}

enum TgInlineKeyboardAction: Equatable {
    case url(URL)
    case callback(data: String)
    case switchInline(query: String, chooseChatTypes: Bool)
    case copyText(String)
    case webApp(URL)
}

struct TgReplyKeyboardButton: Identifiable, Equatable {
    let id: String
    let text: String
}

struct TgReplyKeyboardRow: Identifiable, Equatable {
    let id: String
    let buttons: [TgReplyKeyboardButton]
}

struct TgReplyKeyboardMarkup: Equatable {
    let rows: [TgReplyKeyboardRow]
    let isPersistent: Bool
    let resizeKeyboard: Bool
    let oneTime: Bool
    let placeholder: String?
}

enum TgMessageReplyMarkup: Equatable {
    case inline([TgInlineKeyboardRow])
    case reply(TgReplyKeyboardMarkup)
    case removeKeyboard
}

struct TgMessage: Identifiable, Equatable {
    let id: Int64
    let chatId: Int64
    let text: String
    /// TDLib link / mention spans for tappable message text.
    let textEntities: [TgMessageTextEntity]
    let outgoing: Bool
    let createdAt: Date
    let isEdited: Bool
    let replyToMessageId: Int64?
    let isDeleted: Bool
    let isReadByPeer: Bool
    let attachments: [TgAttachment]
    let mediaAlbumId: Int64?
    let forwardedFrom: String?
    let forwardOrigin: TgForwardOrigin?
    let senderUserId: Int64?
    let senderName: String?
    let senderAvatarPath: String?
    let authorSignature: String?
    let viewCount: Int?
    let reactions: [TgMessageReaction]
    /// True for chat service/system events (joins, pins, title changes, etc.).
    let isService: Bool
    let replyMarkup: TgMessageReplyMarkup?

    init(
        id: Int64,
        chatId: Int64,
        text: String,
        textEntities: [TgMessageTextEntity] = [],
        outgoing: Bool,
        createdAt: Date,
        isEdited: Bool,
        replyToMessageId: Int64?,
        isDeleted: Bool,
        isReadByPeer: Bool = false,
        attachments: [TgAttachment],
        mediaAlbumId: Int64?,
        forwardedFrom: String?,
        forwardOrigin: TgForwardOrigin? = nil,
        senderUserId: Int64? = nil,
        senderName: String? = nil,
        senderAvatarPath: String? = nil,
        authorSignature: String? = nil,
        viewCount: Int? = nil,
        reactions: [TgMessageReaction] = [],
        isService: Bool = false,
        replyMarkup: TgMessageReplyMarkup? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.text = text
        self.textEntities = textEntities
        self.outgoing = outgoing
        self.createdAt = createdAt
        self.isEdited = isEdited
        self.replyToMessageId = replyToMessageId
        self.isDeleted = isDeleted
        self.isReadByPeer = isReadByPeer
        self.attachments = attachments
        self.mediaAlbumId = mediaAlbumId
        self.forwardedFrom = forwardedFrom
        self.forwardOrigin = forwardOrigin
        self.senderUserId = senderUserId
        self.senderName = senderName
        self.senderAvatarPath = senderAvatarPath
        self.authorSignature = authorSignature
        self.viewCount = viewCount
        self.reactions = reactions
        self.isService = isService
        self.replyMarkup = replyMarkup
    }

    func withSenderDisplay(name: String?, avatarPath: String?) -> TgMessage {
        TgMessage(
            id: id,
            chatId: chatId,
            text: text,
            textEntities: textEntities,
            outgoing: outgoing,
            createdAt: createdAt,
            isEdited: isEdited,
            replyToMessageId: replyToMessageId,
            isDeleted: isDeleted,
            isReadByPeer: isReadByPeer,
            attachments: attachments,
            mediaAlbumId: mediaAlbumId,
            forwardedFrom: forwardedFrom,
            forwardOrigin: forwardOrigin,
            senderUserId: senderUserId,
            senderName: name ?? senderName,
            senderAvatarPath: avatarPath ?? senderAvatarPath,
            authorSignature: authorSignature,
            viewCount: viewCount,
            reactions: reactions,
            isService: isService,
            replyMarkup: replyMarkup
        )
    }

    func withReactions(_ newReactions: [TgMessageReaction]) -> TgMessage {
        TgMessage(
            id: id,
            chatId: chatId,
            text: text,
            textEntities: textEntities,
            outgoing: outgoing,
            createdAt: createdAt,
            isEdited: isEdited,
            replyToMessageId: replyToMessageId,
            isDeleted: isDeleted,
            isReadByPeer: isReadByPeer,
            attachments: attachments,
            mediaAlbumId: mediaAlbumId,
            forwardedFrom: forwardedFrom,
            forwardOrigin: forwardOrigin,
            senderUserId: senderUserId,
            senderName: senderName,
            senderAvatarPath: senderAvatarPath,
            authorSignature: authorSignature,
            viewCount: viewCount,
            reactions: newReactions,
            isService: isService,
            replyMarkup: replyMarkup
        )
    }

    func markedDeleted() -> TgMessage {
        TgMessage(
            id: id,
            chatId: chatId,
            text: text,
            textEntities: textEntities,
            outgoing: outgoing,
            createdAt: createdAt,
            isEdited: isEdited,
            replyToMessageId: replyToMessageId,
            isDeleted: true,
            isReadByPeer: isReadByPeer,
            attachments: attachments,
            mediaAlbumId: mediaAlbumId,
            forwardedFrom: forwardedFrom,
            forwardOrigin: forwardOrigin,
            senderUserId: senderUserId,
            senderName: senderName,
            senderAvatarPath: senderAvatarPath,
            authorSignature: authorSignature,
            viewCount: viewCount,
            reactions: reactions,
            isService: isService,
            replyMarkup: replyMarkup
        )
    }

    /// Merges a fresher server/store copy with fields already shown in the UI.
    func mergingPreservingDisplayFields(from previous: TgMessage?) -> TgMessage {
        guard let previous else { return self }
        let mergedForward = Self.nonEmpty(forwardedFrom) ?? Self.nonEmpty(previous.forwardedFrom)
        let mergedOrigin = forwardOrigin ?? previous.forwardOrigin
        return TgMessage(
            id: id,
            chatId: chatId,
            text: text,
            textEntities: textEntities.isEmpty ? previous.textEntities : textEntities,
            outgoing: outgoing,
            createdAt: createdAt,
            isEdited: isEdited || previous.isEdited,
            replyToMessageId: replyToMessageId ?? previous.replyToMessageId,
            isDeleted: isDeleted || previous.isDeleted,
            isReadByPeer: isReadByPeer || previous.isReadByPeer,
            attachments: attachments.isEmpty ? previous.attachments : attachments,
            mediaAlbumId: mediaAlbumId ?? previous.mediaAlbumId,
            forwardedFrom: mergedForward,
            forwardOrigin: mergedOrigin,
            senderUserId: senderUserId ?? previous.senderUserId,
            senderName: senderName ?? previous.senderName,
            senderAvatarPath: senderAvatarPath ?? previous.senderAvatarPath,
            authorSignature: authorSignature ?? previous.authorSignature,
            viewCount: viewCount ?? previous.viewCount,
            reactions: reactions,
            isService: isService,
            replyMarkup: replyMarkup ?? previous.replyMarkup
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
    let bio: String?
    let avatarPath: String?
    let isPremium: Bool
    let premiumBadgePath: String?

    init(
        id: Int64,
        firstName: String,
        lastName: String,
        username: String?,
        phoneNumber: String?,
        bio: String? = nil,
        avatarPath: String?,
        isPremium: Bool,
        premiumBadgePath: String?
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.phoneNumber = phoneNumber
        self.bio = bio
        self.avatarPath = avatarPath
        self.isPremium = isPremium
        self.premiumBadgePath = premiumBadgePath
    }

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

enum TgChatListKind: Equatable {
    case main
    case archive
    case folder(Int32)

    var tdlibDictionary: [String: Any] {
        switch self {
        case .main:
            return ["@type": "chatListMain"]
        case .archive:
            return ["@type": "chatListArchive"]
        case .folder(let id):
            return ["@type": "chatListFolder", "chat_folder_id": NSNumber(value: id)]
        }
    }

    var listTypeName: String {
        switch self {
        case .main: return "chatListMain"
        case .archive: return "chatListArchive"
        case .folder: return "chatListFolder"
        }
    }
}

struct TextSegment: Equatable {
    enum Content: Equatable {
        case text(String)
        case customEmoji(id: Int64, path: String?)
    }

    let content: Content
}

struct TgChatFolder: Identifiable, Equatable {
    let id: Int32
    let title: String
    let titleSegments: [TextSegment]
    let iconEmoji: String?
    let iconCustomEmojiId: Int64?
    let iconImagePath: String?
    let colorId: Int

    init(
        id: Int32,
        title: String,
        titleSegments: [TextSegment]? = nil,
        iconEmoji: String? = nil,
        iconCustomEmojiId: Int64? = nil,
        iconImagePath: String? = nil,
        colorId: Int = 0
    ) {
        self.id = id
        self.title = title
        self.titleSegments = titleSegments ?? [.init(content: .text(title))]
        self.iconEmoji = iconEmoji
        self.iconCustomEmojiId = iconCustomEmojiId
        self.iconImagePath = iconImagePath
        self.colorId = colorId
    }
}

struct ArchiveChatSummary: Equatable {
    let count: Int
    let unreadCount: Int
    let preview: String?
    let topChatTitle: String?
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

struct ProfileLinkedChannel: Equatable, Identifiable {
    let chatId: Int64
    let title: String
    let username: String?
    let avatarPath: String?

    var id: Int64 { chatId }
}

struct TgContact: Identifiable, Equatable {
    let userId: Int64
    let displayName: String
    let phoneNumber: String?
    let username: String?
    let avatarPath: String?
    let isPremium: Bool
    let premiumBadgePath: String?
    let privateChatId: Int64

    var id: Int64 { userId }
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
    let phoneNumber: String?
    let personalChannel: ProfileLinkedChannel?
    let isPremium: Bool
    let premiumBadgePath: String?
    let hasActiveStories: Bool
    let giftCount: Int
    let isBlockedByMe: Bool
    let isBlockedByPeer: Bool
    let inviteLink: String?
    let isBot: Bool

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
        phoneNumber: String? = nil,
        personalChannel: ProfileLinkedChannel? = nil,
        isPremium: Bool = false,
        premiumBadgePath: String? = nil,
        hasActiveStories: Bool = false,
        giftCount: Int = 0,
        isBlockedByMe: Bool = false,
        isBlockedByPeer: Bool = false,
        inviteLink: String? = nil,
        isBot: Bool = false
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
        self.phoneNumber = phoneNumber
        self.personalChannel = personalChannel
        self.isPremium = isPremium
        self.premiumBadgePath = premiumBadgePath
        self.hasActiveStories = hasActiveStories
        self.giftCount = giftCount
        self.isBlockedByMe = isBlockedByMe
        self.isBlockedByPeer = isBlockedByPeer
        self.inviteLink = inviteLink
        self.isBot = isBot
    }
}

struct UserProfileDetail: Equatable, Identifiable {
    var id: Int64 { userId }
    let userId: Int64
    let privateChatId: Int64
    let displayName: String
    let username: String?
    let phoneNumber: String?
    let bio: String?
    let avatarPath: String?
    let personalChannel: ProfileLinkedChannel?
    var statusText: String?
    var isOnline: Bool
    let isPremium: Bool
    let premiumBadgePath: String?
    let hasActiveStories: Bool
    let giftCount: Int
    let isBlockedByMe: Bool
    let isBlockedByPeer: Bool
    let isSelf: Bool
}

struct TgStoryItem: Identifiable, Equatable {
    let id: Int64
    let chatId: Int64
    let date: Date
    let caption: String
    let previewPath: String?
    let mediaPath: String?
    let isVideo: Bool
    let isViewed: Bool
}

struct TgSticker: Identifiable, Equatable {
    let fileId: Int64
    let emoji: String
    let width: Int
    let height: Int
    let displayPath: String?
    let animationPath: String?
    let isAnimated: Bool
    let localPath: String?

    var id: Int64 { fileId }

    init(
        fileId: Int64,
        emoji: String,
        width: Int = 512,
        height: Int = 512,
        displayPath: String? = nil,
        animationPath: String? = nil,
        isAnimated: Bool = false,
        localPath: String? = nil
    ) {
        self.fileId = fileId
        self.emoji = emoji
        self.width = width
        self.height = height
        self.displayPath = displayPath
        self.animationPath = animationPath
        self.isAnimated = isAnimated
        self.localPath = localPath
    }
}

struct TgGiftItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let stickerPath: String?
    let animationPath: String?
    let isAnimated: Bool
    let senderUserId: Int64?
    let senderName: String?
    let senderAvatarPath: String?
    let senderIsPremium: Bool
    let senderPremiumBadgePath: String?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        stickerPath: String? = nil,
        animationPath: String? = nil,
        isAnimated: Bool = false,
        senderUserId: Int64? = nil,
        senderName: String? = nil,
        senderAvatarPath: String? = nil,
        senderIsPremium: Bool = false,
        senderPremiumBadgePath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.stickerPath = stickerPath
        self.animationPath = animationPath
        self.isAnimated = isAnimated
        self.senderUserId = senderUserId
        self.senderName = senderName
        self.senderAvatarPath = senderAvatarPath
        self.senderIsPremium = senderIsPremium
        self.senderPremiumBadgePath = senderPremiumBadgePath
    }
}

struct ChatMember: Identifiable, Equatable {
    let id: Int64
    let title: String
    let username: String?
    let avatarPath: String?
    let statusText: String?
    let isOnline: Bool?
    let isPremium: Bool
    let premiumBadgePath: String?
    let role: String?
    let isUser: Bool
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

struct TgBlockedSender: Identifiable, Equatable {
    let id: String
    let userId: Int64?
    let chatId: Int64?
    let title: String
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
    case chatFoldersChanged
    case chatChanged(Int64)
    case chatTypingChanged(chatId: Int64, userId: Int64?, actionKey: String?)
    case userStatusChanged(userId: Int64, statusText: String, isOnline: Bool)
    case messageInteractionUpdated(chatId: Int64, messageId: Int64, reactions: [TgMessageReaction], viewCount: Int?)
}

struct ChatTypingUpdate: Equatable {
    let chatId: Int64
    let userId: Int64?
    /// `nil` = cancel typing for this user (or entire chat when userId is nil).
    let actionKey: String?
}
