import SwiftUI

struct AppShellView: View {
    @StateObject private var vm = AppViewModel()
    @StateObject private var appearance = AppAppearanceStore.shared
    @StateObject private var language = AppLanguageStore.shared
    @StateObject private var swipeSettings = MessageSwipeSettingsStore.shared
    @StateObject private var appSettings = AppSettingsStore.shared
    @Environment(\.scenePhase) private var scenePhase

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
                    TabView(selection: $vm.mainTabIndex) {
                        ChatListView(vm: vm)
                            .tag(0)
                            .tabItem {
                                Label(AppText.tr("Чаты", "Chats"), systemImage: "bubble.left.and.bubble.right")
                            }

                        ContactsListView(vm: vm)
                            .tag(1)
                            .tabItem {
                                Label(AppText.tr("Контакты", "Contacts"), systemImage: "person.2.fill")
                            }

                        GlobalSearchView(vm: vm)
                            .tag(2)
                            .tabItem {
                                Label(AppText.tr("Поиск", "Search"), systemImage: "magnifyingglass")
                            }

                        NavigationStack {
                            SettingsView(vm: vm)
                        }
                        .tag(3)
                        .tabItem {
                            Label(AppText.tr("Настройки", "Settings"), systemImage: "gearshape")
                        }
                    }
                    .id("\(language.preferredLanguage)|\(appearance.paletteFingerprint)")
                    .tint(appearance.accentColor)
                    .animation(.spring(response: 0.3, dampingFraction: 0.88), value: vm.mainTabIndex)

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
                .onAppear {
                    ChromeAppearance.configureTabBar()
                    ChromeAppearance.configureNavigationBar()
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
