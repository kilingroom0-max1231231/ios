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
    @State private var backdropOpacity: Double = 0
    @State private var bubbleScale: CGFloat = 0.9
    @State private var panelsOpacity: Double = 0
    @State private var panelsOffset: CGFloat = 16
    @State private var reactionsScale: CGFloat = 0.88
    @State private var actionsScale: CGFloat = 0.92

    private let collapsedReactionsHeight: CGFloat = 56
    private let expandedRowHeight: CGFloat = 42
    private let expandedMaxRowsVisible: CGFloat = 3.5

    private var reactionGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    private var panelSpring: Animation {
        .spring(response: 0.36, dampingFraction: 0.82)
    }

    private var message: TgMessage {
        vm.messages.first(where: { $0.id == target.message.id }) ?? target.message
    }

    private var pickerItems: [TgReactionPickerItem] {
        vm.reactionPickerItems
    }

    private var canExpandReactions: Bool {
        pickerItems.count > 10
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
                    .opacity(backdropOpacity)
                    .onTapGesture { dismiss() }

                if let frame = localMessageFrame, frame.width > 1, frame.height > 1 {
                    positionedContent(
                        messageFrame: frame,
                        containerSize: size,
                        safeTop: safeTop,
                        safeBottom: safeBottom,
                        maxExpandedReactionsHeight: maxExpandedReactionsHeight(
                            containerHeight: size.height,
                            safeTop: safeTop,
                            safeBottom: safeBottom
                        )
                    )
                } else {
                    centeredFallback(size: size, safeTop: safeTop, safeBottom: safeBottom)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            appSettings.reactionHaptic(.medium)
            withAnimation(.easeOut(duration: 0.22)) {
                backdropOpacity = 1
            }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                bubbleScale = 1.03
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(0.04)) {
                panelsOpacity = 1
                panelsOffset = 0
                reactionsScale = 1
                actionsScale = 1
            }
        }
        .task {
            await vm.loadReactionPicker(for: message)
            if appSettings.expandReactionPickerByDefault, canExpandReactions {
                try? await Task.sleep(nanoseconds: 120_000_000)
                expandReactionsPanel()
            }
        }
    }

    private func maxExpandedReactionsHeight(
        containerHeight: CGFloat,
        safeTop: CGFloat,
        safeBottom: CGFloat
    ) -> CGFloat {
        let available = containerHeight - safeTop - safeBottom
        let preferred = expandedMaxRowsVisible * expandedRowHeight + 36
        return max(110, min(preferred, available * 0.42, 240))
    }

    private var backdrop: some View {
        ZStack {
            VisualEffectBlur(style: .systemChromeMaterialDark)
            Color.black.opacity(0.45)
        }
    }

    @ViewBuilder
    private func positionedContent(
        messageFrame: CGRect,
        containerSize: CGSize,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        maxExpandedReactionsHeight: CGFloat
    ) -> some View {
        let reactionsH = reactionsPanelHeight(maxExpandedHeight: maxExpandedReactionsHeight)
        let actionsH = actionsMenuHeight
        let topMargin = safeTop + 8
        let bottomMargin = safeBottom + 8
        let available = containerSize.height - topMargin - bottomMargin
        // Natural height with an uncapped bubble. When it doesn't fit, fall back to a
        // scrollable stack so the action buttons stay reachable for long messages.
        let naturalStack = reactionsH + 10 + min(messageFrame.height, available) + 10 + actionsH

        if naturalStack > available {
            scrollableStack(
                messageFrame: messageFrame,
                containerSize: containerSize,
                safeTop: safeTop,
                safeBottom: safeBottom,
                maxExpandedReactionsHeight: maxExpandedReactionsHeight
            )
        } else {
            anchoredContent(
                messageFrame: messageFrame,
                containerSize: containerSize,
                safeTop: safeTop,
                safeBottom: safeBottom,
                maxExpandedReactionsHeight: maxExpandedReactionsHeight
            )
        }
    }

    private func scrollableStack(
        messageFrame: CGRect,
        containerSize: CGSize,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        maxExpandedReactionsHeight: CGFloat
    ) -> some View {
        let inset: CGFloat = 12
        let reactionsWidth = min(containerSize.width - inset * 2, 340)
        let actionsWidth = min(containerSize.width - inset * 2, 250)
        let alignment: HorizontalAlignment = message.outgoing ? .trailing : .leading

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: alignment, spacing: 10) {
                reactionsPanel(width: reactionsWidth, maxExpandedHeight: maxExpandedReactionsHeight)
                    .scaleEffect(reactionsScale, anchor: .bottom)
                    .opacity(panelsOpacity)

                highlightedBubble()
                    .scaleEffect(bubbleScale)
                    .frame(maxWidth: messageFrame.width, alignment: message.outgoing ? .trailing : .leading)

                actionsMenu(width: actionsWidth)
                    .scaleEffect(actionsScale, anchor: .top)
                    .opacity(panelsOpacity)
            }
            .frame(maxWidth: .infinity, alignment: message.outgoing ? .trailing : .leading)
            .padding(.horizontal, inset)
            .padding(.top, safeTop + 8)
            .padding(.bottom, safeBottom + 8)
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .animation(panelSpring, value: reactionsExpanded)
    }

    private func anchoredContent(
        messageFrame: CGRect,
        containerSize: CGSize,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        maxExpandedReactionsHeight: CGFloat
    ) -> some View {
        let layout = overlayLayout(
            messageFrame: messageFrame,
            containerSize: containerSize,
            safeTop: safeTop,
            safeBottom: safeBottom,
            maxExpandedReactionsHeight: maxExpandedReactionsHeight
        )

        let needsScroll = messageFrame.height > layout.bubbleHeight + 1

        return LiquidGlassGroup(spacing: 18) {
            ZStack {
                reactionsPanel(
                    width: layout.reactionsWidth,
                    maxExpandedHeight: maxExpandedReactionsHeight
                )
                .scaleEffect(reactionsScale, anchor: .bottom)
                .opacity(panelsOpacity)
                .offset(y: panelsOffset)
                .position(x: layout.reactionsCenterX, y: layout.reactionsCenterY)

                highlightedBubble(maxHeight: layout.bubbleHeight, scrollable: needsScroll)
                    .scaleEffect(bubbleScale)
                    .frame(
                        width: messageFrame.width,
                        height: layout.bubbleHeight,
                        alignment: message.outgoing ? .trailing : .leading
                    )
                    .position(x: layout.bubbleCenterX, y: layout.bubbleCenterY)

                actionsMenu(width: layout.actionsWidth)
                    .scaleEffect(actionsScale, anchor: .top)
                    .opacity(panelsOpacity)
                    .offset(y: -panelsOffset)
                    .position(x: layout.actionsCenterX, y: layout.actionsCenterY)
            }
        }
        .allowsHitTesting(true)
        .animation(panelSpring, value: reactionsExpanded)
    }

    private func centeredFallback(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        let midY = (safeTop + size.height - safeBottom) / 2
        let fallbackMaxReactionsH = min(152, size.height * 0.22)
        return LiquidGlassGroup(spacing: 18) {
            VStack(spacing: 12) {
                reactionsPanel(width: min(size.width - 32, 360), maxExpandedHeight: fallbackMaxReactionsH)
                    .scaleEffect(reactionsScale, anchor: .bottom)
                    .opacity(panelsOpacity)
                    .offset(y: panelsOffset)
                highlightedBubble()
                    .scaleEffect(bubbleScale)
                    .padding(.horizontal, 12)
                actionsMenu(width: min(size.width - 48, 280))
                    .scaleEffect(actionsScale, anchor: .top)
                    .opacity(panelsOpacity)
                    .offset(y: -panelsOffset)
            }
            .frame(maxWidth: .infinity)
        }
        .position(x: size.width / 2, y: midY)
        .animation(panelSpring, value: reactionsExpanded)
    }

    private struct OverlayLayout {
        let reactionsWidth: CGFloat
        let reactionsCenterX: CGFloat
        let actionsWidth: CGFloat
        let actionsCenterX: CGFloat
        let bubbleCenterX: CGFloat
        let bubbleCenterY: CGFloat
        let bubbleHeight: CGFloat
        let reactionsCenterY: CGFloat
        let actionsCenterY: CGFloat
    }

    private func overlayLayout(
        messageFrame: CGRect,
        containerSize: CGSize,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        maxExpandedReactionsHeight: CGFloat
    ) -> OverlayLayout {
        let inset: CGFloat = 12
        let availableWidth = containerSize.width - inset * 2
        let reactionsWidth = min(availableWidth, 340)
        let actionsWidth = min(availableWidth, 250)
        let reactionsH = reactionsPanelHeight(maxExpandedHeight: maxExpandedReactionsHeight)
        let actionsH = actionsMenuHeight
        let gap: CGFloat = 10
        let topMargin = safeTop + 8
        let bottomMargin = safeBottom + 8

        // The bubble may only occupy the vertical space left between both panels;
        // longer messages are capped and become scrollable so nothing leaves the screen.
        let availableForBubble = containerSize.height - topMargin - bottomMargin - reactionsH - actionsH - gap * 2
        let bubbleHeight = max(72, min(messageFrame.height, max(72, availableForBubble)))

        // Center the whole reaction + bubble + actions stack vertically and clamp on screen.
        let stackHeight = reactionsH + gap + bubbleHeight + gap + actionsH
        var startY = (containerSize.height - stackHeight) / 2
        startY = max(topMargin, min(startY, containerSize.height - bottomMargin - stackHeight))

        let reactionsCenterY = startY + reactionsH / 2
        let bubbleCenterY = startY + reactionsH + gap + bubbleHeight / 2
        let actionsCenterY = startY + reactionsH + gap + bubbleHeight + gap + actionsH / 2

        // Align a panel of the given width to the message's side, kept on screen.
        func centerX(for width: CGFloat) -> CGFloat {
            let half = width / 2
            if message.outgoing {
                return min(containerSize.width - inset - half, max(half + inset, messageFrame.maxX - half))
            }
            return max(inset + half, min(containerSize.width - inset - half, messageFrame.minX + half))
        }

        let bubbleHalfWidth = messageFrame.width / 2
        let bubbleCenterX = min(
            containerSize.width - inset - bubbleHalfWidth,
            max(inset + bubbleHalfWidth, messageFrame.midX)
        )

        return OverlayLayout(
            reactionsWidth: reactionsWidth,
            reactionsCenterX: centerX(for: reactionsWidth),
            actionsWidth: actionsWidth,
            actionsCenterX: centerX(for: actionsWidth),
            bubbleCenterX: bubbleCenterX,
            bubbleCenterY: bubbleCenterY,
            bubbleHeight: bubbleHeight,
            reactionsCenterY: reactionsCenterY,
            actionsCenterY: actionsCenterY
        )
    }

    private func reactionsPanelHeight(maxExpandedHeight: CGFloat) -> CGFloat {
        if reactionsExpanded {
            let columns = 7.0
            let rows = ceil(Double(pickerItems.count) / columns)
            let contentHeight = rows * expandedRowHeight
            let scrollHeight = min(maxExpandedHeight - 28, contentHeight)
            return min(maxExpandedHeight, scrollHeight + 28)
        }
        return collapsedReactionsHeight
    }

    private let actionRowHeight: CGFloat = 48

    private var actionsMenuHeight: CGFloat {
        CGFloat(actionItems.count) * actionRowHeight
    }

    @ViewBuilder
    private func highlightedBubble(maxHeight: CGFloat = .infinity, scrollable: Bool = false) -> some View {
        let bubble = MessageBubbleView(
            message: message,
            chatKind: chatKind,
            peerAvatarPath: peerAvatarPath,
            peerTitle: peerTitle,
            replyPreviewText: replyPreviewText,
            interactionsEnabled: false
        )
        .shadow(color: .black.opacity(0.32), radius: 20, y: 10)

        if scrollable {
            ScrollView(.vertical, showsIndicators: true) {
                bubble
            }
            .frame(maxHeight: maxHeight)
        } else {
            bubble
        }
    }

    private func collapsedReactionsWidth(maxWidth: CGFloat) -> CGFloat {
        let itemExtent: CGFloat = 44 + 4
        var content = CGFloat(pickerItems.count) * itemExtent
        if canExpandReactions { content += itemExtent }
        let horizontalPadding: CGFloat = 12
        return min(maxWidth, content + horizontalPadding)
    }

    @ViewBuilder
    private func reactionsPanel(width: CGFloat, maxExpandedHeight: CGFloat) -> some View {
        if reactionsExpanded {
            expandedReactionsPanel(width: width, maxExpandedHeight: maxExpandedHeight)
        } else {
            collapsedReactionsPanel(maxWidth: width)
        }
    }

    private func collapsedReactionsPanel(maxWidth: CGFloat) -> some View {
        compactReactionsStrip
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(width: collapsedReactionsWidth(maxWidth: maxWidth))
            .glassSurface(cornerRadius: collapsedReactionsHeight / 2)
            .contentShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 8, y: 6)
            .frame(maxWidth: maxWidth, alignment: message.outgoing ? .trailing : .leading)
    }

    private func expandedReactionsPanel(width: CGFloat, maxExpandedHeight: CGFloat) -> some View {
        let expandedHeight = reactionsPanelHeight(maxExpandedHeight: maxExpandedHeight)
        return VStack(spacing: 6) {
            expandedReactionsGrid(maxHeight: maxExpandedHeight - 30)
                .frame(height: expandedHeight - (canExpandReactions ? 26 : 0))
                .clipped()

            if canExpandReactions {
                collapseReactionsButton
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: width, height: expandedHeight)
        .glassSurface(cornerRadius: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    private var compactReactionsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(pickerItems) { item in
                    reactionButton(item: item, compact: false)
                }
                if canExpandReactions {
                    expandReactionsButton
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func expandedReactionsGrid(maxHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: reactionGridColumns, spacing: 6) {
                ForEach(pickerItems) { item in
                    reactionButton(item: item, compact: true)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .frame(maxHeight: max(72, maxHeight))
    }

    private func expandReactionsPanel() {
        appSettings.reactionHaptic(.light)
        withAnimation(panelSpring) {
            reactionsExpanded = true
            reactionsScale = 1
        }
    }

    private func collapseReactionsPanel() {
        appSettings.reactionHaptic(.light)
        withAnimation(panelSpring) {
            reactionsExpanded = false
            reactionsScale = 1
        }
    }

    private var expandReactionsButton: some View {
        Button {
            expandReactionsPanel()
        } label: {
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background {
                    Circle().fill(.quaternary)
                }
        }
        .buttonStyle(.plain)
    }

    private var collapseReactionsButton: some View {
        Button {
            collapseReactionsPanel()
        } label: {
            Label(AppText.tr("Свернуть", "Collapse"), systemImage: "chevron.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reactionButton(item: TgReactionPickerItem, compact: Bool) -> some View {
        let isChosen = message.reactions.contains { $0.key == item.key && $0.isChosen }
        return Button {
            guard canSend else { return }
            appSettings.reactionHaptic(.light)
            Task { await vm.toggleReaction(on: message, item: item) }
        } label: {
            ReactionPickerItemView(item: item, compact: compact)
                .frame(width: compact ? nil : 44, height: compact ? 40 : 44)
                .frame(maxWidth: compact ? .infinity : nil)
                .background {
                    if isChosen {
                        if compact {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppColors.accent.opacity(0.28))
                        } else {
                            Circle().fill(AppColors.accent.opacity(0.28))
                        }
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .scaleEffect(isChosen ? 1.08 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isChosen)
    }

    private struct ActionItem: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let role: ButtonRole?
        let handler: () -> Void
    }

    private var actionItems: [ActionItem] {
        var items: [ActionItem] = []
        if canSend {
            items.append(ActionItem(
                title: AppText.tr("Ответить", "Reply"),
                icon: "arrowshape.turn.up.left",
                role: nil
            ) {
                onReply()
                dismiss()
            })
        }
        items.append(ActionItem(
            title: AppText.tr("Переслать", "Forward"),
            icon: "arrowshape.turn.up.right",
            role: nil
        ) {
            onForward()
            dismiss()
        })
        if let captionText, !captionText.isEmpty {
            items.append(ActionItem(
                title: AppText.tr("Скопировать", "Copy"),
                icon: "doc.on.doc",
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
                role: nil
            ) {
                onDelete(false)
                dismiss()
            })
            items.append(ActionItem(
                title: AppText.tr("Удалить у всех", "Delete for everyone"),
                icon: "trash",
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
                Button(role: item.role, action: item.handler) {
                    HStack(spacing: 12) {
                        Text(item.title)
                            .font(.body)
                        Spacer(minLength: 8)
                        Image(systemName: item.icon)
                            .font(.body)
                            .frame(width: 22)
                    }
                    .foregroundStyle(item.role == .destructive ? Color.red : Color.primary)
                    .padding(.horizontal, 16)
                    .frame(height: actionRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ActionRowButtonStyle())

                if index < actionItems.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .frame(width: width)
        .glassSurface(cornerRadius: 22)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }

    private struct ActionRowButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
        }
    }

    private func dismiss() {
        appSettings.reactionHaptic(.light)
        withAnimation(.easeIn(duration: 0.2)) {
            backdropOpacity = 0
            panelsOpacity = 0
            panelsOffset = 12
            bubbleScale = 0.92
            reactionsScale = 0.86
            actionsScale = 0.9
            reactionsExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onDismiss()
        }
    }
}
