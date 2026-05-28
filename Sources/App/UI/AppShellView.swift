import SwiftUI

struct AppShellView: View {
    @StateObject private var vm = AppViewModel()

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
                TabView {
                    NavigationStack {
                        ChatListView(vm: vm)
                    }
                    .tabItem {
                        Label("Chats", systemImage: "bubble.left.and.bubble.right")
                    }

                    NavigationStack {
                        SettingsView(vm: vm)
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                .tint(AppColors.accent)
            }
        }
        .task {
            await vm.start()
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Запуск TDLib…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.screenBackground)
    }
}
