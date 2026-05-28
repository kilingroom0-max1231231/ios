import SwiftUI
import UIKit

struct MessageBubbleView: View {
    let message: TgMessage
    let incomingAvatarPath: String?
    let incomingTitle: String
    var replyPreviewText: String?
    var onOpenAttachment: ((TgAttachment) -> Void)?
    var onReply: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: ((_ revoke: Bool) -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.outgoing {
                Spacer(minLength: 48)
            } else {
                AvatarView(title: incomingTitle, identifier: message.chatId, imagePath: incomingAvatarPath, size: 30)
            }

            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 6) {
                    if let replyId = message.replyToMessageId {
                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(AppColors.accent)
                                .frame(width: 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ответ")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(replyPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                     ? (replyPreviewText ?? "")
                                     : "Сообщение #\(replyId)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if !message.text.isEmpty || message.attachments.isEmpty {
                        Text(message.text.isEmpty ? " " : message.text)
                            .font(.body)
                            .foregroundStyle(message.outgoing ? AppColors.outgoingText : .primary)
                            .multilineTextAlignment(.leading)
                            .strikethrough(message.isDeleted, pattern: .solid, color: .secondary)
                    }

                    if !message.attachments.isEmpty {
                        ForEach(message.attachments) { attachment in
                            MessageAttachmentPreview(attachment: attachment) {
                                onOpenAttachment?(attachment)
                            }
                        }
                    }
                }
                .padding(.bottom, 14)

                HStack(spacing: 6) {
                    if message.isDeleted {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if message.isEdited {
                        Text("edited")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(message.outgoing ? AppColors.outgoingText.opacity(0.8) : .secondary)
                    if message.outgoing {
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: .leading)
            .background(message.outgoing ? AppColors.outgoingBubble : AppColors.incomingBubble)
            .clipShape(BubbleShape(isOutgoing: message.outgoing))

            if !message.outgoing {
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .contextMenu {
            if !message.text.isEmpty {
                Button("Скопировать") {
                    UIPasteboard.general.string = message.text
                }
            }
            if message.outgoing {
                if let onEdit, !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Изменить") { onEdit() }
                }
                if let onDelete {
                    Button("Удалить у меня") { onDelete(false) }
                    Button("Удалить у всех", role: .destructive) { onDelete(true) }
                }
            }
            if let onReply {
                Button("Ответить") { onReply() }
            }
        }
    }
}

private struct BubbleShape: Shape {
    let isOutgoing: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        var path = Path(roundedRect: rect, cornerRadius: radius)

        // Small tail to look closer to Telegram bubble style.
        let tailWidth: CGFloat = 7
        let tailHeight: CGFloat = 10
        let y = rect.maxY - 16
        if isOutgoing {
            path.move(to: CGPoint(x: rect.maxX - 2, y: y))
            path.addLine(to: CGPoint(x: rect.maxX + tailWidth, y: y + 3))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: y + tailHeight))
            path.closeSubpath()
        } else {
            path.move(to: CGPoint(x: rect.minX + 2, y: y))
            path.addLine(to: CGPoint(x: rect.minX - tailWidth, y: y + 3))
            path.addLine(to: CGPoint(x: rect.minX + 2, y: y + tailHeight))
            path.closeSubpath()
        }
        return path
    }
}
