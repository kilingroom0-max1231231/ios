import SwiftUI

struct MessageSwipeActionButton: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let color: Color
    let handler: () -> Void
}

struct SwipeableMessageRow<Content: View>: View {
    let actions: [MessageSwipeActionButton]
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0

    private let actionWidth: CGFloat = 76

    private var revealWidth: CGFloat {
        CGFloat(actions.count) * actionWidth
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if !actions.isEmpty {
                HStack(spacing: 0) {
                    ForEach(actions) { action in
                        Button {
                            close(animated: true)
                            action.handler()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: action.systemImage)
                                    .font(.body.weight(.semibold))
                                Text(action.title)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(.white)
                            .frame(width: actionWidth)
                            .frame(maxHeight: .infinity)
                            .background(action.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.clear)
                .offset(x: offset)
                .gesture(horizontalDragGesture)
        }
        .clipped()
        .contentShape(Rectangle())
    }

    private var horizontalDragGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                guard !actions.isEmpty else { return }
                guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }

                if value.translation.width < 0 {
                    offset = max(value.translation.width, -revealWidth)
                } else if offset < 0 {
                    offset = min(0, offset + value.translation.width)
                }
            }
            .onEnded { value in
                guard !actions.isEmpty else { return }
                guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else {
                    close(animated: true)
                    return
                }

                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    if -offset > revealWidth * 0.35 {
                        offset = -revealWidth
                    } else {
                        offset = 0
                    }
                }
            }
    }

    private func close(animated: Bool) {
        guard offset != 0 else { return }
        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                offset = 0
            }
        } else {
            offset = 0
        }
    }
}
