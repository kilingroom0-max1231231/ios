import PhotosUI
import SwiftUI
import UIKit

struct AppearanceSettingsView: View {
    @ObservedObject var appearance: AppAppearanceStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var wallpaperItem: PhotosPickerItem?

    var body: some View {
        List {
            livePreviewSection

            Section(AppText.tr("Фоны", "Backgrounds")) {
                Picker(AppText.tr("Список чатов", "Chat list"), selection: $appearance.chatListStyle) {
                    ForEach(ChatListBackgroundStyle.allCases) { style in
                        Text(AppText.tr(style.titleRu, style.titleEn)).tag(style)
                    }
                }

                Picker(AppText.tr("Экран чата", "Chat screen"), selection: $appearance.chatStyle) {
                    ForEach(ChatBackgroundStyle.allCases) { style in
                        Text(AppText.tr(style.titleRu, style.titleEn)).tag(style)
                    }
                }
                .disabled(appearance.chatWallpaperPath != nil)
            }

            Section(AppText.tr("Обои чата", "Chat wallpaper")) {
                PhotosPicker(selection: $wallpaperItem, matching: .images, photoLibrary: .shared()) {
                    Label(AppText.tr("Выбрать из галереи", "Choose from gallery"), systemImage: "photo.on.rectangle.angled")
                }

                if appearance.chatWallpaperPath != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppText.tr("Прозрачность обоев", "Wallpaper opacity"))
                            .font(.subheadline)
                        Slider(value: $appearance.wallpaperOpacity, in: 0.15...1.0)
                    }

                    Button(role: .destructive) {
                        appearance.clearWallpaper()
                    } label: {
                        Label(AppText.tr("Убрать обои", "Remove wallpaper"), systemImage: "trash")
                    }
                }
            }

            Section(AppText.tr("Акцент и пузыри", "Accent & bubbles")) {
                Picker(AppText.tr("Акцентный цвет", "Accent color"), selection: $appearance.accentStyle) {
                    ForEach(AccentColorStyle.allCases) { style in
                        HStack(spacing: 8) {
                            Circle().fill(style.color).frame(width: 14, height: 14)
                            Text(accentTitle(style))
                        }
                        .tag(style)
                    }
                }

                Picker(AppText.tr("Стиль пузырей", "Bubble style"), selection: $appearance.bubbleStyle) {
                    ForEach(BubbleColorStyle.allCases) { style in
                        Text(AppText.tr(style.titleRu, style.titleEn)).tag(style)
                    }
                }

                Toggle(AppText.tr("Компактные пузыри", "Compact bubbles"), isOn: $appearance.compactBubbles)
            }

            Section(AppText.tr("Текст", "Text")) {
                Picker(AppText.tr("Размер сообщений", "Message size"), selection: $appearance.messageFontScale) {
                    ForEach(MessageFontScale.allCases) { scale in
                        Text(AppText.tr(scale.titleRu, scale.titleEn)).tag(scale)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    appearance.resetToDefaults()
                } label: {
                    Label(AppText.tr("Сбросить оформление", "Reset appearance"), systemImage: "arrow.counterclockwise")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AppText.tr("Оформление", "Appearance"))
        .navigationBarTitleDisplayMode(.inline)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .onChange(of: wallpaperItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    try? appearance.setWallpaper(from: image)
                }
                wallpaperItem = nil
            }
        }
    }

    private var livePreviewSection: some View {
        Section(AppText.tr("Превью", "Preview")) {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appearance.chatListColor(colorScheme: colorScheme))
                        .frame(height: 72)
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(AppText.tr("Чаты", "Chats"))
                                    .font(.caption.weight(.bold))
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(height: 28)
                                    .overlay(alignment: .leading) {
                                        Text("Alex")
                                            .font(.caption2)
                                            .padding(.leading, 8)
                                    }
                            }
                            .padding(10)
                        }

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appearance.chatColor(colorScheme: colorScheme))
                        .frame(height: 72)
                        .overlay {
                            if let image = appearance.chatWallpaperImage() {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .opacity(appearance.wallpaperOpacity)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(AppText.tr("Привет!", "Hi!"))
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(appearance.incomingBubble(colorScheme: colorScheme))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text("OK")
                                    .font(.caption2)
                                    .foregroundStyle(appearance.outgoingText(colorScheme: colorScheme))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(appearance.outgoingBubble(colorScheme: colorScheme))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .padding(8)
                        }
                }

                HStack(spacing: 8) {
                    ForEach(AccentColorStyle.allCases) { style in
                        Circle()
                            .fill(style.color)
                            .frame(width: 22, height: 22)
                            .overlay {
                                if appearance.accentStyle == style {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .onTapGesture { appearance.accentStyle = style }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func accentTitle(_ style: AccentColorStyle) -> String {
        switch style {
        case .telegramBlue: return AppText.tr("Синий", "Blue")
        case .teal: return AppText.tr("Бирюза", "Teal")
        case .purple: return AppText.tr("Фиолетовый", "Purple")
        case .orange: return AppText.tr("Оранжевый", "Orange")
        case .green: return AppText.tr("Зелёный", "Green")
        case .red: return AppText.tr("Красный", "Red")
        case .pink: return AppText.tr("Розовый", "Pink")
        }
    }
}
