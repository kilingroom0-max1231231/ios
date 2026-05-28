import SwiftUI
import UIKit

struct MessageBubbleView: View {
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.colorScheme) private var colorScheme

    let message: TgMessage
    let chatKind: ChatKind
    var outgoingIsRead: Bool = false
    var replyPreviewText: String?
    var onOpenAttachment: ((TgAttachment) -> Void)?
    var onReply: (() -> Void)?
    var onForward: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: ((_ revoke: Bool) -> Void)?

    private var maxBubbleWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        if message.outgoing {
            return screenWidth * (appearance.compactBubbles ? 0.70 : 0.76)
        }

        if hasGridMedia {
            return min(screenWidth * 0.62, 260)
        }
        if !standaloneMedia.isEmpty {
            return min(screenWidth * 0.58, 240)
        }
        if let captionText {
            let estimated = CGFloat(captionText.count) * 8.5 + 52
            return min(screenWidth * 0.72, max(96, estimated))
        }
        return min(screenWidth * 0.52, 220)
    }

    private var isCompactIncoming: Bool {
        !message.outgoing
    }

    private var messageFont: Font {
        .system(size: 17 * appearance.messageFontScale.scale)
    }

    private var captionFont: Font {
        .system(size: 16 * appearance.messageFontScale.scale)
    }

    private var showGroupSender: Bool {
        !message.outgoing
            && (chatKind == .basicGroup || chatKind == .supergroup)
            && message.senderName != nil
    }

    private var isCompactSideLayout: Bool {
        chatKind == .private || chatKind == .savedMessages
    }

    private var trailingInset: CGFloat {
        isCompactSideLayout ? 8 : 40
    }

    private var channelAuthorLine: String? {
        guard chatKind == .channel, !message.outgoing else { return nil }
        if let signature = message.authorSignature, !signature.isEmpty {
            return signature
        }
        return message.senderName
    }

    private var captionText: String? {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : message.text
    }

    private var gridMedia: [TgAttachment] {
        message.attachments.filter { attachment in
            switch attachment.kind {
            case .photo, .video, .animation:
                return true
            default:
                return false
            }
        }
    }

    private var standaloneMedia: [TgAttachment] {
        message.attachments.filter { attachment in
            switch attachment.kind {
            case .videoNote, .sticker, .voice, .document:
                return true
            default:
                return false
            }
        }
    }

    private var hasGridMedia: Bool { !gridMedia.isEmpty }
    private var hasHeaderContent: Bool {
        message.forwardedFrom != nil
            || channelAuthorLine != nil
            || message.replyToMessageId != nil
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: showGroupSender ? 8 : 0) {
            if message.outgoing {
                Spacer(minLength: trailingInset)
            } else if showGroupSender {
                AvatarView(
                    title: message.senderName ?? "?",
                    identifier: message.senderUserId ?? message.chatId,
                    imagePath: message.senderAvatarPath,
                    size: 30
                )
            }

            VStack(alignment: message.outgoing ? .trailing : .leading, spacing: 4) {
                if showGroupSender, let name = message.senderName {
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(senderNameColor(message.senderUserId ?? message.id))
                        .lineLimit(1)
                        .padding(.leading, 4)
                }

                bubbleBody
            }
            .frame(maxWidth: maxBubbleWidth, alignment: message.outgoing ? .trailing : .leading)

            if !message.outgoing {
                Spacer(minLength: trailingInset)
            }
        }
        .padding(.horizontal, isCompactSideLayout ? 6 : 10)
        .padding(.vertical, 2)
        .contextMenu {
            if let captionText {
                Button(AppText.tr("Скопировать", "Copy")) {
                    UIPasteboard.general.string = captionText
                }
            }
            if message.outgoing {
                if let onEdit, captionText != nil {
                    Button(AppText.tr("Изменить", "Edit")) { onEdit() }
                }
                if let onDelete {
                    Button(AppText.tr("Удалить у меня", "Delete for me")) { onDelete(false) }
                    Button(AppText.tr("Удалить у всех", "Delete for everyone"), role: .destructive) { onDelete(true) }
                }
            }
            if let onReply {
                Button(AppText.tr("Ответить", "Reply")) { onReply() }
            }
            if let onForward {
                Button(AppText.tr("Переслать", "Forward")) { onForward() }
            }
        }
    }

    private var bubbleBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasHeaderContent {
                VStack(alignment: .leading, spacing: 6) {
                    if let forwardedFrom = message.forwardedFrom, !forwardedFrom.isEmpty {
                        Text(AppText.tr("Переслано от \(forwardedFrom)", "Forwarded from \(forwardedFrom)"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let channelAuthorLine {
                        Text(channelAuthorLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(senderNameColor(message.senderUserId ?? message.id))
                    }

                    if let replyId = message.replyToMessageId {
                        replyPreview(replyId: replyId)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.top, 8)
                .padding(.bottom, hasGridMedia ? 6 : 0)
            }

            if hasGridMedia {
                MessageMediaGridView(
                    attachments: gridMedia,
                    maxWidth: maxBubbleWidth,
                    onOpen: { onOpenAttachment?($0) }
                )
                .opacity(message.isDeleted ? 0.72 : 1)
            }

            if let captionText {
                Text(captionText)
                    .font(captionFont)
                    .foregroundStyle(message.outgoing ? appearance.outgoingText(colorScheme: colorScheme) : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(message.isDeleted ? 0.72 : 1)
                    .padding(.horizontal, 11)
                    .padding(.top, hasGridMedia ? 8 : 8)
                    .padding(.bottom, standaloneMedia.isEmpty ? 0 : 6)
            }

            if !standaloneMedia.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(standaloneMedia) { attachment in
                        MessageAttachmentPreview(attachment: attachment, compact: isCompactIncoming) {
                            onOpenAttachment?(attachment)
                        }
                        .opacity(message.isDeleted ? 0.72 : 1)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.top, (hasGridMedia || captionText != nil) ? 6 : 8)
            }

            if captionText == nil && !hasGridMedia && standaloneMedia.isEmpty {
                if message.isDeleted {
                    Text(AppText.tr("Сообщение удалено", "Message deleted"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11)
                        .padding(.top, 8)
                } else {
                    Text(" ")
                        .font(.body)
                        .padding(.horizontal, 11)
                        .padding(.top, 8)
                }
            }

            bubbleFooter
                .padding(.horizontal, 11)
                .padding(.top, 6)
                .padding(.bottom, appearance.compactBubbles ? 6 : 8)
        }
        .background(
            message.outgoing
                ? appearance.outgoingBubble(colorScheme: colorScheme)
                : appearance.incomingBubble(colorScheme: colorScheme)
        )
        .clipShape(RoundedRectangle(cornerRadius: appearance.compactBubbles ? 14 : 16, style: .continuous))
        .overlay {
            if message.isDeleted {
                RoundedRectangle(cornerRadius: appearance.compactBubbles ? 14 : 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private var bubbleFooter: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            if message.isDeleted {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if message.isEdited {
                Text(AppText.tr("изм.", "edited"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let views = message.viewCount, views > 0, chatKind == .channel {
                HStack(spacing: 2) {
                    Image(systemName: "eye")
                    Text(formatViewCount(views))
                }
                .font(.caption2)
                    .foregroundStyle(message.outgoing ? appearance.outgoingText(colorScheme: colorScheme).opacity(0.75) : .secondary)
                }
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(message.outgoing ? appearance.outgoingText(colorScheme: colorScheme).opacity(0.8) : .secondary)
                if message.outgoing {
                    outgoingStatusIcon
                }
            }
        }
    }

    @ViewBuilder
    private var outgoingStatusIcon: some View {
        let tint = appearance.outgoingText(colorScheme: colorScheme).opacity(0.85)
        if message.isSending {
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(tint)
        } else if outgoingIsRead {
            Image(systemName: "checkmark")
                .font(.caption2.bold())
                .foregroundStyle(appearance.accentColor)
        } else {
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundStyle(tint.opacity(0.75))
        }
    }

    @ViewBuilder
    private func replyPreview(replyId: Int64) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(appearance.accentColor)
                .frame(width: 2, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppText.tr("Ответ", "Reply"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(replyPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                     ? (replyPreviewText ?? "")
                     : AppText.tr("Сообщение #\(replyId)", "Message #\(replyId)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func senderNameColor(_ id: Int64) -> Color {
        let palette: [Color] = [
            Color(red: 0.85, green: 0.35, blue: 0.30),
            Color(red: 0.30, green: 0.62, blue: 0.88),
            Color(red: 0.45, green: 0.72, blue: 0.35),
            Color(red: 0.72, green: 0.42, blue: 0.82),
            Color(red: 0.90, green: 0.55, blue: 0.20),
            Color(red: 0.35, green: 0.72, blue: 0.68)
        ]
        return palette[Int(abs(id) % Int64(palette.count))]
    }

    private func formatViewCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}
