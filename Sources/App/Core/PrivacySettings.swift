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
    case profilePhoto
    case status
    case phoneNumber
    case bio
    case forwards
    case findByPhone
    case showLink

    var id: String { rawValue }

    var tdlibType: String {
        switch self {
        case .profilePhoto: return "userPrivacySettingProfilePhoto"
        case .status: return "userPrivacySettingShowStatus"
        case .phoneNumber: return "userPrivacySettingPhoneNumber"
        case .bio: return "userPrivacySettingBio"
        case .forwards: return "userPrivacySettingForwards"
        case .findByPhone: return "userPrivacySettingAllowFindingByPhoneNumber"
        case .showLink: return "userPrivacySettingShowLink"
        }
    }

    var title: String {
        switch self {
        case .profilePhoto: return AppText.tr("Фото профиля", "Profile photo")
        case .status: return AppText.tr("Время захода", "Last seen")
        case .phoneNumber: return AppText.tr("Номер телефона", "Phone number")
        case .bio: return AppText.tr("О себе", "Bio")
        case .forwards: return AppText.tr("Пересылка сообщений", "Forwarded messages")
        case .findByPhone: return AppText.tr("Найти по номеру", "Find by phone")
        case .showLink: return AppText.tr("Ссылка t.me / @username", "t.me link / @username")
        }
    }
}

struct UserPrivacySettingValue: Identifiable, Equatable {
    let kind: UserPrivacySettingKind
    var visibility: PrivacyVisibility

    var id: String { kind.id }
}
