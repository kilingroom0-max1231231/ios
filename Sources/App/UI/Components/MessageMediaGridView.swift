import SwiftUI
import UIKit

struct MessageMediaGridView: View {
    let attachments: [TgAttachment]
    let maxWidth: CGFloat
    var onOpen: (TgAttachment) -> Void

    private let spacing: CGFloat = 2

    var body: some View {
        Group {
            switch attachments.count {
            case 0:
                EmptyView()
            case 1:
                mediaCell(attachments[0], width: maxWidth, height: singleHeight)
            case 2:
                HStack(spacing: spacing) {
                    mediaCell(attachments[0], width: halfWidth, height: pairHeight)
                    mediaCell(attachments[1], width: halfWidth, height: pairHeight)
                }
            case 3:
                HStack(spacing: spacing) {
                    mediaCell(attachments[0], width: largeWidth, height: tripleHeight)
                    VStack(spacing: spacing) {
                        mediaCell(attachments[1], width: smallWidth, height: smallHeight)
                        mediaCell(attachments[2], width: smallWidth, height: smallHeight)
                    }
                }
            default:
                gridMany
            }
        }
        .frame(width: maxWidth, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var gridMany: some View {
        let visible = Array(attachments.prefix(4))
        let columns = [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)]
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, attachment in
                ZStack {
                    mediaCell(attachment, width: halfWidth, height: pairHeight)
                    if index == 3, attachments.count > 4 {
                        Color.black.opacity(0.45)
                        Text("+\(attachments.count - 3)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private var halfWidth: CGFloat { (maxWidth - spacing) / 2 }
    private var largeWidth: CGFloat { maxWidth * 0.62 }
    private var smallWidth: CGFloat { maxWidth - largeWidth - spacing }
    private var singleHeight: CGFloat { min(maxWidth * 0.72, 260) }
    private var pairHeight: CGFloat { min(maxWidth * 0.5, 200) }
    private var tripleHeight: CGFloat { pairHeight * 2 + spacing }
    private var smallHeight: CGFloat { (tripleHeight - spacing) / 2 }

    @ViewBuilder
    private func mediaCell(_ attachment: TgAttachment, width: CGFloat, height: CGFloat) -> some View {
        Button {
            onOpen(attachment)
        } label: {
            MessageMediaThumbnail(attachment: attachment)
                .frame(width: width, height: height)
                .clipped()
        }
        .buttonStyle(.plain)
        .disabled(attachment.localURL == nil && attachment.localImage == nil)
    }
}

struct MessageMediaThumbnail: View {
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.colorScheme) private var colorScheme

    let attachment: TgAttachment

    private var mediaBackdrop: Color {
        appearance.incomingBubble(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.72)
    }

    var body: some View {
        ZStack {
            thumbnailContent

            if attachment.kind == .video || attachment.kind == .animation {
                mediaBackdrop.opacity(0.35)
                Image(systemName: attachment.kind == .animation ? "play.rectangle.fill" : "play.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            if attachment.localURL == nil && attachment.localImage == nil {
                ProgressView()
                    .tint(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(mediaBackdrop.opacity(0.4))
            }
        }
        .background(mediaBackdrop.opacity(attachment.kind == .sticker ? 0.25 : 0.45))
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        switch attachment.kind {
        case .photo:
            if let image = attachment.localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder("photo")
            }
        case .video, .animation:
            VideoThumbnailView(url: attachment.localURL)
        case .sticker, .gift:
            if let image = attachment.localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                placeholder(attachment.kind == .gift ? "gift.fill" : "face.smiling")
            }
        default:
            placeholder("photo")
        }
    }

    private func placeholder(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(mediaBackdrop.opacity(0.5))
    }
}
