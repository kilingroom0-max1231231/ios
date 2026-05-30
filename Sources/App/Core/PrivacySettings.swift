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
    case bio
    case forwards
    case groupInvites
    case calls
    case findByPhone

    var id: String { rawValue }

    /// Settings shown under the Privacy section (Telegram order).
    static let privacySection: [UserPrivacySettingKind] = [
        .phoneNumber, .status, .profilePhoto, .bio, .forwards, .groupInvites, .calls
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
        case .findByPhone: return "userPrivacySettingAllowFindingByPhoneNumber"
        }
    }

    var title: String {
        switch self {
        case .profilePhoto: return AppText.tr("Фото профиля", "Profile photos")
        case .status: return AppText.tr("Время захода", "Last seen & online")
        case .phoneNumber: return AppText.tr("Номер телефона", "Phone number")
        case .bio: return AppText.tr("О себе", "Bio")
        case .forwards: return AppText.tr("Пересылка сообщений", "Forwarded messages")
        case .groupInvites: return AppText.tr("Группы и каналы", "Groups & channels")
        case .calls: return AppText.tr("Звонки", "Calls")
        case .findByPhone: return AppText.tr("Найти по номеру", "Find by phone number")
        }
    }

    /// Base visibility options available for this setting in Telegram.
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

    /// Whether the Always Allow exceptions row is shown (Telegram-style).
    var showsAlwaysAllowSection: Bool {
        baseVisibility == .nobody || baseVisibility == .contacts
    }

    /// Whether the Never Allow exceptions row is shown.
    var showsNeverAllowSection: Bool {
        baseVisibility == .everybody || baseVisibility == .contacts
    }
}

/// @deprecated name kept for minimal churn — use UserPrivacyRules.
typealias UserPrivacySettingValue = UserPrivacyRules

extension UserPrivacyRules {
    var visibility: PrivacyVisibility {
        get { baseVisibility }
        set { baseVisibility = newValue }
    }
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
