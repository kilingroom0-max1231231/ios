import SwiftUI

struct UserProfileView: View {
    @ObservedObject var vm: AppViewModel
    @EnvironmentObject private var appSettings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    let userId: Int64

    @State private var selectedTab: Tab = .overview
    @State private var selectedStoryIndex = 0
    @State private var showStoryViewer = false

    private enum Tab: String, CaseIterable, Identifiable {
        case overview
        case stories
        case gifts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return AppText.tr("Обзор", "Overview")
            case .stories: return AppText.tr("Истории", "Stories")
            case .gifts: return AppText.tr("Подарки", "Gifts")
            }
        }
    }

    var body: some View {
        Group {
            if vm.isUserProfileLoading && vm.userProfileDetail == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let profile = vm.userProfileDetail, profile.userId == userId {
                profileContent(profile)
            } else {
                Text(AppText.tr("Не удалось загрузить профиль", "Failed to load profile"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(AppText.tr("Профиль", "Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .handleTelegramLinks(vm, onNavigate: { dismiss() })
        .task(id: userId) {
            await vm.loadUserProfile(userId: userId)
        }
        .fullScreenCover(isPresented: $showStoryViewer) {
            if !vm.userProfileStories.isEmpty {
                StoryViewerView(
                    stories: vm.userProfileStories,
                    startIndex: selectedStoryIndex
                )
            }
        }
    }

    @ViewBuilder
    private func profileContent(_ profile: UserProfileDetail) -> some View {
        List {
            Section {
                header(profile)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 16, trailing: 16))
            }

            Section {
                Picker("ProfileTab", selection: $selectedTab) {
                    ForEach(availableTabs(for: profile)) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch selectedTab {
            case .overview:
                overviewTab(profile)
            case .stories:
                storiesTab
            case .gifts:
                giftsTab(profile)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
    }

    private func availableTabs(for profile: UserProfileDetail) -> [Tab] {
        var tabs: [Tab] = [.overview, .stories]
        if profile.giftCount > 0 || !vm.userProfileGifts.isEmpty {
            tabs.append(.gifts)
        }
        return tabs
    }

    private func header(_ profile: UserProfileDetail) -> some View {
        VStack(spacing: 10) {
            AvatarView(
                title: profile.displayName,
                identifier: profile.userId,
                imagePath: profile.avatarPath,
                size: 116
            )

            DisplayNameWithPremium(
                name: profile.displayName,
                isPremium: profile.isPremium,
                badgeImagePath: profile.premiumBadgePath,
                font: .title2.weight(.bold),
                lineLimit: 2,
                onPremiumBadgeTap: profile.isPremium
                    ? { vm.presentPremiumUpsell(for: profile.displayName, badgePath: profile.premiumBadgePath) }
                    : nil
            )
            .multilineTextAlignment(.center)

            if let username = profile.username, !username.isEmpty {
                UsernameLine(
                    username: username,
                    font: .subheadline,
                    color: AppColors.accent,
                    vm: vm,
                    onNavigate: { dismiss() }
                )
            }

            if let phone = profile.phoneNumber, !phone.isEmpty {
                Text(phone)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if profile.isBlockedByMe || profile.isBlockedByPeer {
                Label(blockText(profile), systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            } else if let status = profile.statusText, !status.isEmpty {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(profile.isOnline ? .green : .secondary)
            }

            if !profile.isSelf {
                Button {
                    Task { await vm.openChat(chatId: profile.privateChatId) }
                } label: {
                    Text(AppText.tr("Написать", "Message"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func overviewTab(_ profile: UserProfileDetail) -> some View {
        if !profile.isSelf {
            Section {
                Button(role: profile.isBlockedByMe ? .none : .destructive) {
                    Task {
                        await vm.setUserBlocked(chatId: profile.privateChatId, blocked: !profile.isBlockedByMe)
                        await vm.loadUserProfile(userId: userId)
                    }
                } label: {
                    Label(
                        profile.isBlockedByMe
                            ? AppText.tr("Разблокировать", "Unblock")
                            : AppText.tr("Заблокировать", "Block"),
                        systemImage: profile.isBlockedByMe ? "hand.raised.slash" : "hand.raised.fill"
                    )
                }
            }
        }

        Section(AppText.tr("Информация", "Info")) {
            if let phone = profile.phoneNumber, !phone.isEmpty {
                profileRow(
                    icon: "phone.fill",
                    title: AppText.tr("Телефон", "Phone"),
                    value: phone
                )
            }

            if let channel = profile.personalChannel {
                ProfileLinkedChannelRow(channel: channel) {
                    Task {
                        await vm.openChat(chatId: channel.chatId)
                        dismiss()
                    }
                }
            }

            if appSettings.showProfileChatKind {
                profileRow(
                    icon: "person.fill",
                    title: AppText.tr("Тип", "Type"),
                    value: AppText.tr("Пользователь", "User")
                )
            }

            if appSettings.showProfileUserId {
                profileRow(
                    icon: "number",
                    title: AppText.tr("ID пользователя", "User ID"),
                    value: "\(profile.userId)",
                    monospaced: true
                )
            }

            if let bio = profile.bio, !bio.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppText.tr("О себе", "Bio"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LinkifiedText(text: bio, linkColor: AppColors.accent)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if profile.giftCount > 0 {
                Label(
                    AppText.tr("Подарков: \(profile.giftCount)", "Gifts: \(profile.giftCount)"),
                    systemImage: "gift.fill"
                )
            }
            if profile.hasActiveStories {
                Label(AppText.tr("Есть активные истории", "Has active stories"), systemImage: "circle.dashed")
            }
        }
    }

    private var storiesTab: some View {
        Section(AppText.tr("Истории", "Stories")) {
            if vm.isUserProfileExtrasLoading && vm.userProfileStories.isEmpty {
                ProgressView()
            } else if vm.userProfileStories.isEmpty {
                Text(AppText.tr("Нет активных историй", "No active stories"))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(vm.userProfileStories.enumerated()), id: \.element.id) { index, story in
                            Button {
                                selectedStoryIndex = index
                                showStoryViewer = true
                            } label: {
                                StoryThumbView(story: story)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
        }
        .onAppear {
            Task { await vm.loadUserProfileStories(userId: userId, force: true) }
        }
    }

    private func giftsTab(_ profile: UserProfileDetail) -> some View {
        Section {
            if vm.isUserProfileExtrasLoading && vm.userProfileGifts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if vm.userProfileGifts.isEmpty {
                if profile.giftCount > 0 {
                    Text(AppText.tr("Подарки скрыты или недоступны в этой версии TDLib", "Gifts are hidden or unavailable in this TDLib build"))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                } else {
                    Text(AppText.tr("Нет подарков", "No gifts"))
                        .foregroundStyle(.secondary)
                }
            } else {
                GiftsGridView(gifts: vm.userProfileGifts)
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .onAppear {
            Task { await vm.loadUserProfileGifts(userId: userId) }
        }
        .onDisappear {
            TGSFileLoader.clearAnimationCache()
        }
    }

    private func blockText(_ profile: UserProfileDetail) -> String {
        if profile.isBlockedByMe {
            return AppText.tr("Вы заблокировали", "You blocked them")
        }
        return AppText.tr("Ограничил(а) вас", "Restricted you")
    }

    private func profileRow(icon: String, title: String, value: String, monospaced: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(monospaced ? .subheadline.monospacedDigit() : .subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
