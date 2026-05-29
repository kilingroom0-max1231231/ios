import SwiftUI
import UIKit

enum ChatListBackgroundStyle: String, CaseIterable, Identifiable {
    case system, light, slate, mint, sand, dark, charcoal, lavender

    var id: String { rawValue }

    var titleRu: String {
        switch self {
        case .system: return "Системный"
        case .light: return "Светлый"
        case .slate: return "Серый"
        case .mint: return "Мятный"
        case .sand: return "Песочный"
        case .dark: return "Тёмный"
        case .charcoal: return "Графит"
        case .lavender: return "Лаванда"
        }
    }

    var titleEn: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .slate: return "Slate"
        case .mint: return "Mint"
        case .sand: return "Sand"
        case .dark: return "Dark"
        case .charcoal: return "Charcoal"
        case .lavender: return "Lavender"
        }
    }

    func color(_ scheme: ColorScheme) -> Color {
        switch self {
        case .system:
            return Color(.systemGroupedBackground)
        case .light:
            return scheme == .dark
                ? Color(red: 0.09, green: 0.09, blue: 0.10)
                : Color(red: 0.94, green: 0.94, blue: 0.96)
        case .slate:
            return scheme == .dark
                ? Color(red: 0.08, green: 0.09, blue: 0.11)
                : Color(red: 0.88, green: 0.90, blue: 0.94)
        case .mint:
            return scheme == .dark
                ? Color(red: 0.07, green: 0.10, blue: 0.09)
                : Color(red: 0.90, green: 0.95, blue: 0.92)
        case .sand:
            return scheme == .dark
                ? Color(red: 0.10, green: 0.09, blue: 0.08)
                : Color(red: 0.94, green: 0.91, blue: 0.86)
        case .dark:
            return scheme == .dark
                ? Color(red: 0.07, green: 0.08, blue: 0.10)
                : Color(red: 0.86, green: 0.87, blue: 0.89)
        case .charcoal:
            return scheme == .dark
                ? Color(red: 0.05, green: 0.05, blue: 0.06)
                : Color(red: 0.82, green: 0.83, blue: 0.85)
        case .lavender:
            return scheme == .dark
                ? Color(red: 0.09, green: 0.08, blue: 0.12)
                : Color(red: 0.92, green: 0.90, blue: 0.96)
        }
    }

    /// Slightly elevated surface so rows stay readable on tinted list backgrounds.
    func rowColor(_ scheme: ColorScheme) -> Color {
        switch self {
        case .system:
            return Color(.secondarySystemGroupedBackground)
        default:
            return scheme == .dark
                ? Color.white.opacity(0.06)
                : Color(.systemBackground).opacity(0.88)
        }
    }
}

enum ChatBackgroundStyle: String, CaseIterable, Identifiable {
    case `default`, paper, ocean, forest, night, dusk, rose

    var id: String { rawValue }

    var titleRu: String {
        switch self {
        case .default: return "По умолчанию"
        case .paper: return "Бумага"
        case .ocean: return "Океан"
        case .forest: return "Лес"
        case .night: return "Ночь"
        case .dusk: return "Закат"
        case .rose: return "Розовый"
        }
    }

    var titleEn: String {
        switch self {
        case .default: return "Default"
        case .paper: return "Paper"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .night: return "Night"
        case .dusk: return "Dusk"
        case .rose: return "Rose"
        }
    }

    func color(_ scheme: ColorScheme) -> Color {
        switch self {
        case .default:
            return scheme == .dark
                ? Color(red: 0.08, green: 0.10, blue: 0.14)
                : Color(red: 0.95, green: 0.97, blue: 1.0)
        case .paper:
            return scheme == .dark
                ? Color(red: 0.11, green: 0.11, blue: 0.10)
                : Color(red: 0.96, green: 0.94, blue: 0.90)
        case .ocean:
            return scheme == .dark
                ? Color(red: 0.06, green: 0.12, blue: 0.18)
                : Color(red: 0.90, green: 0.96, blue: 1.0)
        case .forest:
            return scheme == .dark
                ? Color(red: 0.07, green: 0.12, blue: 0.09)
                : Color(red: 0.92, green: 0.97, blue: 0.93)
        case .night:
            return Color(red: 0.05, green: 0.06, blue: 0.09)
        case .dusk:
            return scheme == .dark
                ? Color(red: 0.12, green: 0.08, blue: 0.14)
                : Color(red: 0.98, green: 0.93, blue: 0.96)
        case .rose:
            return scheme == .dark
                ? Color(red: 0.14, green: 0.08, blue: 0.10)
                : Color(red: 1.0, green: 0.95, blue: 0.96)
        }
    }
}

enum AccentColorStyle: String, CaseIterable, Identifiable {
    case telegramBlue, teal, purple, orange, green, red, pink

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .telegramBlue: return Color(red: 0.16, green: 0.53, blue: 0.92)
        case .teal: return Color(red: 0.12, green: 0.66, blue: 0.58)
        case .purple: return Color(red: 0.50, green: 0.34, blue: 0.84)
        case .orange: return Color(red: 0.95, green: 0.50, blue: 0.18)
        case .green: return Color(red: 0.22, green: 0.70, blue: 0.36)
        case .red: return Color(red: 0.90, green: 0.28, blue: 0.28)
        case .pink: return Color(red: 0.92, green: 0.32, blue: 0.58)
        }
    }
}

enum BubbleColorStyle: String, CaseIterable, Identifiable {
    case classic, soft, contrast, midnight

    var id: String { rawValue }

    var titleRu: String {
        switch self {
        case .classic: return "Классика"
        case .soft: return "Мягкие"
        case .contrast: return "Контраст"
        case .midnight: return "Полночь"
        }
    }

    var titleEn: String {
        switch self {
        case .classic: return "Classic"
        case .soft: return "Soft"
        case .contrast: return "Contrast"
        case .midnight: return "Midnight"
        }
    }

    func incoming(_ scheme: ColorScheme) -> Color {
        switch self {
        case .classic: return Color(UIColor.secondarySystemBackground)
        case .soft: return scheme == .dark ? Color(red: 0.18, green: 0.19, blue: 0.22) : Color(red: 0.94, green: 0.95, blue: 0.97)
        case .contrast: return scheme == .dark ? Color(red: 0.22, green: 0.24, blue: 0.28) : Color.white
        case .midnight: return Color(red: 0.14, green: 0.16, blue: 0.20)
        }
    }

    func outgoing(_ scheme: ColorScheme) -> Color {
        switch self {
        case .classic:
            return scheme == .dark
                ? Color(red: 0.20, green: 0.37, blue: 0.60)
                : Color(red: 0.86, green: 0.95, blue: 1.0)
        case .soft:
            return scheme == .dark
                ? Color(red: 0.24, green: 0.42, blue: 0.38)
                : Color(red: 0.88, green: 0.97, blue: 0.92)
        case .contrast:
            return scheme == .dark
                ? Color(red: 0.28, green: 0.48, blue: 0.78)
                : Color(red: 0.78, green: 0.90, blue: 1.0)
        case .midnight:
            return Color(red: 0.18, green: 0.32, blue: 0.52)
        }
    }

    func outgoingText(_ scheme: ColorScheme) -> Color {
        switch self {
        case .midnight: return .white
        default: return scheme == .dark ? .white : .black
        }
    }
}

enum MessageFontScale: String, CaseIterable, Identifiable {
    case small, normal, large

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .small: return 0.92
        case .normal: return 1.0
        case .large: return 1.12
        }
    }

    var titleRu: String {
        switch self {
        case .small: return "Мелкий"
        case .normal: return "Обычный"
        case .large: return "Крупный"
        }
    }

    var titleEn: String {
        switch self {
        case .small: return "Small"
        case .normal: return "Normal"
        case .large: return "Large"
        }
    }
}

enum AppColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var titleRu: String {
        switch self {
        case .system: return "Как в системе"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var titleEn: String {
        switch self {
        case .system: return "Match system"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppAppearanceStore: ObservableObject {
    static let shared = AppAppearanceStore()

    @Published var colorSchemePreference: AppColorSchemePreference { didSet { persist() } }
    @Published var chatListStyle: ChatListBackgroundStyle { didSet { persist() } }
    @Published var chatStyle: ChatBackgroundStyle { didSet { persist() } }
    @Published var accentStyle: AccentColorStyle { didSet { persist() } }
    @Published var bubbleStyle: BubbleColorStyle { didSet { persist() } }
    @Published var messageFontScale: MessageFontScale { didSet { persist() } }
    @Published var chatWallpaperPath: String? { didSet { UserDefaults.standard.set(chatWallpaperPath, forKey: Keys.chatWallpaper) } }
    @Published var wallpaperOpacity: Double { didSet { UserDefaults.standard.set(wallpaperOpacity, forKey: Keys.wallpaperOpacity) } }
    @Published var compactBubbles: Bool { didSet { UserDefaults.standard.set(compactBubbles, forKey: Keys.compactBubbles) } }

    private enum Keys {
        static let colorSchemePreference = "appearance.colorSchemePreference"
        static let chatListStyle = "appearance.chatListStyle"
        static let chatStyle = "appearance.chatStyle"
        static let accentStyle = "appearance.accentStyle"
        static let bubbleStyle = "appearance.bubbleStyle"
        static let messageFontScale = "appearance.messageFontScale"
        static let chatWallpaper = "appearance.chatWallpaperPath"
        static let wallpaperOpacity = "appearance.wallpaperOpacity"
        static let compactBubbles = "appearance.compactBubbles"
    }

    private init() {
        let defaults = UserDefaults.standard
        colorSchemePreference = AppColorSchemePreference(rawValue: defaults.string(forKey: Keys.colorSchemePreference) ?? "") ?? .system
        chatListStyle = ChatListBackgroundStyle(rawValue: defaults.string(forKey: Keys.chatListStyle) ?? "") ?? .system
        chatStyle = ChatBackgroundStyle(rawValue: defaults.string(forKey: Keys.chatStyle) ?? "") ?? .default
        accentStyle = AccentColorStyle(rawValue: defaults.string(forKey: Keys.accentStyle) ?? "") ?? .telegramBlue
        bubbleStyle = BubbleColorStyle(rawValue: defaults.string(forKey: Keys.bubbleStyle) ?? "") ?? .classic
        messageFontScale = MessageFontScale(rawValue: defaults.string(forKey: Keys.messageFontScale) ?? "") ?? .normal
        chatWallpaperPath = defaults.string(forKey: Keys.chatWallpaper)
        let opacity = defaults.object(forKey: Keys.wallpaperOpacity) as? Double
        wallpaperOpacity = opacity ?? 0.55
        compactBubbles = defaults.object(forKey: Keys.compactBubbles) as? Bool ?? false
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(colorSchemePreference.rawValue, forKey: Keys.colorSchemePreference)
        defaults.set(chatListStyle.rawValue, forKey: Keys.chatListStyle)
        defaults.set(chatStyle.rawValue, forKey: Keys.chatStyle)
        defaults.set(accentStyle.rawValue, forKey: Keys.accentStyle)
        defaults.set(bubbleStyle.rawValue, forKey: Keys.bubbleStyle)
        defaults.set(messageFontScale.rawValue, forKey: Keys.messageFontScale)
    }

    var resolvedColorScheme: ColorScheme? {
        colorSchemePreference.colorScheme
    }

    func resetToDefaults() {
        colorSchemePreference = .system
        chatListStyle = .system
        chatStyle = .default
        accentStyle = .telegramBlue
        bubbleStyle = .classic
        messageFontScale = .normal
        wallpaperOpacity = 0.55
        compactBubbles = false
        clearWallpaper()
    }

    var accentColor: Color { accentStyle.color }

    func chatListColor(colorScheme: ColorScheme) -> Color {
        chatListStyle.color(colorScheme)
    }

    func chatListRowColor(colorScheme: ColorScheme) -> Color {
        chatListStyle.rowColor(colorScheme)
    }

    func chatColor(colorScheme: ColorScheme) -> Color {
        chatStyle.color(colorScheme)
    }

    func incomingBubble(colorScheme: ColorScheme) -> Color {
        bubbleStyle.incoming(colorScheme)
    }

    func outgoingBubble(colorScheme: ColorScheme) -> Color {
        bubbleStyle.outgoing(colorScheme)
    }

    func outgoingText(colorScheme: ColorScheme) -> Color {
        bubbleStyle.outgoingText(colorScheme)
    }

    func messageFont(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .default).weight(.regular)
    }

    func scaledFont(_ style: Font.TextStyle = .body) -> Font {
        messageFont(style).weight(.regular)
    }

    func chatWallpaperImage() -> UIImage? {
        guard let chatWallpaperPath, !chatWallpaperPath.isEmpty else { return nil }
        return UIImage(contentsOfFile: chatWallpaperPath)
    }

    func setWallpaper(from image: UIImage) throws {
        let directory = try wallpaperDirectory()
        let path = directory.appendingPathComponent("chat_wallpaper.jpg").path
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            throw NSError(domain: "AppAppearanceStore", code: 1, userInfo: nil)
        }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        chatWallpaperPath = path
    }

    func clearWallpaper() {
        if let chatWallpaperPath {
            try? FileManager.default.removeItem(atPath: chatWallpaperPath)
        }
        chatWallpaperPath = nil
    }

    private func wallpaperDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Appearance", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

struct ChatScreenBackground: View {
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                appearance.chatColor(colorScheme: colorScheme)

                if let uiImage = appearance.chatWallpaperImage() {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(appearance.wallpaperOpacity * (colorScheme == .dark ? 0.75 : 1.0))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

struct ChatListScreenBackground: View {
    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }
}

struct ChatListRowBackground: View {
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        appearance.chatListRowColor(colorScheme: colorScheme)
    }
}
