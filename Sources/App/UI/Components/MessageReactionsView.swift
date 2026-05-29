import SwiftUI

struct MessageReactionsView: View {
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.colorScheme) private var colorScheme

    let reactions: [TgMessageReaction]
    let outgoing: Bool
    var onTap: ((String) -> Void)?

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(reactions) { reaction in
                reactionChip(reaction)
            }
        }
    }

    private func reactionChip(_ reaction: TgMessageReaction) -> some View {
        Button {
            onTap?(reaction.emoji)
        } label: {
            HStack(spacing: 4) {
                Text(reaction.emoji)
                    .font(.system(size: 15))
                if reaction.count > 1 {
                    Text("\(reaction.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(reaction.isChosen ? appearance.accentColor : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(chipBackground(reaction.isChosen))
            .overlay {
                Capsule()
                    .stroke(
                        reaction.isChosen ? appearance.accentColor.opacity(0.55) : Color.clear,
                        lineWidth: 1
                    )
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    private func chipBackground(_ isChosen: Bool) -> Color {
        if isChosen {
            return appearance.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.16)
        }
        return Color(.secondarySystemBackground).opacity(colorScheme == .dark ? 0.9 : 1)
    }
}

/// Simple wrapping layout for reaction chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() where index < subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let width = min(maxWidth, frames.map { $0.maxX }.max() ?? 0)
        let height = y + rowHeight
        return (CGSize(width: width, height: height), frames)
    }
}
