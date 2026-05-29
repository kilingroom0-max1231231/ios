import SwiftUI

struct ChatProfileView: View {
    @ObservedObject var vm: AppViewModel
    @EnvironmentObject private var appSettings: AppSettingsStore
    let profile: ChatProfile
    @Namespace private var avatarNamespace
    @State private var selectedTab: ProfileTab = .overview
    @State private var selectedMediaCategory: ChatMediaCategory = .photos
    @State private var mediaSelection: MediaViewerSelection?
    @State private var showAvatar = false
    @State private var profilePhotoPaths: [String] = []
    @State private var selectedStoryIndex = 0
    @State private var showStoryViewer = false

    private var hasAvatar: Bool {
        guard let avatarPath = profile.avatarPath else { return false }
        return !avatarPath.isEmpty
    }

    var body: some View {
        ZStack {
            List {
                Section {
                    profileHeader
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 16, trailing: 16))
                }

                Section {
                    Picker("Profile", selection: $selectedTab) {
                        ForEach(availableTabs) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }

                switch selectedTab {
                case .overview:
                    overviewSections
                case .members:
                    if shouldShowMembersTab {
                        membersSection
                    } else {
                        EmptyView()
                    }
                case .stories:
                    userStoriesSection
                case .gifts:
                    userGiftsSection
                case .media:
                    mediaSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ChatListScreenBackground().ignoresSafeArea())

            if showAvatar {
                let paths = profilePhotoPaths.isEmpty
                    ? [profile.avatarPath].compactMap { $0 }
                    : profilePhotoPaths
                if let first = paths.first {
                    FullscreenAvatarOverlay(
                        imagePath: first,
                        imagePaths: paths,
                        title: profile.title,
                        namespace: avatarNamespace,
                        id: "profile-avatar",
                        isPresented: $showAvatar
                    )
                    .zIndex(10)
                }
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: selectedTab)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: showAvatar)
        .fullScreenCover(item: $mediaSelection) { selection in
            MediaViewerView(attachments: selection.attachments, startIndex: selection.startIndex)
        }
        .fullScreenCover(isPresented: $showStoryViewer) {
            if !vm.userProfileStories.isEmpty {
                StoryViewerView(
                    stories: vm.userProfileStories,
                    startIndex: selectedStoryIndex
                )
            }
        }
        .task(id: profile.userId) {
            if let userId = profile.userId {
                await vm.loadUserProfile(userId: userId)
            }
        }
    }

    private var availableTabs: [ProfileTab] {
        var tabs: [ProfileTab] = [.overview]
        if shouldShowMembersTab {
            tabs.append(.members)
        }
        if profile.userId != nil || profile.hasActiveStories || !vm.userProfileStories.isEmpty {
            tabs.append(.stories)
        }
        if profile.userId != nil, profile.giftCount > 0 || !vm.userProfileGifts.isEmpty {
            tabs.append(.gifts)
        }
        tabs.append(.media)
        return tabs
    }

    private var shouldShowMembersTab: Bool {
        // Hide for private chats and Saved Messages, and for places where TDLib doesn't provide members.
        guard profile.kind == .basicGroup || profile.kind == .supergroup else { return false }
        return true
    }

    private struct MediaViewerSelection: Identifiable {
        let id = UUID()
        let attachments: [TgAttachment]
        let startIndex: Int
    }

    private var profileMediaAttachments: [TgAttachment] {
        vm.chatMediaMessages.flatMap(\.attachments)
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            Button {
                if hasAvatar {
                    Task {
                        if let userId = profile.userId {
                            let loaded = await vm.loadProfilePhotoPaths(userId: userId)
                            if !loaded.isEmpty {
                                profilePhotoPaths = loaded
                            } else if let avatarPath = profile.avatarPath {
                                profilePhotoPaths = [avatarPath]
                            }
                        } else if let avatarPath = profile.avatarPath {
                            profilePhotoPaths = [avatarPath]
                        }
                        showAvatar = true
                    }
                }
            } label: {
                AvatarView(
                    title: profile.title,
                    identifier: profile.chatId,
                    imagePath: profile.avatarPath,
                    size: 116
                )
                .matchedGeometryEffect(id: "profile-avatar", in: avatarNamespace)
                .overlay(alignment: .bottomTrailing) {
                    if hasAvatar {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(AppColors.accent)
                            .clipShape(Circle())
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!hasAvatar)

            DisplayNameWithPremium(
                name: profile.title,
                isPremium: profile.isPremium,
                badgeImagePath: profile.premiumBadgePath,
                font: .title2.weight(.bold),
                lineLimit: 2
            )
            .multilineTextAlignment(.center)

            if let username = profile.username, !username.isEmpty {
                UsernameLine(
                    username: username,
                    font: .subheadline,
                    color: AppColors.accent
                )
            }

            if profile.isBlockedByMe || profile.isBlockedByPeer {
                Label(blockBannerText, systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text(profile.statusText?.isEmpty == false ? profile.statusText ?? "" : kindText(profile.kind))
                    .font(.subheadline)
                    .foregroundStyle(statusColor(profile.statusText))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var blockBannerText: String {
        if profile.isBlockedByMe {
            return AppText.tr("Вы заблокировали этого пользователя", "You blocked this user")
        }
        if profile.isBlockedByPeer {
            return AppText.tr("Пользователь ограничил вас", "This user restricted you")
        }
        return ""
    }

    @ViewBuilder
    private var overviewSections: some View {
        if profile.kind == .private, profile.userId != nil {
            Section {
                Button(role: profile.isBlockedByMe ? .none : .destructive) {
                    Task {
                        await vm.setUserBlocked(chatId: profile.chatId, blocked: !profile.isBlockedByMe)
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
            if let username = profile.username, !username.isEmpty {
                profileRow(icon: "at", title: "Username", value: "@\(username)")
            }

            if appSettings.showProfileChatKind {
                profileRow(
                    icon: "person.text.rectangle",
                    title: AppText.tr("Тип", "Type"),
                    value: kindText(profile.kind)
                )
            }

            if let members = profile.membersCount {
                profileRow(icon: "person.2.fill", title: "Участники", value: membersText(members))
            }

            if appSettings.showProfileChatId {
                profileRow(
                    icon: "number",
                    title: AppText.tr("ID чата", "Chat ID"),
                    value: "\(profile.chatId)",
                    monospaced: true
                )
            }
        }

        if let description = profile.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            Section("Описание") {
                Text(description)
                    .textSelection(.enabled)
            }
        }
    }

    private var membersSection: some View {
        Section("Участники") {
            if vm.isProfileDetailsLoading && vm.chatMembers.isEmpty {
                ProgressView()
            } else if vm.chatMembers.isEmpty {
                Text("Участники недоступны")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.chatMembers) { member in
                    if member.isUser {
                        NavigationLink {
                            UserProfileView(vm: vm, userId: member.id)
                        } label: {
                            memberRow(member)
                        }
                        .buttonStyle(.plain)
                    } else {
                        memberRow(member)
                    }
                }
            }
        }
    }

    private func memberRow(_ member: ChatMember) -> some View {
        HStack(spacing: 12) {
            AvatarView(
                title: member.title,
                identifier: member.id,
                imagePath: member.avatarPath,
                size: 38
            )

            VStack(alignment: .leading, spacing: 2) {
                DisplayNameWithPremium(
                    name: member.title,
                    isPremium: member.isPremium,
                    badgeImagePath: member.premiumBadgePath,
                    font: .subheadline.weight(.semibold)
                )
                if let username = member.username, !username.isEmpty {
                    UsernameLine(
                        username: username,
                        font: .caption,
                        color: .secondary
                    )
                } else {
                    Text(member.role ?? member.statusText ?? "member")
                        .font(.caption)
                        .foregroundStyle((member.isOnline ?? false) ? .green : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var userStoriesSection: some View {
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
            Task { await vm.loadActiveStories(chatId: profile.chatId) }
        }
    }

    private var userGiftsSection: some View {
        Section {
            if vm.isUserProfileExtrasLoading && vm.userProfileGifts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if vm.userProfileGifts.isEmpty {
                Text(AppText.tr("Нет подарков", "No gifts"))
                    .foregroundStyle(.secondary)
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
            if let userId = profile.userId {
                Task { await vm.loadUserProfileGifts(userId: userId) }
            }
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        Section {
            Picker("Media", selection: $selectedMediaCategory) {
                ForEach(ChatMediaCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)
        }

        Section(selectedMediaCategory.title) {
            if vm.isProfileDetailsLoading && selectedMediaMessages.isEmpty {
                ProgressView()
            } else if selectedMediaMessages.isEmpty {
                Text("Нет медиа")
                    .foregroundStyle(.secondary)
            } else if selectedMediaCategory == .photos || selectedMediaCategory == .videos {
                ProfileMediaGrid(attachments: selectedMediaAttachments) { attachment in
                    let attachments = profileMediaAttachments
                    if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
                        mediaSelection = MediaViewerSelection(attachments: attachments, startIndex: idx)
                    } else {
                        mediaSelection = MediaViewerSelection(attachments: [attachment], startIndex: 0)
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            } else {
                ForEach(selectedMediaMessages) { message in
                    MediaMessageRow(message: message, category: selectedMediaCategory) { attachment in
                        let attachments = profileMediaAttachments
                        if let idx = attachments.firstIndex(where: { $0.id == attachment.id }) {
                            mediaSelection = MediaViewerSelection(attachments: attachments, startIndex: idx)
                        } else {
                            mediaSelection = MediaViewerSelection(attachments: [attachment], startIndex: 0)
                        }
                    }
                }
            }
        }
    }

    private var selectedMediaMessages: [TgMessage] {
        mediaMessages(for: selectedMediaCategory)
    }

    private var selectedMediaAttachments: [TgAttachment] {
        selectedMediaMessages.flatMap { mediaAttachments(in: $0, for: selectedMediaCategory) }
    }

    private func mediaMessages(for category: ChatMediaCategory) -> [TgMessage] {
        vm.chatMediaMessages.filter { message in
            switch category {
            case .photos:
                return message.attachments.contains { $0.kind == .photo || $0.kind == .sticker }
            case .videos:
                return message.attachments.contains { $0.kind == .video || $0.kind == .videoNote || $0.kind == .animation }
            case .voices:
                return message.attachments.contains { $0.kind == .voice }
            case .files:
                return message.attachments.contains { $0.kind == .document }
            case .links:
                return message.text.containsURL
            }
        }
    }

    private func mediaAttachments(in message: TgMessage, for category: ChatMediaCategory) -> [TgAttachment] {
        message.attachments.filter { attachment in
            switch category {
            case .photos:
                return attachment.kind == .photo || attachment.kind == .sticker
            case .videos:
                return attachment.kind == .video || attachment.kind == .videoNote || attachment.kind == .animation
            case .voices:
                return attachment.kind == .voice
            case .files:
                return attachment.kind == .document
            case .links:
                return false
            }
        }
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
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: String?) -> Color {
        guard let status else { return .secondary }
        return status.localizedCaseInsensitiveContains("онлайн") || status.localizedCaseInsensitiveContains("online")
            ? .green
            : .secondary
    }

    private func membersText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "участник" : "участников")"
    }

    private func kindText(_ kind: ChatKind) -> String {
        switch kind {
        case .savedMessages: return "Saved Messages"
        case .private: return "Пользователь"
        case .basicGroup: return "Группа"
        case .supergroup: return "Супергруппа"
        case .channel: return "Канал"
        case .unknown: return "Неизвестно"
        }
    }
}

private enum ProfileTab: String, CaseIterable, Identifiable {
    case overview
    case members
    case stories
    case gifts
    case media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return AppText.tr("Обзор", "Overview")
        case .members: return AppText.tr("Участники", "Members")
        case .stories: return AppText.tr("Истории", "Stories")
        case .gifts: return AppText.tr("Подарки", "Gifts")
        case .media: return AppText.tr("Медиа", "Media")
        }
    }
}

private struct ProfileMediaGrid: View {
    let attachments: [TgAttachment]
    var onOpen: (TgAttachment) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 92), spacing: 6)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(attachments) { attachment in
                Button {
                    onOpen(attachment)
                } label: {
                    ProfileMediaThumbnail(attachment: attachment)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ProfileMediaThumbnail: View {
    let attachment: TgAttachment

    var body: some View {
        ZStack {
            thumbnailContent

            if attachment.kind == .video || attachment.kind == .videoNote || attachment.kind == .animation {
                Color.black.opacity(0.18)
                Image(systemName: attachment.kind == .animation ? "gift.fill" : "play.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.36))
                    .clipShape(Circle())
            }

            if attachment.localURL == nil {
                ProgressView()
                    .tint(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        switch attachment.kind {
        case .photo:
            if let image = attachment.localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder(systemImage: "photo")
            }
        case .sticker, .gift:
            if let image = attachment.localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                placeholder(systemImage: attachment.kind == .gift ? "gift.fill" : "face.smiling")
            }
        case .video, .videoNote, .animation:
            VideoThumbnailView(url: attachment.localURL)
        default:
            placeholder(systemImage: "doc.fill")
        }
    }

    private func placeholder(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MediaMessageRow: View {
    let message: TgMessage
    let category: ChatMediaCategory
    var onOpen: (TgAttachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let gridItems = visibleAttachments.filter {
                switch $0.kind {
                case .photo, .video, .animation: return true
                default: return false
                }
            }
            let otherItems = visibleAttachments.filter { !gridItems.contains($0) }

            if !gridItems.isEmpty {
                MessageMediaGridView(
                    attachments: gridItems,
                    maxWidth: UIScreen.main.bounds.width - 48,
                    onOpen: onOpen
                )
            }

            ForEach(otherItems) { attachment in
                MessageAttachmentPreview(attachment: attachment) {
                    onOpen(attachment)
                }
            }

            let caption = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if category == .links || !caption.isEmpty {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(category == .links ? AppColors.accent : .secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private var visibleAttachments: [TgAttachment] {
        message.attachments.filter { attachment in
            switch category {
            case .photos:
                return attachment.kind == .photo || attachment.kind == .sticker
            case .videos:
                return attachment.kind == .video || attachment.kind == .videoNote || attachment.kind == .animation
            case .voices:
                return attachment.kind == .voice
            case .files:
                return attachment.kind == .document
            case .links:
                return false
            }
        }
    }
}

private extension String {
    var containsURL: Bool {
        localizedCaseInsensitiveContains("http://")
            || localizedCaseInsensitiveContains("https://")
            || localizedCaseInsensitiveContains("t.me/")
    }
}
