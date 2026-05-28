import PhotosUI
import SwiftUI
import UIKit

struct PrivacySettingsView: View {
    @ObservedObject var vm: AppViewModel
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var isSavingProfile = false
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false

    var body: some View {
        List {
            Section(AppText.tr("Аватар", "Avatar")) {
                HStack(spacing: 14) {
                    if let me = vm.me {
                        AvatarView(
                            title: me.displayName,
                            identifier: me.id,
                            imagePath: me.avatarPath,
                            size: 64
                        )
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(AppColors.accent)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $avatarPickerItem, matching: .images, photoLibrary: .shared()) {
                            Label(
                                AppText.tr("Изменить фото", "Change photo"),
                                systemImage: "photo.on.rectangle.angled"
                            )
                        }
                        .disabled(isUploadingAvatar)

                        if isUploadingAvatar {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

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
                ForEach(vm.privacySettings) { item in
                    Picker(item.kind.title, selection: binding(for: item.kind)) {
                        ForEach(PrivacyVisibility.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                }
            } header: {
                Text(AppText.tr("Приватность", "Privacy"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppText.tr(
                        "Кто видит аватар, имя, @username, номер и другие данные профиля.",
                        "Who can see your avatar, name, @username, phone number, and other profile details."
                    ))
                    if vm.isPrivacyLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(AppText.tr("Загрузка настроек…", "Loading settings…"))
                        }
                    }
                    if !vm.status.isEmpty {
                        Text(vm.status)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(AppText.tr("Приватность", "Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .frostedNavigationBar()
        .task {
            syncProfileFields()
            await vm.loadPrivacySettings()
        }
        .onChange(of: vm.me?.id) { _ in
            syncProfileFields()
        }
        .onChange(of: avatarPickerItem) { newItem in
            guard let newItem else { return }
            Task {
                isUploadingAvatar = true
                defer {
                    isUploadingAvatar = false
                    avatarPickerItem = nil
                }
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await vm.uploadMyProfilePhoto(from: image)
                }
            }
        }
    }

    private func binding(for kind: UserPrivacySettingKind) -> Binding<PrivacyVisibility> {
        Binding(
            get: {
                vm.privacySettings.first(where: { $0.kind == kind })?.visibility ?? .contacts
            },
            set: { newValue in
                if let index = vm.privacySettings.firstIndex(where: { $0.kind == kind }) {
                    vm.privacySettings[index].visibility = newValue
                }
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
