import SwiftUI

struct AppShellView: View {
    @StateObject private var vm = AppViewModel()
    @StateObject private var appearance = AppAppearanceStore.shared
    @StateObject private var language = AppLanguageStore.shared
    @StateObject private var swipeSettings = MessageSwipeSettingsStore.shared
    @StateObject private var appSettings = AppSettingsStore.shared
    @StateObject private var tabBar = MainTabBarStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showTabBarCustomization = false

    var body: some View {
        Group {
            switch vm.phase {
            case .loading:
                LoadingView()
            case .setup:
                NavigationStack {
                    SetupCredentialsView(vm: vm)
                }
            case .login:
                NavigationStack {
                    LoginView(vm: vm)
                }
            case .main:
                ZStack(alignment: .top) {
                    TabView(selection: $tabBar.selectedTab) {
                        ForEach(tabBar.visibleTabs) { tab in
                            tabRoot(for: tab)
                                .tag(tab)
                                .tabItem {
                                    Label(tab.title, systemImage: tab.systemImage)
                                }
                        }
                    }
                    .id("\(language.preferredLanguage)|\(tabBar.layoutFingerprint)")
                    .tint(appearance.accentColor)
                    .preferredColorScheme(appearance.resolvedColorScheme)
                    .animation(.spring(response: 0.3, dampingFraction: 0.88), value: tabBar.selectedTab)
                    .tabBarLongPressLifecycle(
                        refreshToken: "\(language.preferredLanguage)|\(tabBar.layoutFingerprint)|\(tabBar.selectedTab.rawValue)"
                    )

                    if let toast = vm.incomingToast {
                        IncomingMessageToastView(
                            toast: toast,
                            onOpen: {
                                Task { await vm.openIncomingToastChat() }
                            },
                            onDismiss: {
                                vm.dismissIncomingToast()
                            }
                        )
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: vm.incomingToast)
                .sheet(item: $vm.premiumUpsellContext) { context in
                    PremiumUpsellSheet(context: context)
                }
                .sheet(isPresented: $showTabBarCustomization) {
                    TabBarCustomizationView(store: tabBar)
                }
                .onAppear {
                    ChromeAppearance.configureTabBar()
                    ChromeAppearance.configureNavigationBar()
                    TabBarLongPressInstaller.shared.refresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openTabBarCustomization)) { _ in
                    showTabBarCustomization = true
                }
                .onChange(of: showTabBarCustomization) { isPresented in
                    if !isPresented {
                        TabBarLongPressInstaller.shared.refresh()
                    }
                }
                .onChange(of: tabBar.selectedTab) { tab in
                    TabBarLongPressInstaller.shared.refresh()
                    if tab == .chats {
                        Task { await vm.ensureChatFoldersVisible() }
                    }
                }
            }
        }
        .environmentObject(appearance)
        .environmentObject(language)
        .environmentObject(swipeSettings)
        .environmentObject(appSettings)
        .task {
            AppDelegateHolder.viewModel = vm
            await vm.start()
        }
        .onChange(of: scenePhase) { phase in
            vm.handleScenePhase(phase)
            if phase == .active {
                TabBarLongPressInstaller.shared.refresh()
            }
        }
        .onChange(of: appSettings.enablePushNotifications) { enabled in
            if enabled {
                Task { await vm.configurePushAndBackground() }
            }
        }
    }

    @ViewBuilder
    private func tabRoot(for tab: MainTab) -> some View {
        switch tab {
        case .chats:
            ChatListView(vm: vm)
        case .contacts:
            ContactsListView(vm: vm)
        case .search:
            GlobalSearchView(vm: vm)
        case .settings:
            NavigationStack {
                SettingsView(vm: vm)
            }
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(AppText.tr("Запуск TDLib…", "Starting TDLib…"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChatListScreenBackground())
    }
}
