import SwiftUI

/// Telegram-style hub: account, security, and privacy drill-down screens.
struct PrivacySettingsView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        List {
            profileHeaderSection

            Section(AppText.tr("Аккаунт", "Account")) {
                accountRow(
                    title: AppText.tr("Имя", "Name"),
                    value: vm.me?.displayName ?? "—",
                    destination: EditProfileNameView(vm: vm)
                )
                accountRow(
                    title: AppText.tr("О себе", "Bio"),
                    value: bioSummary,
                    placeholder: vm.me?.bio?.isEmpty != false,
                    destination: EditProfileBioView(vm: vm)
                )
                if let phone = vm.me?.phoneNumber, !phone.isEmpty {
                    ProfileSettingsValueRow(
                        title: AppText.tr("Номер телефона", "Phone number"),
                        value: phone
                    )
                }
                accountRow(
                    title: AppText.tr("Имя пользователя", "Username"),
                    value: usernameSummary,
                    placeholder: vm.me?.username?.isEmpty != false,
                    destination: EditProfileUsernameView(vm: vm)
                )
            }

            Section {
                securityInfoRow(
                    icon: "lock.shield",
                    title: AppText.tr("Облачный пароль", "Cloud password"),
                    value: onOffText(vm.securitySnapshot.hasCloudPassword)
                )

                NavigationLink {
                    EditMessageAutoDeleteView(vm: vm)
                } label: {
                    securityNavigationRow(
                        icon: "clock.arrow.circlepath",
                        title: AppText.tr("Автоудаление сообщений", "Auto-delete messages"),
                        value: autoDeleteSummary
                    )
                }
                securityInfoRow(
                    icon: "lock",
                    title: AppText.tr("Код-пароль", "Passcode"),
                    value: AppText.tr("Выкл.", "Off")
                )
                securityInfoRow(
                    icon: "envelope",
                    title: AppText.tr("Почта для входа", "Login email"),
                    value: loginEmailSummary
                )

                NavigationLink {
                    BlockedUsersView(vm: vm)
                } label: {
                    securityNavigationRow(
                        icon: "hand.raised",
                        title: AppText.tr("Заблокированные пользователи", "Blocked users"),
                        value: blockedUsersSummary
                    )
                }

                NavigationLink {
                    ActiveSessionsView(vm: vm)
                } label: {
                    securityNavigationRow(
                        icon: "laptopcomputer.and.iphone",
                        title: AppText.tr("Активные сеансы", "Active sessions"),
                        value: activeSessionsSummary
                    )
                }
            } header: {
                Text(AppText.tr("Безопасность", "Security"))
            } footer: {
                Text(AppText.tr(
                    "Управление сеансами на всех подключённых устройствах.",
                    "Manage sessions on all connected devices."
                ))
            }

            Section {
                ForEach(UserPrivacySettingKind.primaryPrivacySection) { kind in
                    privacyNavigationLink(kind: kind)
                }
            } header: {
                Text(AppText.tr("Конфиденциальность", "Privacy"))
            } footer: {
                privacyFooter
            }

            Section {
                ForEach(UserPrivacySettingKind.extendedPrivacySection) { kind in
                    privacyNavigationLink(kind: kind)
                }
            }

            Section {
                ForEach(UserPrivacySettingKind.discoverySection) { kind in
                    privacyNavigationLink(kind: kind)
                }
            } header: {
                Text(AppText.tr("Поиск", "Discovery"))
            }

            Section {
                NavigationLink {
                    EditAccountDeletionView(vm: vm)
                } label: {
                    securityNavigationRow(
                        icon: "trash",
                        title: AppText.tr("При неактивности…", "If inactive for…"),
                        value: accountDeletionSummary
                    )
                }
            } header: {
                Text(AppText.tr("Удаление аккаунта", "Account deletion"))
            } footer: {
                Text(AppText.tr(
                    "Если вы не заходите в Telegram, аккаунт будет удалён через указанный срок.",
                    "If you don't log in to Telegram, your account will be deleted after this period."
                ))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Конфиденциальность", "Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
        .task {
            await vm.refreshMe()
            async let privacy: Void = vm.loadPrivacySettings()
            async let security: Void = vm.refreshSecuritySnapshot()
            _ = await (privacy, security)
        }
    }

    // MARK: - Sections

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
                            reloadToken: vm.avatarReloadToken,
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

    private func privacyNavigationLink(kind: UserPrivacySettingKind) -> some View {
        NavigationLink {
            PrivacySettingPickerView(vm: vm, kind: kind)
        } label: {
            ProfileSettingsValueRow(
                title: kind.title,
                value: vm.privacySummary(for: kind)
            )
        }
    }

    private func accountRow<D: View>(
        title: String,
        value: String,
        placeholder: Bool = false,
        destination: D
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            ProfileSettingsValueRow(title: title, value: value, placeholder: placeholder)
        }
    }

    // MARK: - Security rows

    private func securityInfoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func securityNavigationRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Summaries

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

    private var blockedUsersSummary: String {
        let count = vm.securitySnapshot.blockedUsersCount
        if count == 0 {
            return AppText.tr("Нет", "None")
        }
        return "\(count)"
    }

    private var activeSessionsSummary: String {
        let count = vm.activeSessions.count
        return count > 0 ? "\(count)" : "—"
    }

    private var loginEmailSummary: String {
        if let pattern = vm.securitySnapshot.loginEmailPattern, !pattern.isEmpty {
            return pattern
        }
        return AppText.tr("Не задана", "Not set")
    }

    private var autoDeleteSummary: String {
        let seconds = vm.securitySnapshot.messageAutoDeleteSeconds
        guard seconds > 0 else {
            return AppText.tr("Выкл.", "Off")
        }
        return formatDuration(seconds: seconds)
    }

    private var accountDeletionSummary: String {
        let days = vm.securitySnapshot.accountDeleteDays
        guard days > 0 else {
            return AppText.tr("Выкл.", "Off")
        }
        if days >= 365 {
            let years = days / 365
            return AppText.tr("\(years) \(yearsLabel(years))", "\(years) \(years == 1 ? "year" : "years")")
        }
        if days >= 30 {
            let months = max(1, days / 30)
            return AppText.tr("\(months) \(monthsLabel(months))", "\(months) \(months == 1 ? "month" : "months")")
        }
        return AppText.tr("\(days) \(daysLabel(days))", "\(days) \(days == 1 ? "day" : "days")")
    }

    private func onOffText(_ isOn: Bool) -> String {
        isOn ? AppText.tr("Вкл.", "On") : AppText.tr("Выкл.", "Off")
    }

    private func formatDuration(seconds: Int) -> String {
        if seconds < 3600 {
            let minutes = max(1, seconds / 60)
            return AppText.tr("\(minutes) мин.", "\(minutes) min")
        }
        if seconds < 86_400 {
            let hours = max(1, seconds / 3600)
            return AppText.tr("\(hours) ч.", "\(hours) h")
        }
        let days = max(1, seconds / 86_400)
        return AppText.tr("\(days) \(daysLabel(days))", "\(days) \(days == 1 ? "day" : "days")")
    }

    private func monthsLabel(_ count: Int) -> String {
        switch AppLanguageStore.shared.preferredLanguage {
        case .russian:
            let mod10 = count % 10
            let mod100 = count % 100
            if mod100 >= 11 && mod100 <= 14 { return "месяцев" }
            if mod10 == 1 { return "месяц" }
            if mod10 >= 2 && mod10 <= 4 { return "месяца" }
            return "месяцев"
        case .english:
            return count == 1 ? "month" : "months"
        }
    }

    private func daysLabel(_ count: Int) -> String {
        switch AppLanguageStore.shared.preferredLanguage {
        case .russian:
            let mod10 = count % 10
            let mod100 = count % 100
            if mod100 >= 11 && mod100 <= 14 { return "дней" }
            if mod10 == 1 { return "день" }
            if mod10 >= 2 && mod10 <= 4 { return "дня" }
            return "дней"
        case .english:
            return count == 1 ? "day" : "days"
        }
    }

    private func yearsLabel(_ count: Int) -> String {
        switch AppLanguageStore.shared.preferredLanguage {
        case .russian:
            let mod10 = count % 10
            let mod100 = count % 100
            if mod100 >= 11 && mod100 <= 14 { return "лет" }
            if mod10 == 1 { return "год" }
            if mod10 >= 2 && mod10 <= 4 { return "года" }
            return "лет"
        case .english:
            return count == 1 ? "year" : "years"
        }
    }

    @ViewBuilder
    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppText.tr(
                "Настройте, кто может видеть ваши данные и связываться с вами.",
                "Control who can see your information and contact you."
            ))
            if vm.isPrivacyLoading || vm.isSecurityLoading {
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
