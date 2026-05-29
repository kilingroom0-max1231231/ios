import SwiftUI
import UIKit

struct MessageActionTarget: Identifiable {
    let message: TgMessage
    var id: Int64 { message.id }
}

struct MessageBubbleFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int64: CGRect] = [:]

    static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func reportMessageBubbleFrame(messageId: Int64) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: MessageBubbleFramePreferenceKey.self,
                    value: [messageId: geo.frame(in: .global)]
                )
            }
        }
    }
}

private struct VisualEffectBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct MessageActionsOverlay: View {
    @ObservedObject var vm: AppViewModel
    let target: MessageActionTarget
    let messageFrame: CGRect?
    let chatKind: ChatKind
    let peerAvatarPath: String?
    let peerTitle: String?
    let replyPreviewText: String?
    let canSend: Bool
    let canEdit: Bool
    let captionText: String?

    let onDismiss: () -> Void
    let onReply: () -> Void
    let onForward: () -> Void
    let onEdit: () -> Void
    let onDelete: (Bool) -> Void
    let onCopy: () -> Void

    @ObservedObject private var appSettings = AppSettingsStore.shared
    @State private var reactionsExpanded = false
    @State private var appeared = false

    private let compactReactionLimit = 8
    private let reactionGridColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    private var message: TgMessage {
        vm.messages.first(where: { $0.id == target.message.id }) ?? target.message
    }

    private var displayedEmojis: [String] {
        if reactionsExpanded || vm.reactionPickerEmojis.count <= compactReactionLimit {
            return vm.reactionPickerEmojis
        }
        return Array(vm.reactionPickerEmojis.prefix(compactReactionLimit))
    }

    private var canExpandReactions: Bool {
        vm.reactionPickerEmojis.count > compactReactionLimit
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom
            let overlayOrigin = geo.frame(in: .global).origin
            let localMessageFrame = messageFrame.map { globalFrame in
                CGRect(
                    x: globalFrame.minX - overlayOrigin.x,
                    y: globalFrame.minY - overlayOrigin.y,
                    width: globalFrame.width,
                    height: globalFrame.height
                )
            }

            ZStack {
                backdrop
                    .onTapGesture { dismiss() }

                if let frame = localMessageFrame, frame.width > 1, frame.height > 1 {
                    positionedContent(
                        messageFrame: frame,
                        containerSize: size,
                        safeTop: safeTop,
                        safeBottom: safeBottom
                    )
                } else {
                    centeredFallback(size: size, safeTop: safeTop, safeBottom: safeBottom)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .task {
            await vm.loadReactionPicker(for: message)
            if appSettings.expandReactionPickerByDefault {
                reactionsExpanded = true
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            VisualEffectBlur(style: .systemChromeMaterialDark)
            Color.black.opacity(0.42)
        }
    }

    @ViewBuilder
    private func positionedContent(
        messageFrame: CGRect,
        containerSize: CGSize,
        safeTop: CGFloat,
        safeBottom: CGFloat
    ) {
        let layout = overlayLayout(
            messageFrame: messageFrame,
            containerSize: containerSize,
            safeTop: safeTop,
            safeBottom: safeBottom
        )

        ZStack {
            reactionsPanel(width: layout.panelWidth)
                .position(x: layout.panelCenterX, y: layout.reactionsCenterY)

            highlightedBubble
                .frame(width: messageFrame.width, alignment: message.outgoing ? .trailing : .leading)
                .position(x: layout.bubbleCenterX, y: layout.bubbleCenterY)

            actionsMenu(width: layout.panelWidth)
                .position(x: layout.panelCenterX, y: layout.actionsCenterY)
        }
        .allowsHitTesting(true)
    }

    private func centeredFallback(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        let midY = (safeTop + size.height - safeBottom) / 2
        return VStack(spacing: 12) {
            reactionsPanel(width: min(size.width - 32, 340))
            highlightedBubble
                .padding(.horizontal, 12)
            actionsMenu(width: min(size.width - 48, 280))
        }
        .frame(maxWidth: .infinity)
        .position(x: size.width / 2, y: midY)
    }

    private struct OverlayLayout {
        let panelWidth: CGFloat
        let panelCenterX: CGFloat
        let bubbleCenterX: CGFloat
        let bubbleCenterY: CGFloat
        let reactionsCenterY: CGFloat
        let actionsCenterY: CGFloat
    }

    private func overlayLayout(
        messageFrame: CGRect,
        containerSize: CGSize,
        safeTop: CGFloat,
        safeBottom: CGFloat
    ) -> OverlayLayout {
        let panelWidth = min(containerSize.width - 24, 360)
        let reactionsH = reactionsPanelHeight
        let actionsH = actionsMenuHeight
        let gap: CGFloat = 10

        let bubbleCenterX = messageFrame.midX
        var bubbleCenterY = messageFrame.midY

        let contentTop = safeTop + 8 + reactionsH + gap
        let contentBottom = containerSize.height - safeBottom - 8 - actionsH - gap

        let bubbleHalf = messageFrame.height / 2
        let minBubbleY = contentTop + bubbleHalf
        let maxBubbleY = contentBottom - bubbleHalf
        if minBubbleY <= maxBubbleY {
            bubbleCenterY = min(max(bubbleCenterY, minBubbleY), maxBubbleY)
        } else {
            bubbleCenterY = (contentTop + contentBottom) / 2
        }

        let panelCenterX: CGFloat = {
            let half = panelWidth / 2
            let inset: CGFloat = 12
            if message.outgoing {
                return min(containerSize.width - inset - half, max(half + inset, messageFrame.maxX - half))
            }
            return max(inset + half, min(containerSize.width - inset - half, messageFrame.minX + half))
        }()

        let reactionsCenterY = bubbleCenterY - bubbleHalf - gap - reactionsH / 2
        let actionsCenterY = bubbleCenterY + bubbleHalf + gap + actionsH / 2

        return OverlayLayout(
            panelWidth: panelWidth,
            panelCenterX: panelCenterX,
            bubbleCenterX: bubbleCenterX,
            bubbleCenterY: bubbleCenterY,
            reactionsCenterY: reactionsCenterY,
            actionsCenterY: actionsCenterY
        )
    }

    private var reactionsPanelHeight: CGFloat {
        if reactionsExpanded {
            let rows = ceil(Double(displayedEmojis.count) / 6.0)
            return 52 + rows * 48 + (canExpandReactions ? 36 : 0)
        }
        return 56
    }

    private var actionsMenuHeight: CGFloat {
        CGFloat(actionItems.count) * 46 + 12
    }

    private var highlightedBubble: some View {
        MessageBubbleView(
            message: message,
            chatKind: chatKind,
            peerAvatarPath: peerAvatarPath,
            peerTitle: peerTitle,
            replyPreviewText: replyPreviewText,
            interactionsEnabled: false
        )
        .scaleEffect(appeared ? 1.02 : 1)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .shadow(color: AppColors.accent.opacity(0.15), radius: 12, y: 4)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 2)
                .padding(-2)
        }
    }

    private func reactionsPanel(width: CGFloat) -> some View {
        VStack(spacing: 6) {
            if reactionsExpanded {
                LazyVGrid(columns: reactionGridColumns, spacing: 6) {
                    ForEach(displayedEmojis, id: \.self) { emoji in
                        reactionButton(emoji: emoji, compact: true)
                    }
                }
                if canExpandReactions {
                    collapseReactionsButton
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displayedEmojis, id: \.self) { emoji in
                            reactionButton(emoji: emoji, compact: false)
                        }
                        if canExpandReactions {
                            expandReactionsChip
                        }
                    }
                    .padding(.horizontal, 4)
                }
                if canExpandReactions {
                    expandAllReactionsButton
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: width)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var expandReactionsChip: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                reactionsExpanded = true
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                Text(AppText.tr("ещё", "more"))
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var expandAllReactionsButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                reactionsExpanded = true
            }
        } label: {
            Text(AppText.tr("Все реакции", "All reactions"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var collapseReactionsButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                reactionsExpanded = false
            }
        } label: {
            Label(AppText.tr("Свернуть", "Collapse"), systemImage: "chevron.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func reactionButton(emoji: String, compact: Bool) -> some View {
        let isChosen = message.reactions.contains { $0.emoji == emoji && $0.isChosen }
        return Button {
            guard canSend else { return }
            appSettings.reactionHaptic(.light)
            Task { await vm.toggleReaction(on: message, emoji: emoji) }
        } label: {
            Text(emoji)
                .font(.system(size: compact ? 26 : 30))
                .frame(width: compact ? nil : 44, height: compact ? 40 : 44)
                .frame(maxWidth: compact ? .infinity : nil)
                .background(
                    isChosen
                        ? AppColors.accent.opacity(0.28)
                        : Color.white.opacity(0.08)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private struct ActionItem: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let color: Color
        let role: ButtonRole?
        let handler: () -> Void
    }

    private var actionItems: [ActionItem] {
        var items: [ActionItem] = []
        if canSend {
            items.append(ActionItem(
                title: AppText.tr("Ответить", "Reply"),
                icon: "arrowshape.turn.up.left.fill",
                color: AppColors.accent,
                role: nil
            ) {
                onReply()
                dismiss()
            })
        }
        items.append(ActionItem(
            title: AppText.tr("Переслать", "Forward"),
            icon: "arrowshape.turn.up.right.fill",
            color: .green,
            role: nil
        ) {
            onForward()
            dismiss()
        })
        if let captionText, !captionText.isEmpty {
            items.append(ActionItem(
                title: AppText.tr("Скопировать", "Copy"),
                icon: "doc.on.doc.fill",
                color: .orange,
                role: nil
            ) {
                onCopy()
                dismiss()
            })
        }
        if canEdit {
            items.append(ActionItem(
                title: AppText.tr("Изменить", "Edit"),
                icon: "pencil",
                color: .blue,
                role: nil
            ) {
                onEdit()
                dismiss()
            })
        }
        if message.outgoing {
            items.append(ActionItem(
                title: AppText.tr("Удалить у меня", "Delete for me"),
                icon: "trash",
                color: .secondary,
                role: nil
            ) {
                onDelete(false)
                dismiss()
            })
            items.append(ActionItem(
                title: AppText.tr("Удалить у всех", "Delete for everyone"),
                icon: "trash.fill",
                color: .red,
                role: .destructive
            ) {
                onDelete(true)
                dismiss()
            })
        }
        return items
    }

    private func actionsMenu(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(actionItems.enumerated()), id: \.offset) { index, item in
                Button(role: item.role) {
                    item.handler()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(item.color)
                            .frame(width: 24)
                        Text(item.title)
                            .font(.body)
                            .foregroundStyle(item.role == .destructive ? .red : .primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < actionItems.count - 1 {
                    Divider().opacity(0.35)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(width: width)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}
