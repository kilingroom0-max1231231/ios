import PhotosUI
import SwiftUI
import UIKit

// MARK: - Hub row helpers

struct ProfileSettingsValueRow: View {
    let title: String
    let value: String
    var placeholder = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(placeholder ? .secondary : .secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

// MARK: - Edit name

struct EditProfileNameView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isSaving = false

    var body: some View {
        List {
            Section {
                TextField(AppText.tr("Имя", "First name"), text: $firstName)
                TextField(AppText.tr("Фамилия", "Last name"), text: $lastName)
            } footer: {
                Text(AppText.tr(
                    "Введите имя и фамилию, которые будут видеть другие пользователи.",
                    "Enter the name other users will see."
                ))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Имя", "Name"))
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppText.tr("Готово", "Done")) {
                    Task { await save() }
                }
                .disabled(isSaving || firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            firstName = vm.me?.firstName ?? ""
            lastName = vm.me?.lastName ?? ""
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        await vm.updateProfileName(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if vm.status.isEmpty {
            dismiss()
        }
    }
}

// MARK: - Edit bio

struct EditProfileBioView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var bio = ""
    @State private var isSaving = false

    private let maxLength = 70

    var body: some View {
        List {
            Section {
                TextField(
                    AppText.tr("О себе", "Bio"),
                    text: $bio,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .onChange(of: bio) { newValue in
                    if newValue.count > maxLength {
                        bio = String(newValue.prefix(maxLength))
                    }
                }
            } footer: {
                Text(AppText.tr(
                    "Любые подробности, например: возраст, род занятий или город.",
                    "Any details, such as age, occupation or city."
                ))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("О себе", "Bio"))
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppText.tr("Готово", "Done")) {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("\(bio.count)/\(maxLength)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
        }
        .onAppear {
            bio = vm.me?.bio ?? ""
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        await vm.updateMyBio(bio.trimmingCharacters(in: .whitespacesAndNewlines))
        if vm.status.isEmpty {
            dismiss()
        }
    }
}

// MARK: - Edit username

struct EditProfileUsernameView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var isSaving = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 4) {
                    Text("@")
                        .foregroundStyle(.secondary)
                    TextField(AppText.tr("username", "username"), text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } footer: {
                Text(AppText.tr(
                    "Вы можете выбрать имя пользователя в Telegram. Другие смогут найти вас по @username без номера телефона.",
                    "You can choose a username on Telegram. People can find you by @username without knowing your phone number."
                ))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Имя пользователя", "Username"))
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppText.tr("Готово", "Done")) {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            username = vm.me?.username ?? ""
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        await vm.updateMyUsername(username)
        if vm.status.isEmpty {
            dismiss()
        }
    }
}

// MARK: - Privacy picker (Telegram-style)

struct PrivacySettingPickerView: View {
    @ObservedObject var vm: AppViewModel
    let kind: UserPrivacySettingKind
    @State private var isUpdating = false

    private var rules: UserPrivacyRules {
        vm.privacyRules(for: kind)
    }

    var body: some View {
        List {
            Section {
                ForEach(kind.availableBaseOptions) { level in
                    Button {
                        guard rules.baseVisibility != level else { return }
                        isUpdating = true
                        Task {
                            await vm.updatePrivacySetting(kind, visibility: level)
                            isUpdating = false
                        }
                    } label: {
                        HStack {
                            Text(level.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if rules.baseVisibility == level {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                    .disabled(isUpdating)
                }
            } footer: {
                if let footer = kind.footer {
                    Text(footer)
                }
            }

            if rules.showsAlwaysAllowSection {
                Section {
                    NavigationLink {
                        PrivacyExceptionUsersView(vm: vm, kind: kind, allow: true)
                    } label: {
                        exceptionSummaryRow(
                            title: AppText.tr("Всегда разрешить", "Always allow"),
                            count: rules.allowUserIds.count
                        )
                    }
                } header: {
                    Text(AppText.tr("Исключения", "Exceptions"))
                } footer: {
                    Text(AppText.tr(
                        "Эти пользователи всегда смогут видеть данные, даже если основная настройка этого не позволяет.",
                        "These users will always be allowed, even if the main setting would restrict them."
                    ))
                }
            }

            if rules.showsNeverAllowSection {
                Section {
                    NavigationLink {
                        PrivacyExceptionUsersView(vm: vm, kind: kind, allow: false)
                    } label: {
                        exceptionSummaryRow(
                            title: AppText.tr("Никогда не разрешать", "Never allow"),
                            count: rules.restrictUserIds.count
                        )
                    }
                } footer: {
                    if !rules.showsAlwaysAllowSection {
                        Text(AppText.tr(
                            "Эти пользователи никогда не смогут видеть данные, даже если основная настройка это разрешает.",
                            "These users will never be allowed, even if the main setting would permit them."
                        ))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
        .task {
            await vm.refreshContactsIfNeeded()
            await vm.resolvePrivacyUserLabels(for: rules)
        }
        .overlay {
            if isUpdating || vm.isPrivacyLoading {
                ProgressView()
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func exceptionSummaryRow(title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Exception user list

struct PrivacyExceptionUsersView: View {
    @ObservedObject var vm: AppViewModel
    let kind: UserPrivacySettingKind
    let allow: Bool
    @State private var showPicker = false
    @State private var isUpdating = false

    private var userIds: [Int64] {
        let rules = vm.privacyRules(for: kind)
        return allow ? rules.allowUserIds : rules.restrictUserIds
    }

    private var title: String {
        allow
            ? AppText.tr("Всегда разрешить", "Always allow")
            : AppText.tr("Никогда не разрешать", "Never allow")
    }

    var body: some View {
        List {
            Section {
                Button {
                    showPicker = true
                } label: {
                    Label(AppText.tr("Добавить пользователя", "Add user"), systemImage: "plus.circle.fill")
                        .foregroundStyle(AppColors.accent)
                }
                .disabled(isUpdating)
            }

            if userIds.isEmpty {
                Section {
                    Text(AppText.tr("Нет пользователей", "No users"))
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(userIds, id: \.self) { userId in
                        HStack(spacing: 12) {
                            AvatarView(
                                title: vm.privacyUserDisplayName(userId),
                                identifier: userId,
                                imagePath: vm.contacts.first(where: { $0.userId == userId })?.avatarPath,
                                size: 40
                            )
                            Text(vm.privacyUserDisplayName(userId))
                            Spacer()
                            Button(role: .destructive) {
                                isUpdating = true
                                Task {
                                    await vm.removePrivacyException(kind: kind, userId: userId, allow: allow)
                                    isUpdating = false
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .disabled(isUpdating)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
        .sheet(isPresented: $showPicker) {
            PrivacyUserPickerSheet(vm: vm, kind: kind, allow: allow) {
                showPicker = false
            }
        }
        .task {
            await vm.refreshContactsIfNeeded()
            await vm.resolvePrivacyUserLabels(for: vm.privacyRules(for: kind))
        }
    }
}

// MARK: - Pick contact for exception

struct PrivacyUserPickerSheet: View {
    @ObservedObject var vm: AppViewModel
    let kind: UserPrivacySettingKind
    let allow: Bool
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isSaving = false

    private var rules: UserPrivacyRules {
        vm.privacyRules(for: kind)
    }

    private var filteredContacts: [TgContact] {
        let excluded = Set(rules.allowUserIds + rules.restrictUserIds)
        let base = vm.contacts.filter { contact in
            contact.userId != vm.me?.id && !excluded.contains(contact.userId)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || ($0.username?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if vm.contacts.isEmpty && vm.isContactsLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if filteredContacts.isEmpty {
                    Text(AppText.tr("Контакты не найдены", "No contacts found"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredContacts) { contact in
                        Button {
                            Task { await add(contact.userId) }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(
                                    title: contact.displayName,
                                    identifier: contact.userId,
                                    imagePath: contact.avatarPath,
                                    size: 40
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.displayName)
                                        .foregroundStyle(.primary)
                                    if let username = contact.username, !username.isEmpty {
                                        Text("@\(username)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ChatListScreenBackground().ignoresSafeArea())
            .navigationTitle(AppText.tr("Добавить", "Add"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: AppText.tr("Поиск", "Search")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.tr("Отмена", "Cancel")) {
                        dismiss()
                        onDone()
                    }
                }
            }
            .task {
                await vm.refreshContactsIfNeeded()
            }
        }
    }

    private func add(_ userId: Int64) async {
        isSaving = true
        defer { isSaving = false }
        await vm.addPrivacyException(kind: kind, userId: userId, allow: allow)
        dismiss()
        onDone()
    }
}

// MARK: - Change photo

struct EditProfilePhotoView: View {
    @ObservedObject var vm: AppViewModel
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var isUploading = false

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 14) {
                        if let me = vm.me {
                            AvatarView(
                                title: me.displayName,
                                identifier: me.id,
                                imagePath: me.avatarPath,
                                size: 120
                            )
                        }

                        PhotosPicker(selection: $avatarPickerItem, matching: .images, photoLibrary: .shared()) {
                            Text(AppText.tr("Выбрать фото", "Choose photo"))
                                .font(.body.weight(.semibold))
                        }
                        .disabled(isUploading)

                        if isUploading {
                            ProgressView()
                        }
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Фото профиля", "Profile photo"))
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
        .onChange(of: avatarPickerItem) { newItem in
            guard let newItem else { return }
            Task {
                isUploading = true
                defer {
                    isUploading = false
                    avatarPickerItem = nil
                }
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await vm.uploadMyProfilePhoto(from: image)
                }
            }
        }
    }
}
