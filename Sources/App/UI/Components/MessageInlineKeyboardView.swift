import SwiftUI

struct MessageInlineKeyboardView: View {
    let rows: [TgInlineKeyboardRow]
    var outgoing: Bool = false
    let onTap: (TgInlineKeyboardButton) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows) { row in
                HStack(spacing: 4) {
                    ForEach(row.buttons) { button in
                        Button {
                            onTap(button)
                        } label: {
                            Text(button.text)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppColors.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(.secondarySystemBackground).opacity(outgoing ? 0.85 : 1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct BotReplyKeyboardView: View {
    let markup: TgReplyKeyboardMarkup
    let onTap: (TgReplyKeyboardButton) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(markup.rows) { row in
                HStack(spacing: 6) {
                    ForEach(row.buttons) { button in
                        Button {
                            onTap(button)
                        } label: {
                            Text(button.text)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
