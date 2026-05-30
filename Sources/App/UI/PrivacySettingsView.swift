import SwiftUI

/// Telegram-style hub: account fields + privacy drill-down screens.
struct PrivacySettingsView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        List {
            profileHeaderSection

            Section(AppText.tr("Аккаунт", "Account")) {
                NavigationLink {
                    EditProfileNameView(vm: vm)
                } label: {
                    ProfileSettingsValueRow(
                        title: AppText.tr("Имя", "Name"),
                        value: vm.me?.displayName ?? "—"
                    )
                }

                NavigationLink {
                    EditProfileBioView(vm: vm)
                } label: {
                    ProfileSettingsValueRow(
                        title: AppText.tr("О себе", "Bio"),
                        value: bioSummary,
                        placeholder: vm.me?.bio?.isEmpty != false
                    )
                }

                if let phone = vm.me?.phoneNumber, !phone.isEmpty {
                    ProfileSettingsValueRow(
                        title: AppText.tr("Номер телефона", "Phone number"),
                        value: phone
                    )
                }

                NavigationLink {
                    EditProfileUsernameView(vm: vm)
                } label: {
                    ProfileSettingsValueRow(
                        title: AppText.tr("Имя пользователя", "Username"),
                        value: usernameSummary,
                        placeholder: vm.me?.username?.isEmpty != false
                    )
                }
            }

            Section {
                ForEach(UserPrivacySettingKind.privacySection) { kind in
                    NavigationLink {
                        PrivacySettingPickerView(vm: vm, kind: kind)
                    } label: {
                        ProfileSettingsValueRow(
                            title: kind.title,
                            value: vm.privacyVisibility(for: kind).title
                        )
                    }
                }
            } header: {
                Text(AppText.tr("Приватность", "Privacy"))
            } footer: {
                privacyFooter
            }

            Section {
                ForEach(UserPrivacySettingKind.discoverySection) { kind in
                    NavigationLink {
                        PrivacySettingPickerView(vm: vm, kind: kind)
                    } label: {
                        ProfileSettingsValueRow(
                            title: kind.title,
                            value: vm.privacyVisibility(for: kind).title
                        )
                    }
                }
            } header: {
                Text(AppText.tr("Поиск", "Discovery"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Профиль и приватность", "Profile & privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
        .task {
            await vm.refreshMe()
            await vm.loadPrivacySettings()
        }
    }

    private var profileHeaderSection: some View {
        Section {
            NavigationLink {
                EditProfilePhotoView(vm: vm)
            } label: {
                HStack(spacing: 16) {
                    if let me = vm.me {
                        AvatarView(
                            title: me.displayName,
                            identifier: me.id,
                            imagePath: me.avatarPath,
                            size: 72
                        )
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(AppColors.accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppText.tr("Изменить фото профиля", "Change profile photo"))
                            .font(.body)
                            .foregroundStyle(AppColors.accent)
                        if let me = vm.me {
                            Text(me.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var bioSummary: String {
        guard let bio = vm.me?.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty else {
            return AppText.tr("Добавить", "Add")
        }
        return bio
    }

    private var usernameSummary: String {
        guard let username = vm.me?.username, !username.isEmpty else {
            return AppText.tr("Задать", "Set")
        }
        return "@\(username)"
    }

    @ViewBuilder
    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppText.tr(
                "Настройте, кто может видеть ваши данные и связываться с вами.",
                "Control who can see your information and contact you."
            ))
            if vm.isPrivacyLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(AppText.tr("Загрузка…", "Loading…"))
                }
            }
            if !vm.status.isEmpty {
                Text(vm.status)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
