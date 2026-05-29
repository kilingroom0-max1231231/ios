import SwiftUI
import UIKit

/// Swipe left on a message row to run a single action; action icon slides in from the right edge.
struct SwipeableMessageRow<Content: View>: View {
    let actionIcon: String
    let actionColor: Color
    let onSwipe: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0

    private let triggerThreshold: CGFloat = 72
    private let maxDrag: CGFloat = 96
    private let hintSize: CGFloat = 42
    /// How far the hint sits beyond the message when the drag starts (off-screen / peek).
    private let hintHiddenOffset: CGFloat = 54

    private var dragProgress: CGFloat {
        min(1, abs(offset) / triggerThreshold)
    }

    var body: some View {
        content()
            .offset(x: offset)
            .overlay(alignment: .trailing) {
                swipeActionHint
                    .offset(x: hintHiddenOffset * (1 - dragProgress))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(horizontalDragGesture)
    }

    private var swipeActionHint: some View {
        Image(systemName: actionIcon)
            .font(.body.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: hintSize, height: hintSize)
            .background(
                Circle()
                    .fill(actionColor.gradient)
            )
            .shadow(color: actionColor.opacity(0.4), radius: 10, y: 3)
            .scaleEffect(0.5 + 0.5 * dragProgress)
            .opacity(Double(dragProgress))
            .allowsHitTesting(false)
    }

    private var horizontalDragGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.25 else { return }

                if value.translation.width < 0 {
                    offset = max(value.translation.width, -maxDrag)
                } else if offset < 0 {
                    offset = min(0, offset + value.translation.width)
                }
            }
            .onEnded { value in
                let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.25
                let shouldTrigger = horizontal && (value.translation.width < -triggerThreshold || offset < -triggerThreshold)

                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    offset = 0
                }

                if shouldTrigger {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSwipe()
                }
            }
    }
}
