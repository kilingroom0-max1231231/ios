import Foundation

enum AppText {
    static var isRussian: Bool {
        Locale.autoupdatingCurrent.language.languageCode?.identifier == "ru"
    }

    static func tr(_ ru: String, _ en: String) -> String {
        isRussian ? ru : en
    }
}

