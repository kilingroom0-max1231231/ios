import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    if let me = vm.me {
                        AvatarView(
                            title: me.displayName,
                            identifier: me.id,
                            imagePath: me.avatarPath,
                            size: 52
                        )
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(AppColors.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(vm.me?.displayName ?? "Telegram User Client")
                            .font(.headline)

                        if let username = vm.me?.username, !username.isEmpty {
                            Text("@\(username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(statusText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Application") {
                settingsRow(icon: "sparkles", title: "Interface", value: "Native Apple")
                settingsRow(icon: "lock.shield", title: "Storage", value: "Local TDLib database")
                settingsRow(icon: "photo.on.rectangle", title: "Media", value: "Inline previews")
            }

            Section {
                Button(role: .destructive) {
                    vm.signOut()
                } label: {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .background(AppColors.screenBackground.ignoresSafeArea())
        .task {
            await vm.refreshMe()
        }
    }

    private var statusText: String {
        switch vm.authState {
        case .ready: return "Connected"
        case .waitPhone, .waitCode, .waitPassword: return "Authorization required"
        }
    }

    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
