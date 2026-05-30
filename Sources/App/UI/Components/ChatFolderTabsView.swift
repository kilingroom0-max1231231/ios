import SwiftUI

struct ChatFolderTabsView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                folderChip(
                    title: AppText.tr("Все", "All"),
                    emoji: nil,
                    color: AppColors.accent,
                    isSelected: vm.selectedChatFolderId == nil
                ) {
                    Task { await vm.selectChatFolder(nil) }
                }

                ForEach(vm.chatFolders) { folder in
                    folderChip(
                        titleSegments: folder.titleSegments,
                        emoji: folder.iconEmoji,
                        customEmojiPath: folder.iconImagePath,
                        color: folderAccentColor(folder.colorId),
                        isSelected: vm.selectedChatFolderId == folder.id
                    ) {
                        Task { await vm.selectChatFolder(folder.id) }
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            vm.folderSettingsTarget = folder
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func folderChip(
        title: String? = nil,
        titleSegments: [TextSegment]? = nil,
        emoji: String?,
        customEmojiPath: String? = nil,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                FolderIconView(emoji: emoji, customEmojiPath: customEmojiPath, size: 16)
                if let titleSegments, !titleSegments.isEmpty {
                    FolderTitleLabel(segments: titleSegments, font: .subheadline.weight(.semibold))
                } else if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundStyle(isSelected ? Color.white : color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? color : color.opacity(0.14))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func folderAccentColor(_ colorId: Int) -> Color {
        switch colorId {
        case 0: return .blue
        case 1: return .red
        case 2: return .orange
        case 3: return .green
        case 4: return .cyan
        case 5: return .purple
        case 6: return .pink
        default: return AppColors.accent
        }
    }
}

struct ArchiveChatRowView: View {
    let summary: ArchiveChatSummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 52, height: 52)
                Image(systemName: "archivebox.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(AppText.tr("Архив", "Archived"))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    if summary.unreadCount > 0 {
                        Text(unreadText(summary.unreadCount))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppColors.accent)
                            .clipShape(Capsule())
                    }
                }

                if let preview = summary.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(AppText.tr("Чатов: \(summary.count)", "\(summary.count) chats"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func unreadText(_ value: Int) -> String {
        value > 99 ? "99+" : "\(value)"
    }
}
