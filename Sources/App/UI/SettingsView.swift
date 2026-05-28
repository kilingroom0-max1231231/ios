import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(AppColors.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Telegram User Client")
                            .font(.headline)
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
