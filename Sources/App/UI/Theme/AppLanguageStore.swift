import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        }
    }
}

final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()

    @Published var preferredLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(preferredLanguage.rawValue, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "app.preferredLanguage"

    var isRussian: Bool { preferredLanguage == .russian }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let language = AppLanguage(rawValue: raw) {
            preferredLanguage = language
        } else {
            let code = Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"
            preferredLanguage = code.hasPrefix("ru") ? .russian : .english
        }
    }
}
