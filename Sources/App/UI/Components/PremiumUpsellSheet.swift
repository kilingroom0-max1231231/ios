import SwiftUI

struct PremiumUpsellContext: Identifiable, Equatable {
    let id = UUID()
    let previewPath: String?
    let previewAnimationPath: String?
    let headlineText: String?
    let title: String
    let explanation: String

    static func premiumSticker(attachment: TgAttachment, setTitle: String? = nil) -> PremiumUpsellContext {
        let setName = setTitle ?? AppText.tr("Premium", "Premium")
        return PremiumUpsellContext(
            previewPath: attachment.localPath,
            previewAnimationPath: attachment.animationPath,
            headlineText: nil,
            title: AppText.tr(
                "Это стикер из набора «\(setName)»",
                "This sticker is from the “\(setName)” set"
            ),
            explanation: AppText.tr(
                "Premium-стикеры доступны только с подпиской Telegram Premium. Другие преимущества подписки:",
                "Premium stickers are available only with Telegram Premium. Other subscription benefits:"
            )
        )
    }

    static func premiumUser(displayName: String, badgePath: String?) -> PremiumUpsellContext {
        PremiumUpsellContext(
            previewPath: badgePath,
            previewAnimationPath: nil,
            headlineText: nil,
            title: AppText.tr(
                "\(displayName) — подписчик Telegram Premium",
                "\(displayName) is a Telegram Premium subscriber"
            ),
            explanation: AppText.tr(
                "Значок Premium показывает, что у пользователя активна подписка. Преимущества Telegram Premium:",
                "The Premium badge means this user has an active subscription. Telegram Premium benefits:"
            )
        )
    }

    static func emojiStatus(headline: String, userName: String, setName: String) -> PremiumUpsellContext {
        PremiumUpsellContext(
            previewPath: nil,
            previewAnimationPath: nil,
            headlineText: headline,
            title: AppText.tr(
                "Это статус пользователя \(userName) из набора \(setName)",
                "This is \(userName)'s status from the \(setName) set"
            ),
            explanation: AppText.tr(
                "Эмодзи-статусы доступны только с подпиской Telegram Premium. Другие преимущества подписки:",
                "Emoji statuses are available only with Telegram Premium. Other subscription benefits:"
            )
        )
    }
}

struct PremiumUpsellSheet: View {
    let context: PremiumUpsellContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previewBlock
                    textBlock
                    featuresList
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                subscribeButton
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(.ultraThinMaterial)
            }
            .navigationTitle(AppText.tr("Telegram Premium", "Telegram Premium"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var previewBlock: some View {
        if let headline = context.headlineText, !headline.isEmpty {
            Text(headline)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else if context.previewPath != nil || context.previewAnimationPath != nil {
            StickerMediaView(
                displayPath: context.previewPath,
                animationPath: context.previewAnimationPath,
                isAnimated: context.previewAnimationPath.map(StickerMediaView.isPlayableVideoPath) ?? false
            )
            .frame(width: 160, height: 160)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(context.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(context.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featuresList: some View {
        VStack(spacing: 0) {
            ForEach(PremiumFeature.all) { feature in
                PremiumFeatureRow(feature: feature)
                if feature.id != PremiumFeature.all.last?.id {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var subscribeButton: some View {
        Button {
            if let url = URL(string: "https://t.me/premium") {
                openURL(url)
            }
        } label: {
            Text(AppText.tr("Подключить Telegram Premium", "Get Telegram Premium"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(premiumGradient, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var premiumGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.35, green: 0.72, blue: 1.0),
                Color(red: 0.52, green: 0.55, blue: 0.98),
                Color(red: 0.88, green: 0.58, blue: 0.82)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct PremiumFeature: Identifiable {
    let id: String
    let icon: String
    let iconColors: [Color]
    let title: String
    let subtitle: String
    let isNew: Bool

    static let all: [PremiumFeature] = [
        PremiumFeature(
            id: "stories",
            icon: "circle.dashed",
            iconColors: [.orange, .pink],
            title: AppText.tr("Истории", "Stories"),
            subtitle: AppText.tr(
                "Неограниченный постинг, приоритетные просмотры, невидимый режим и многое другое.",
                "Unlimited posting, priority views, stealth mode, and more."
            ),
            isNew: false
        ),
        PremiumFeature(
            id: "storage",
            icon: "doc.fill",
            iconColors: [.orange, .red],
            title: AppText.tr("Безлимитное хранилище", "Unlimited Storage"),
            subtitle: AppText.tr(
                "Загрузка файлов до 4 ГБ и неограниченное место в облаке.",
                "Upload files up to 4 GB and unlimited cloud storage."
            ),
            isNew: false
        ),
        PremiumFeature(
            id: "limits",
            icon: "xmark",
            iconColors: [.orange, .yellow],
            title: AppText.tr("Удвоенные лимиты", "Doubled Limits"),
            subtitle: AppText.tr(
                "1000 каналов, 30 папок, 10 закреплённых чатов и многое другое.",
                "1000 channels, 30 folders, 10 pinned chats, and more."
            ),
            isNew: false
        ),
        PremiumFeature(
            id: "stickers",
            icon: "face.smiling",
            iconColors: [.purple, .pink],
            title: AppText.tr("Эксклюзивные стикеры", "Exclusive Stickers"),
            subtitle: AppText.tr(
                "Крупные стикеры с уникальной анимацией. Коллекция регулярно обновляется.",
                "Large stickers with unique animation. The collection is regularly updated."
            ),
            isNew: false
        ),
        PremiumFeature(
            id: "emoji",
            icon: "hand.wave.fill",
            iconColors: [.purple, .indigo],
            title: AppText.tr("Эмодзи-статусы", "Emoji Statuses"),
            subtitle: AppText.tr(
                "Установите эмодзи рядом с именем, чтобы показать настроение.",
                "Set an emoji next to your name to show how you feel."
            ),
            isNew: false
        ),
        PremiumFeature(
            id: "reactions",
            icon: "heart.fill",
            iconColors: [.pink, .red],
            title: AppText.tr("Неограниченные реакции", "Unlimited Reactions"),
            subtitle: AppText.tr(
                "Несколько реакций на сообщение и неограниченный выбор эмодзи.",
                "Multiple reactions per message and unlimited emoji choice."
            ),
            isNew: false
        ),
        PremiumFeature(
            id: "download",
            icon: "speedometer",
            iconColors: [.pink, .orange],
            title: AppText.tr("Быстрая загрузка", "Faster Downloads"),
            subtitle: AppText.tr(
                "Без ограничений скорости при загрузке медиа и документов.",
                "No speed limits when downloading media and documents."
            ),
            isNew: false
        ),
        PremiumFeature(
            id: "translate",
            icon: "character.bubble",
            iconColors: [.pink, .purple],
            title: AppText.tr("Перевод в реальном времени", "Real-time Translation"),
            subtitle: AppText.tr(
                "Динамический перевод чатов и каналов.",
                "Dynamic translation of chats and channels."
            ),
            isNew: false
        ),
        PremiumFeature(
            id: "ai",
            icon: "sparkles",
            iconColors: [.teal, .blue],
            title: AppText.tr("ИИ-функции", "AI Features"),
            subtitle: AppText.tr(
                "Перевод, изменение стиля и другие инструменты.",
                "Translation, style changes, and other tools."
            ),
            isNew: true
        )
    ]
}

private struct PremiumFeatureRow: View {
    let feature: PremiumFeature

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: feature.iconColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: feature.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(feature.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if feature.isNew {
                        Text(AppText.tr("НОВОЕ", "NEW"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green, in: Capsule())
                    }
                }
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
