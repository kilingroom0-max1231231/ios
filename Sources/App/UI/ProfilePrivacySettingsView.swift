import SwiftUI

struct ProfilePrivacySettingsView: View {
    @ObservedObject var vm: AppViewModel
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isSaving = false

    var body: some View {
        List {
            Section(AppText.tr("Профиль", "Profile")) {
                HStack(spacing: 12) {
                    if let me = vm.me {
                        AvatarView(
                            title: me.displayName,
                            identifier: me.id,
                            imagePath: me.avatarPath,
                            size: 56
                        )
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.me?.displayName ?? "—")
                            .font(.headline)
                        if let username = vm.me?.username, !username.isEmpty {
                            Text("@\(username)")
                                .foregroundStyle(.secondary)
                        }
                        if let phone = vm.me?.phoneNumber, !phone.isEmpty {
                            Text(phone)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section(AppText.tr("Имя и фамилия", "Name")) {
                TextField(AppText.tr("Имя", "First name"), text: $firstName)
                TextField(AppText.tr("Фамилия", "Last name"), text: $lastName)
                Button {
                    Task { await saveName() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(AppText.tr("Сохранить", "Save"))
                    }
                }
                .disabled(isSaving || firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section(AppText.tr("Приватность", "Privacy")) {
                privacyRow(
                    title: AppText.tr("Номер телефона", "Phone number"),
                    detail: AppText.tr("Управляется в официальном Telegram", "Managed in official Telegram")
                )
                privacyRow(
                    title: AppText.tr("Аватар", "Profile photo"),
                    detail: AppText.tr("Отображается в чатах", "Shown in chats")
                )
                privacyRow(
                    title: AppText.tr("Юзернейм", "Username"),
                    detail: vm.me?.username.map { "@\($0)" } ?? AppText.tr("Не задан", "Not set")
                )
                privacyRow(
                    title: AppText.tr("Статус «в сети»", "Last seen"),
                    detail: AppText.tr("Синхронизируется с аккаунтом", "Synced with your account")
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AppText.tr("Профиль и приватность", "Profile & privacy"))
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .frostedNavigationBar()
        .task {
            await vm.refreshMe()
            firstName = vm.me?.firstName ?? ""
            lastName = vm.me?.lastName ?? ""
        }
    }

    private func privacyRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func saveName() async {
        isSaving = true
        defer { isSaving = false }
        await vm.updateProfileName(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
