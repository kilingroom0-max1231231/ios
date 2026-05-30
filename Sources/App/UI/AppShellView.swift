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
                    VStack(spacing: 0) {
                        ZStack {
                            tabContent(isActive: tabBar.selectedTab == .chats) {
                                ChatListView(vm: vm)
                            }

                            tabContent(isActive: tabBar.selectedTab == .contacts) {
                                ContactsListView(vm: vm)
                            }

                            tabContent(isActive: tabBar.selectedTab == .search) {
                                GlobalSearchView(vm: vm)
                            }

                            tabContent(isActive: tabBar.selectedTab == .settings) {
                                NavigationStack {
                                    SettingsView(vm: vm)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("\(language.preferredLanguage)|\(appearance.paletteFingerprint)")

                        CustomMainTabBar(
                            store: tabBar,
                            accent: appearance.accentColor,
                            onCustomize: { showTabBarCustomization = true }
                        )
                    }
                    .tint(appearance.accentColor)
                    .animation(.spring(response: 0.3, dampingFraction: 0.88), value: tabBar.selectedTab)

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
                    ChromeAppearance.configureNavigationBar()
                }
                .onChange(of: tabBar.selectedTab) { tab in
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
        }
        .onChange(of: appSettings.enablePushNotifications) { enabled in
            if enabled {
                Task { await vm.configurePushAndBackground() }
            }
        }
    }

    @ViewBuilder
    private func tabContent<Content: View>(isActive: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
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
