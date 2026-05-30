import Foundation

enum PrivacyVisibility: String, CaseIterable, Identifiable {
    case everybody
    case contacts
    case nobody

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everybody: return AppText.tr("Все", "Everybody")
        case .contacts: return AppText.tr("Контакты", "Contacts")
        case .nobody: return AppText.tr("Никто", "Nobody")
        }
    }
}

enum UserPrivacySettingKind: String, CaseIterable, Identifiable {
    case phoneNumber
    case status
    case profilePhoto
    case forwards
    case calls
    case voiceMessages
    case messages
    case birthday
    case gifts
    case bio
    case savedMusic
    case groupInvites
    case findByPhone

    var id: String { rawValue }

    /// First privacy block — matches Telegram «Конфиденциальность» (top).
    static let primaryPrivacySection: [UserPrivacySettingKind] = [
        .phoneNumber, .status, .profilePhoto, .forwards, .calls, .voiceMessages
    ]

    /// Extended privacy rows (scroll below the fold in official app).
    static let extendedPrivacySection: [UserPrivacySettingKind] = [
        .messages, .birthday, .gifts, .bio, .savedMusic, .groupInvites
    ]

    static let discoverySection: [UserPrivacySettingKind] = [.findByPhone]

    var tdlibType: String {
        switch self {
        case .profilePhoto: return "userPrivacySettingShowProfilePhoto"
        case .status: return "userPrivacySettingShowStatus"
        case .phoneNumber: return "userPrivacySettingShowPhoneNumber"
        case .bio: return "userPrivacySettingShowBio"
        case .forwards: return "userPrivacySettingShowLinkInForwardedMessages"
        case .groupInvites: return "userPrivacySettingAllowChatInvites"
        case .calls: return "userPrivacySettingAllowCalls"
        case .voiceMessages: return "userPrivacySettingAllowPrivateVoiceAndVideoNoteMessages"
        case .messages: return "userPrivacySettingAllowUnpaidMessages"
        case .birthday: return "userPrivacySettingShowBirthdate"
        case .gifts: return "userPrivacySettingAutosaveGifts"
        case .savedMusic: return "userPrivacySettingShowProfileAudio"
        case .findByPhone: return "userPrivacySettingAllowFindingByPhoneNumber"
        }
    }

    var title: String {
        switch self {
        case .profilePhoto: return AppText.tr("Фотографии профиля", "Profile photos")
        case .status: return AppText.tr("Время захода", "Last seen & online")
        case .phoneNumber: return AppText.tr("Номер телефона", "Phone number")
        case .bio: return AppText.tr("О себе", "About me")
        case .forwards: return AppText.tr("Пересылка сообщений", "Forwarded messages")
        case .groupInvites: return AppText.tr("Приглашения", "Invitations")
        case .calls: return AppText.tr("Звонки", "Calls")
        case .voiceMessages: return AppText.tr("Голосовые сообщения", "Voice messages")
        case .messages: return AppText.tr("Сообщения", "Messages")
        case .birthday: return AppText.tr("День рождения", "Birthday")
        case .gifts: return AppText.tr("Подарки", "Gifts")
        case .savedMusic: return AppText.tr("Сохранённая музыка", "Saved music")
        case .findByPhone: return AppText.tr("Найти по номеру", "Find by phone number")
        }
    }

    var availableBaseOptions: [PrivacyVisibility] {
        switch self {
        case .findByPhone:
            return [.everybody, .contacts]
        default:
            return PrivacyVisibility.allCases
        }
    }

    var footer: String? {
        switch self {
        case .phoneNumber:
            return AppText.tr(
                "Укажите, кто может видеть ваш номер телефона.",
                "Choose who can see your phone number."
            )
        case .status:
            return AppText.tr(
                "Укажите, кто может видеть время вашего последнего захода.",
                "Choose who can see when you were last online."
            )
        case .profilePhoto:
            return AppText.tr(
                "Укажите, кто может видеть фото вашего профиля.",
                "Choose who can see your profile photos."
            )
        case .bio:
            return AppText.tr(
                "Укажите, кто может видеть текст «О себе».",
                "Choose who can see your bio."
            )
        case .forwards:
            return AppText.tr(
                "Укажите, кому будет видна ссылка на ваш аккаунт при пересылке сообщений.",
                "Choose who can see a link to your account when your messages are forwarded."
            )
        case .groupInvites:
            return AppText.tr(
                "Укажите, кто может добавлять вас в группы и каналы.",
                "Choose who can add you to groups and channels."
            )
        case .calls:
            return AppText.tr(
                "Укажите, кто может звонить вам в Telegram.",
                "Choose who can call you on Telegram."
            )
        case .voiceMessages:
            return AppText.tr(
                "Укажите, кто может отправлять вам голосовые и видеосообщения.",
                "Choose who can send you voice and video messages."
            )
        case .messages:
            return AppText.tr(
                "Укажите, кто может писать вам без дополнительной оплаты.",
                "Choose who can message you without additional payment."
            )
        case .birthday:
            return AppText.tr(
                "Укажите, кто может видеть ваш день рождения.",
                "Choose who can see your birthday."
            )
        case .gifts:
            return AppText.tr(
                "Укажите, будут ли полученные подарки автоматически показываться в профиле.",
                "Choose whether received gifts are shown on your profile."
            )
        case .savedMusic:
            return AppText.tr(
                "Укажите, кто может видеть сохранённую музыку в вашем профиле.",
                "Choose who can see saved music on your profile."
            )
        case .findByPhone:
            return AppText.tr(
                "Если вы выключите эту опцию, пользователи не смогут найти вас по номеру телефона.",
                "If you turn this off, users won't find you by your phone number."
            )
        }
    }
}

struct UserPrivacyRules: Identifiable, Equatable {
    let kind: UserPrivacySettingKind
    var baseVisibility: PrivacyVisibility
    var allowUserIds: [Int64]
    var restrictUserIds: [Int64]

    var id: String { kind.id }

    static func `default`(for kind: UserPrivacySettingKind) -> UserPrivacyRules {
        UserPrivacyRules(
            kind: kind,
            baseVisibility: .contacts,
            allowUserIds: [],
            restrictUserIds: []
        )
    }

    var showsAlwaysAllowSection: Bool {
        baseVisibility == .nobody || baseVisibility == .contacts
    }

    var showsNeverAllowSection: Bool {
        baseVisibility == .everybody || baseVisibility == .contacts
    }

    /// Telegram-style hub label, e.g. «Никто (+3)».
    var hubSummary: String {
        let base = baseVisibility.title
        let exceptionCount: Int
        switch baseVisibility {
        case .nobody:
            exceptionCount = allowUserIds.count
        case .everybody:
            exceptionCount = restrictUserIds.count
        case .contacts:
            exceptionCount = allowUserIds.count + restrictUserIds.count
        }
        guard exceptionCount > 0 else { return base }
        return "\(base) (+\(exceptionCount))"
    }
}

typealias UserPrivacySettingValue = UserPrivacyRules

extension UserPrivacyRules {
    var visibility: PrivacyVisibility {
        get { baseVisibility }
        set { baseVisibility = newValue }
    }
}

struct AccountSecuritySnapshot: Equatable {
    var hasCloudPassword = false
    var loginEmailPattern: String?
    var messageAutoDeleteSeconds = 0
    var accountDeleteDays = 0
    var blockedUsersCount = 0
}

enum GlobalSearchScope: String, CaseIterable, Identifiable {
    case myChats
    case telegram

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myChats: return AppText.tr("Мои чаты", "My chats")
        case .telegram: return AppText.tr("Telegram", "Telegram")
        }
    }
}

struct GlobalSearchMessageHit: Identifiable, Equatable {
    let id: String
    let chatTitle: String
    let message: TgMessage
}
