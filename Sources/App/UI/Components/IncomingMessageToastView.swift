import SwiftUI

struct IncomingMessageToastView: View {
    let toast: IncomingMessageToast
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                AvatarView(
                    title: toast.title,
                    identifier: toast.chatId,
                    imagePath: toast.avatarPath,
                    size: 40
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(toast.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}
