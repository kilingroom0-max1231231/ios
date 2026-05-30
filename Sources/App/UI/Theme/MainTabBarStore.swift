import Foundation
import SwiftUI

enum MainTab: String, Codable, CaseIterable, Identifiable {
    case chats
    case contacts
    case search
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats:
            return AppText.tr("Чаты", "Chats")
        case .contacts:
            return AppText.tr("Контакты", "Contacts")
        case .search:
            return AppText.tr("Поиск", "Search")
        case .settings:
            return AppText.tr("Настройки", "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .chats:
            return "bubble.left.and.bubble.right"
        case .contacts:
            return "person.2.fill"
        case .search:
            return "magnifyingglass"
        case .settings:
            return "gearshape"
        }
    }

    var legacyIndex: Int {
        switch self {
        case .chats: return 0
        case .contacts: return 1
        case .search: return 2
        case .settings: return 3
        }
    }

    static func from(legacyIndex: Int) -> MainTab? {
        switch legacyIndex {
        case 0: return .chats
        case 1: return .contacts
        case 2: return .search
        case 3: return .settings
        default: return nil
        }
    }
}

@MainActor
final class MainTabBarStore: ObservableObject {
    static let shared = MainTabBarStore()

    @Published var tabOrder: [MainTab] {
        didSet { persist() }
    }

    @Published var hiddenTabs: Set<MainTab> {
        didSet {
            normalizeSelection()
            persist()
        }
    }

    @Published var selectedTab: MainTab {
        didSet {
            if hiddenTabs.contains(selectedTab) {
                let fallback = visibleTabs.first ?? .chats
                if fallback != selectedTab {
                    selectedTab = fallback
                    return
                }
            }
            persist()
        }
    }

    var visibleTabs: [MainTab] {
        tabOrder.filter { !hiddenTabs.contains($0) }
    }

    private enum Key {
        static let tabOrder = "app.mainTabBar.tabOrder"
        static let hiddenTabs = "app.mainTabBar.hiddenTabs"
        static let selectedTab = "app.mainTabBar.selectedTab"
    }

    private init() {
        let defaults = UserDefaults.standard
        if let rawOrder = defaults.stringArray(forKey: Key.tabOrder) {
            let decoded = rawOrder.compactMap(MainTab.init(rawValue:))
            tabOrder = decoded.isEmpty ? MainTab.allCases : decoded
        } else {
            tabOrder = MainTab.allCases
        }

        if let rawHidden = defaults.stringArray(forKey: Key.hiddenTabs) {
            hiddenTabs = Set(rawHidden.compactMap(MainTab.init(rawValue:)))
        } else {
            hiddenTabs = []
        }

        if let rawSelected = defaults.string(forKey: Key.selectedTab),
           let tab = MainTab(rawValue: rawSelected) {
            selectedTab = tab
        } else {
            selectedTab = .chats
        }

        normalizeSelection()
    }

    func isVisible(_ tab: MainTab) -> Bool {
        !hiddenTabs.contains(tab)
    }

    func setVisible(_ tab: MainTab, visible: Bool) {
        if visible {
            hiddenTabs.remove(tab)
            return
        }
        guard visibleTabs.count > 1 else { return }
        hiddenTabs.insert(tab)
        normalizeSelection()
    }

    func moveTabs(from source: IndexSet, to destination: Int) {
        tabOrder.move(fromOffsets: source, toOffset: destination)
    }

    func selectLegacyIndex(_ index: Int) {
        if let tab = MainTab.from(legacyIndex: index) {
            selectedTab = tab
        }
    }

    func resetToDefault() {
        tabOrder = MainTab.allCases
        hiddenTabs = []
        selectedTab = .chats
    }

    private func normalizeSelection() {
        if hiddenTabs.contains(selectedTab) {
            selectedTab = visibleTabs.first ?? .chats
        }
        if visibleTabs.isEmpty {
            hiddenTabs = []
            selectedTab = .chats
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(tabOrder.map(\.rawValue), forKey: Key.tabOrder)
        defaults.set(Array(hiddenTabs).map(\.rawValue), forKey: Key.hiddenTabs)
        defaults.set(selectedTab.rawValue, forKey: Key.selectedTab)
    }
}
