import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject var vm: AppViewModel
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var isSavingProfile = false

    var body: some View {
        List {
            Section(AppText.tr("Профиль", "Profile")) {
                TextField(AppText.tr("Имя", "First name"), text: $firstName)
                TextField(AppText.tr("Фамилия", "Last name"), text: $lastName)
                TextField(AppText.tr("Имя пользователя", "Username"), text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await saveProfile() }
                } label: {
                    if isSavingProfile {
                        ProgressView()
                    } else {
                        Text(AppText.tr("Сохранить профиль", "Save profile"))
                    }
                }
                .disabled(isSavingProfile)
            }

            Section {
                if vm.isPrivacyLoading && vm.privacySettings.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    ForEach(vm.privacySettings) { item in
                        Picker(item.kind.title, selection: binding(for: item.kind)) {
                            ForEach(PrivacyVisibility.allCases) { level in
                                Text(level.title).tag(level)
                            }
                        }
                    }
                }
            } header: {
                Text(AppText.tr("Приватность", "Privacy"))
            } footer: {
                Text(AppText.tr(
                    "Кто видит аватар, имя, @username, номер и другие данные профиля.",
                    "Who can see your avatar, name, @username, phone number, and other profile details."
                ))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AppText.tr("Приватность", "Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .task {
            await vm.loadPrivacySettings()
            syncProfileFields()
        }
        .onChange(of: vm.me?.id) { _ in
            syncProfileFields()
        }
    }

    private func binding(for kind: UserPrivacySettingKind) -> Binding<PrivacyVisibility> {
        Binding(
            get: {
                vm.privacySettings.first(where: { $0.kind == kind })?.visibility ?? .contacts
            },
            set: { newValue in
                Task { await vm.updatePrivacySetting(kind, visibility: newValue) }
            }
        )
    }

    private func syncProfileFields() {
        guard let me = vm.me else { return }
        firstName = me.firstName
        lastName = me.lastName
        username = me.username ?? ""
    }

    private func saveProfile() async {
        isSavingProfile = true
        defer { isSavingProfile = false }
        await vm.updateMyProfile(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
