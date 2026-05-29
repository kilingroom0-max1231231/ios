import SwiftUI

struct ProfileLinkedChannelRow: View {
    let channel: ProfileLinkedChannel
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                AvatarView(
                    title: channel.title,
                    identifier: channel.chatId,
                    imagePath: channel.avatarPath,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let username = channel.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(AppColors.accent)
                    } else {
                        Text(AppText.tr("Личный канал", "Personal channel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
