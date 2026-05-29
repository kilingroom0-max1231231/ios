import AVKit
import SwiftUI

struct StoryThumbView: View {
    let story: TgStoryItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                CachedLocalImage(path: story.previewPath ?? story.mediaPath, contentMode: .fill) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .overlay {
                            if story.isVideo {
                                Image(systemName: "play.fill")
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                                    .tint(.secondary)
                            }
                        }
                }
            }
            .frame(width: 92, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if story.isVideo {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(6)
            }

            if story.isViewed {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 2)
                    .frame(width: 92, height: 128)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [AppColors.accent, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 92, height: 128)
            }
        }
    }
}

struct StoryViewerView: View {
    let stories: [TgStoryItem]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(stories: [TgStoryItem], startIndex: Int) {
        self.stories = stories
        self.startIndex = startIndex
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(stories.enumerated()), id: \.element.id) { offset, story in
                    StoryMediaPage(story: story)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding()
                Spacer()
            }
        }
    }
}

private struct StoryMediaPage: View {
    let story: TgStoryItem
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if story.isVideo, let path = story.mediaPath, !path.isEmpty {
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ProgressView()
                        .tint(.white)
                }
            } else if story.mediaPath != nil || story.previewPath != nil {
                CachedLocalImage(path: story.mediaPath ?? story.previewPath, contentMode: .fit) {
                    ProgressView()
                        .tint(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
            }

            if !story.caption.isEmpty {
                VStack {
                    Spacer()
                    Text(story.caption)
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.45))
                }
            }
        }
        .onAppear {
            startPlaybackIfNeeded()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func startPlaybackIfNeeded() {
        guard story.isVideo,
              let path = story.mediaPath,
              !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            newPlayer.seek(to: .zero)
            newPlayer.play()
        }
        player = newPlayer
        newPlayer.play()
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
    }
}
