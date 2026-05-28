import SwiftUI

struct IncomingMessageBannerView: View {
    let banner: IncomingMessageBanner
    var onOpen: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                AvatarView(
                    title: banner.title,
                    identifier: banner.chatId,
                    imagePath: banner.avatarPath,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(banner.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppText.tr("Закрыть", "Close"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassContainer(cornerRadius: 16)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }
}
