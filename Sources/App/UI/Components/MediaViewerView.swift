import AVFoundation
import AVKit
import ImageIO
import SwiftUI
import UIKit

struct MessageAttachmentPreview: View {
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.colorScheme) private var colorScheme

    let attachment: TgAttachment
    var isOutgoing: Bool = false
    var onOpen: (() -> Void)?
    var onPremiumSticker: ((TgAttachment) -> Void)?
    @State private var inlinePlayer: AVPlayer?
    @State private var isInlinePlaying = false

    private var mediaBackdrop: Color {
        appearance.incomingBubble(colorScheme: colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.72)
    }

    private var stickerLikeBackdrop: Color {
        isOutgoing
            ? appearance.outgoingBubble(colorScheme: colorScheme)
            : appearance.incomingBubble(colorScheme: colorScheme)
    }

    var body: some View {
        switch attachment.kind {
        case .photo:
            photoPreview
        case .video:
            videoPreview(isRound: false)
        case .videoNote:
            videoPreview(isRound: true)
        case .animation:
            videoPreview(isRound: false)
        case .sticker, .gift:
            stickerLikePreview
        case .voice:
            InlineVoicePlayer(attachment: attachment, onOpen: onOpen)
        case .document:
            documentPreview
        }
    }

    private var photoPreview: some View {
        Button {
            onOpen?()
        } label: {
            ZStack {
                CachedLocalImage(path: attachment.localPath, contentMode: .fill) {
                    loadingPlaceholder(systemImage: "photo", title: "Фото загружается")
                }
                .scaledToFill()
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if attachment.localURL == nil {
                    ProgressView()
                        .tint(.white)
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(attachment.localURL == nil)
    }

    private func videoPreview(isRound: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isRound {
                    videoPreviewContent(title: "Кружок загружается")
                        .frame(width: 170, height: 170)
                        .clipShape(Circle())
                } else {
                    videoPreviewContent(title: attachment.kind == .animation ? "GIF загружается" : "Видео загружается")
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleInlinePlayback)

            if attachment.localURL != nil {
                Button {
                    onOpen?()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.36))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear {
            inlinePlayer?.pause()
            isInlinePlaying = false
        }
    }

    private func videoPreviewContent(title: String) -> some View {
        ZStack {
            if isInlinePlaying, let inlinePlayer {
                VideoPlayer(player: inlinePlayer)
            } else {
                VideoThumbnailView(url: attachment.localURL)
            }

            if !isInlinePlaying {
                Image(systemName: "play.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.black.opacity(0.36))
                    .clipShape(Circle())
            }

            if attachment.localURL == nil {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(12)
            }
        }
    }

    private func toggleInlinePlayback() {
        guard let url = attachment.localURL else { return }
        if inlinePlayer == nil {
            inlinePlayer = AVPlayer(url: url)
        }

        if isInlinePlaying {
            inlinePlayer?.pause()
        } else {
            inlinePlayer?.play()
        }
        isInlinePlaying.toggle()
    }

    private var documentPreview: some View {
        Button {
            onOpen?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 34, height: 34)
                    .background(AppColors.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName?.isEmpty == false ? attachment.fileName ?? "Файл" : "Файл")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let size = attachment.size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .buttonStyle(.plain)
    }

    private var stickerLikePreview: some View {
        Button {
            if attachment.isPremiumSticker {
                onPremiumSticker?(attachment)
            } else {
                onOpen?()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(stickerLikeBackdrop)

                StickerMediaView(
                    displayPath: attachment.localPath,
                    animationPath: attachment.animationPath,
                    isAnimated: attachment.isAnimatedSticker
                )
                .padding(8)

                if attachment.isPremiumSticker {
                    VStack {
                        HStack {
                            Spacer()
                            PremiumBadgeView(size: 18)
                                .padding(8)
                        }
                        Spacer()
                    }
                }

                if attachment.localPath == nil && attachment.animationPath == nil {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.secondary)
                        Text(attachment.kind == .gift
                             ? AppText.tr("Подарок загружается", "Gift loading")
                             : AppText.tr("Стикер загружается", "Sticker loading"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: attachment.kind == .gift ? 168 : 150, height: attachment.kind == .gift ? 168 : 150)
        }
        .buttonStyle(.plain)
    }

    private func loadingPlaceholder(systemImage: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(mediaBackdrop.opacity(0.5))
    }
}

struct MediaViewerView: View {
    let attachments: [TgAttachment]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int
    @State private var players: [Int: AVPlayer] = [:]
    @State private var saveConfirmationShown = false

    init(attachments: [TgAttachment], startIndex: Int) {
        self.attachments = attachments
        self.startIndex = max(0, min(startIndex, max(0, attachments.count - 1)))
        _selection = State(initialValue: self.startIndex)
    }

    init(attachment: TgAttachment) {
        self.init(attachments: [attachment], startIndex: 0)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                    MediaViewerPage(attachment: attachment, player: player(for: index))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: attachments.count > 1 ? .automatic : .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                HStack {
                    if let currentURL = currentLocalURL {
                        HStack(spacing: 14) {
                            ShareLink(item: currentURL) {
                                mediaToolbarLabel(
                                    title: AppText.tr("Поделиться", "Share"),
                                    systemImage: "square.and.arrow.up"
                                )
                            }

                            Button {
                                saveCurrentToLibrary()
                            } label: {
                                mediaToolbarLabel(
                                    title: AppText.tr("Сохранить", "Save"),
                                    systemImage: "arrow.down.circle.fill"
                                )
                            }
                        }
                    }
                    Spacer()
                    mediaCloseButton {
                        dismiss()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                Spacer()
            }
        }
        .onDisappear { pauseAll() }
        .alert(AppText.tr("Сохранено", "Saved"), isPresented: $saveConfirmationShown) {
            Button(AppText.tr("OK", "OK"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func mediaToolbarLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(minWidth: 72, minHeight: 56)
        .background(Color.black.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func mediaCloseButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.42))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppText.tr("Закрыть", "Close"))
    }

    private func player(for index: Int) -> AVPlayer? {
        let attachment = attachments[index]
        guard attachment.kind == .video || attachment.kind == .animation || attachment.kind == .videoNote else {
            return nil
        }
        guard let path = attachment.localPath, !path.isEmpty else { return nil }

        if let existing = players[index] {
            return existing
        }
        let player = AVPlayer(url: URL(fileURLWithPath: path))
        players[index] = player
        return player
    }

    private func pauseAll() {
        for (_, player) in players {
            player.pause()
        }
    }

    private var currentAttachment: TgAttachment? {
        guard attachments.indices.contains(selection) else { return nil }
        return attachments[selection]
    }

    private var currentLocalURL: URL? {
        currentAttachment?.localURL
    }

    private func saveCurrentToLibrary() {
        guard let attachment = currentAttachment, let url = attachment.localURL else { return }
        switch attachment.kind {
        case .photo, .sticker, .gift:
            if let image = UIImage(contentsOfFile: url.path) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                saveConfirmationShown = true
            }
        case .video, .videoNote, .animation:
            UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
            saveConfirmationShown = true
        default:
            break
        }
    }
}

private struct MediaViewerPage: View {
    let attachment: TgAttachment
    let player: AVPlayer?

    var body: some View {
        switch attachment.kind {
        case .photo:
            if let path = attachment.localPath {
                FullscreenImageContent(imagePath: path)
            } else {
                MissingMediaView(title: "Фото еще загружается")
            }
        case .video:
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                MissingMediaView(title: "Видео еще загружается")
            }
        case .animation:
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if let path = attachment.localPath {
                FullscreenImageContent(imagePath: path)
            } else {
                MissingMediaView(title: "GIF еще загружается")
            }
        case .videoNote:
            if let player {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height) * 0.74
                    VideoPlayer(player: player)
                        .frame(width: side, height: side)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                MissingMediaView(title: "Кружок еще загружается")
            }
        case .voice:
            FullscreenVoicePlayer(attachment: attachment)
        case .sticker:
            if let path = attachment.localPath {
                FullscreenImageContent(imagePath: path)
            } else {
                MissingMediaView(title: "Стикер еще загружается")
            }
        case .gift:
            if let path = attachment.localPath {
                FullscreenImageContent(imagePath: path)
            } else {
                MissingMediaView(title: AppText.tr("Подарок еще загружается", "Gift is still loading"))
            }
        case .document:
            DocumentFullscreenView(attachment: attachment)
        }
    }
}

struct FullscreenImageViewer: View {
    let imagePath: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            viewerBackground
            FullscreenImageContent(imagePath: imagePath)
                .offset(dragOffset)
                .scaleEffect(dragScale)

            FullscreenCloseButton {
                dismiss()
            }
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
        .simultaneousGesture(dragToCloseGesture)
        .accessibilityLabel(title)
    }

    private var viewerBackground: some View {
        Color.black
            .opacity(max(0.35, 1 - abs(dragOffset.height) / 420))
            .ignoresSafeArea()
            .background(.ultraThinMaterial)
    }

    private var dragScale: CGFloat {
        max(0.86, 1 - abs(dragOffset.height) / 900)
    }

    private var dragToCloseGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 220 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = .zero
                    }
                }
            }
    }
}

private struct FullscreenImageContent: View {
    let imagePath: String
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1

    var body: some View {
        Group {
            if let image = LocalImageCache.shared.image(path: imagePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(committedScale * value, 1), 4)
                            }
                            .onEnded { _ in
                                committedScale = scale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            scale = scale > 1 ? 1 : 2.2
                            committedScale = scale
                        }
                    }
                    .padding(8)
            } else {
                MissingMediaView(title: "Не удалось открыть изображение")
            }
        }
    }
}

struct FullscreenAvatarOverlay: View {
    let imagePaths: [String]
    let title: String
    let namespace: Namespace.ID
    let id: String
    @Binding var isPresented: Bool
    @State private var selection = 0
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1

    init(
        imagePath: String,
        imagePaths: [String] = [],
        title: String,
        namespace: Namespace.ID,
        id: String,
        isPresented: Binding<Bool>
    ) {
        let merged = imagePaths.isEmpty ? [imagePath] : imagePaths
        self.imagePaths = merged
        self.title = title
        self.namespace = namespace
        self.id = id
        self._isPresented = isPresented
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .opacity(max(0.28, 0.92 - abs(dragOffset.height) / 430))
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture { close() }

            TabView(selection: $selection) {
                ForEach(Array(imagePaths.enumerated()), id: \.offset) { index, path in
                    Group {
                        if let image = LocalImageCache.shared.image(path: path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            MissingMediaView(title: AppText.tr("Не удалось открыть", "Could not open"))
                        }
                    }
                    .tag(index)
                    .padding(18)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: imagePaths.count > 1 ? .automatic : .never))
            .task(id: imagePaths) {
                for path in imagePaths {
                    _ = LocalImageCache.shared.image(path: path)
                }
            }
            .offset(dragOffset)
            .scaleEffect(scale * max(0.84, 1 - abs(dragOffset.height) / 820))
            .gesture(zoomGesture)
            .simultaneousGesture(dragGesture)
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    scale = scale > 1 ? 1 : 2.2
                    committedScale = scale
                }
            }
            .accessibilityLabel(title)

            VStack {
                HStack {
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.42))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppText.tr("Закрыть", "Close"))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                if imagePaths.count > 1 {
                    Text("\(selection + 1) / \(imagePaths.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 6)
                }

                Spacer()
            }
        }
        .transition(.opacity)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                if value.translation.height > 110 || value.predictedEndTranslation.height > 220 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(committedScale * value, 1), 4)
            }
            .onEnded { _ in
                committedScale = scale
            }
    }

    private func close() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            isPresented = false
            dragOffset = .zero
        }
    }
}

private struct FullscreenVoicePlayer: View {
    let attachment: TgAttachment

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 92))
                .foregroundStyle(AppColors.accent)

            VStack(spacing: 6) {
                Text("Голосовое сообщение")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                if let size = attachment.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            InlineVoicePlayer(attachment: attachment, expanded: true)
                .frame(maxWidth: 320)
        }
        .padding(24)
    }
}

private struct DocumentFullscreenView: View {
    let attachment: TgAttachment

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.fill")
                .font(.system(size: 76))
                .foregroundStyle(AppColors.accent)

            VStack(spacing: 5) {
                Text(attachment.fileName ?? "Файл")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if let size = attachment.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            if let url = attachment.localURL {
                ShareLink(item: url) {
                    Label("Open", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                MissingMediaView(title: "Файл еще загружается")
            }
        }
        .padding(24)
    }
}

private struct InlineVoicePlayer: View {
    let attachment: TgAttachment
    var expanded: Bool = false
    var onOpen: (() -> Void)?
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: expanded ? 44 : 34, height: expanded ? 44 : 34)
                    .background(attachment.localURL == nil ? Color.secondary.opacity(0.45) : AppColors.accent)
                    .clipShape(Circle())
            }
            .disabled(attachment.localURL == nil)

            VStack(alignment: .leading, spacing: 6) {
                Text("Голосовое")
                    .font(expanded ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(expanded ? .white : .primary)

                VoiceWaveform()
                    .foregroundStyle(attachment.localURL == nil ? Color.secondary.opacity(0.45) : AppColors.accent)
                    .opacity(isPlaying ? 1 : 0.72)
                    .animation(.easeInOut(duration: 0.22), value: isPlaying)
            }

            Spacer(minLength: 0)

            if let onOpen, attachment.localURL != nil {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(expanded ? 14 : 10)
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
    }

    private func togglePlayback() {
        guard let url = attachment.localURL else { return }
        if player == nil {
            player = AVPlayer(url: url)
        }

        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
}

private struct VoiceWaveform: View {
    private let heights: [CGFloat] = [8, 16, 11, 20, 13, 24, 10, 18, 28, 14, 22, 12, 18, 9, 24, 15, 20, 11]
    @State private var animated = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .frame(width: 3, height: animated ? heights[index] : max(6, heights[index] * 0.55))
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index % 5) * 0.05),
                        value: animated
                    )
            }
        }
        .frame(height: 30)
        .onAppear {
            animated = true
        }
    }
}

struct VideoThumbnailView: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.black.opacity(0.22), AppColors.accent.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .task(id: url?.path) {
            guard let url else { return }
            image = await makeThumbnail(url: url)
        }
    }

    private func makeThumbnail(url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: 0.25, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
}

private struct MissingMediaView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(24)
    }
}

private struct FullscreenCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .buttonStyle(.bordered)
        .clipShape(Circle())
        .controlSize(.large)
        .tint(.white)
    }
}

extension TgAttachment {
    var localURL: URL? {
        guard let localPath, !localPath.isEmpty, FileManager.default.fileExists(atPath: localPath) else {
            return nil
        }
        return URL(fileURLWithPath: localPath)
    }

    var localImage: UIImage? {
        guard let localPath, !localPath.isEmpty else { return nil }
        return LocalImageCache.shared.image(path: localPath)
    }
}

struct CachedLocalImage<Placeholder: View>: View {
    let path: String?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: path) {
            guard let path, !path.isEmpty else {
                image = nil
                return
            }
            let loaded = await Task.detached(priority: .utility) {
                LocalImageCache.shared.image(path: path, maxPixelSize: 640)
            }.value
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

final class LocalImageCache {
    static let shared = LocalImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 72
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(path: String, maxPixelSize: CGFloat? = nil) -> UIImage? {
        let cacheKey = maxPixelSize.map { "\(path)|\(Int($0))" } ?? path
        let key = cacheKey as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard var image = UIImage(contentsOfFile: path) ?? Self.decodeImageIO(path: path) else {
            return nil
        }

        if let maxPixelSize {
            image = downscaled(image, maxPixelSize: maxPixelSize) ?? image
        }

        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    private static func decodeImageIO(path: String) -> UIImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func downscaled(_ image: UIImage, maxPixelSize: CGFloat) -> UIImage? {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxPixelSize, longest > 0 else { return image }

        let scale = maxPixelSize / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
