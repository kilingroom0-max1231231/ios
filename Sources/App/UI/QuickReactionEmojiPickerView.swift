import SwiftUI

struct QuickReactionEmojiPickerView: View {
    @ObservedObject var appSettings: AppSettingsStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AppSettingsStore.quickReactionEmojiOptions, id: \.self) { emoji in
                    Button {
                        appSettings.doubleTapQuickReactionEmoji = emoji
                        appSettings.reactionHaptic(.medium)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 32))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                appSettings.doubleTapQuickReactionEmoji == emoji
                                    ? AppColors.accent.opacity(0.2)
                                    : Color(.secondarySystemBackground)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        appSettings.doubleTapQuickReactionEmoji == emoji
                                            ? AppColors.accent
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Быстрая реакция", "Quick reaction"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
