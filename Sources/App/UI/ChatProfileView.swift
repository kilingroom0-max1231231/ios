import SwiftUI

struct ChatProfileView: View {
    @ObservedObject var vm: AppViewModel
    let profile: ChatProfile
    @Namespace private var avatarNamespace
    @State private var selectedTab: ProfileTab = .overview
    @State private var selectedMediaCategory: ChatMediaCategory = .photos
    @State private var selectedAttachment: TgAttachment?
    @State private var showAvatar = false

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
                        ForEach(ProfileTab.allCases) { tab in
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
                    membersSection
                case .media:
                    mediaSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.screenBackground.ignoresSafeArea())

            if showAvatar, let avatarPath = profile.avatarPath {
                FullscreenAvatarOverlay(
                    imagePath: avatarPath,
                    title: profile.title,
                    namespace: avatarNamespace,
                    id: "profile-avatar",
                    isPresented: $showAvatar
                )
                .zIndex(10)
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: selectedTab)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: showAvatar)
        .fullScreenCover(item: $selectedAttachment) { attachment in
            MediaViewerView(attachment: attachment)
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            Button {
                if hasAvatar {
                    showAvatar = true
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

            Text(profile.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(profile.statusText?.isEmpty == false ? profile.statusText ?? "" : kindText(profile.kind))
                .font(.subheadline)
                .foregroundStyle(statusColor(profile.statusText))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var overviewSections: some View {
        Section("Информация") {
            if let username = profile.username, !username.isEmpty {
                profileRow(icon: "at", title: "Username", value: "@\(username)")
            }

            profileRow(icon: "person.text.rectangle", title: "Тип", value: kindText(profile.kind))

            if let members = profile.membersCount {
                profileRow(icon: "person.2.fill", title: "Участники", value: membersText(members))
            }

            profileRow(icon: "number", title: "Chat ID", value: "\(profile.chatId)", monospaced: true)
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
                Text(profile.kind == .private ? "Личный чат" : "Участники недоступны")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.chatMembers) { member in
                    HStack(spacing: 12) {
                        AvatarView(
                            title: member.title,
                            identifier: member.id,
                            imagePath: member.avatarPath,
                            size: 38
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.title)
                                .font(.subheadline.weight(.semibold))
                            Text(member.role ?? member.statusText ?? "member")
                                .font(.caption)
                                .foregroundStyle((member.isOnline ?? false) ? .green : .secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
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
                    selectedAttachment = attachment
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            } else {
                ForEach(selectedMediaMessages) { message in
                    MediaMessageRow(message: message, category: selectedMediaCategory) { attachment in
                        selectedAttachment = attachment
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
    case media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Info"
        case .members: return "Members"
        case .media: return "Media"
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
        case .sticker:
            if let image = attachment.localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                placeholder(systemImage: "face.smiling")
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
            ForEach(visibleAttachments) { attachment in
                MessageAttachmentPreview(attachment: attachment) {
                    onOpen(attachment)
                }
            }

            if category == .links || !message.text.isEmpty {
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
