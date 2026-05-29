import SwiftUI

struct MessageActionTarget: Identifiable {
    let message: TgMessage
    var id: Int64 { message.id }
}

struct MessageActionsSheet: View {
    @ObservedObject var vm: AppViewModel
    let message: TgMessage
    let canSend: Bool
    let canEdit: Bool
    let captionText: String?

    let onReply: () -> Void
    let onForward: () -> Void
    let onEdit: () -> Void
    let onDelete: (Bool) -> Void
    let onCopy: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var liveMessage: TgMessage {
        vm.messages.first(where: { $0.id == message.id }) ?? message
    }

    var body: some View {
        VStack(spacing: 0) {
            reactionBar
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            messagePreview
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            actionsList
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await vm.loadReactionPicker(for: message)
        }
    }

    private var reactionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppText.tr("Реакции", "Reactions"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if vm.reactionPickerMaxCount > 1 {
                    Text(
                        AppText.tr(
                            "до \(vm.reactionPickerMaxCount)",
                            "up to \(vm.reactionPickerMaxCount)"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(vm.reactionPickerEmojis, id: \.self) { emoji in
                        reactionButton(emoji: emoji)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private func reactionButton(emoji: String) -> some View {
        let isChosen = liveMessage.reactions.contains { $0.emoji == emoji && $0.isChosen }
        return Button {
            guard canSend else { return }
            Task {
                await vm.toggleReaction(on: liveMessage, emoji: emoji)
            }
        } label: {
            Text(emoji)
                .font(.system(size: 34))
                .frame(width: 48, height: 48)
                .background(
                    isChosen
                        ? AppColors.accent.opacity(0.22)
                        : Color(.secondarySystemBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isChosen ? AppColors.accent : Color.clear, lineWidth: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private var messagePreview: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: message.outgoing ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(message.outgoing ? AppColors.accent : .secondary)
            Text(previewText)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previewText: String {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let caption = captionText, !caption.isEmpty { return caption }
        if !message.attachments.isEmpty {
            return AppText.tr("Медиа", "Media")
        }
        return AppText.tr("Сообщение", "Message")
    }

    private var actionsList: some View {
        List {
            if canSend {
                actionRow(
                    title: AppText.tr("Ответить", "Reply"),
                    icon: "arrowshape.turn.up.left.fill",
                    color: AppColors.accent
                ) {
                    onReply()
                    dismiss()
                }
            }

            actionRow(
                title: AppText.tr("Переслать", "Forward"),
                icon: "arrowshape.turn.up.right.fill",
                color: .green
            ) {
                onForward()
                dismiss()
            }

            if let captionText, !captionText.isEmpty {
                actionRow(
                    title: AppText.tr("Скопировать", "Copy"),
                    icon: "doc.on.doc.fill",
                    color: .orange
                ) {
                    onCopy()
                    dismiss()
                }
            }

            if canEdit {
                actionRow(
                    title: AppText.tr("Изменить", "Edit"),
                    icon: "pencil",
                    color: .blue
                ) {
                    onEdit()
                    dismiss()
                }
            }

            if message.outgoing {
                actionRow(
                    title: AppText.tr("Удалить у меня", "Delete for me"),
                    icon: "trash",
                    color: .gray
                ) {
                    onDelete(false)
                    dismiss()
                }
                actionRow(
                    title: AppText.tr("Удалить у всех", "Delete for everyone"),
                    icon: "trash.fill",
                    color: .red
                ) {
                    onDelete(true)
                    dismiss()
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func actionRow(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
        }
    }
}
