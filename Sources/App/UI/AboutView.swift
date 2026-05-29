import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColors.accent, AppColors.accent.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("Telegram User Client")
                        .font(.title2.weight(.bold))

                    Text(AppText.tr(
                        "Неофициальный клиент Telegram на TDLib с локальным кэшем и кастомным интерфейсом.",
                        "Unofficial Telegram client powered by TDLib with local cache and a custom interface."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section(AppText.tr("Версия", "Version")) {
                infoRow(icon: "number.circle", title: AppText.tr("Сборка", "Build"), value: appVersion)
                infoRow(icon: "cpu", title: AppText.tr("Движок", "Engine"), value: "TDLib")
                infoRow(icon: "iphone", title: AppText.tr("Платформа", "Platform"), value: "iOS 16+")
            }

            Section(AppText.tr("Возможности", "Features")) {
                featureRow("bubble.left.and.bubble.right", AppText.tr("Чаты и сообщения", "Chats & messages"))
                featureRow("person.2.fill", AppText.tr("Контакты и синхронизация", "Contacts & sync"))
                featureRow("circle.dashed", AppText.tr("Истории", "Stories"))
                featureRow("gift.fill", AppText.tr("Подарки", "Gifts"))
                featureRow("lock.shield", AppText.tr("Приватность TDLib", "TDLib privacy"))
                featureRow("paintpalette.fill", AppText.tr("Темы и оформление", "Themes & appearance"))
            }

            Section(AppText.tr("Команда", "Team")) {
                infoRow(icon: "hammer.fill", title: AppText.tr("Система / TDLib", "System / TDLib"), value: "masezev")
                infoRow(icon: "paintbrush.fill", title: AppText.tr("Интерфейс", "Interface"), value: "masezev")
            }

            Section(AppText.tr("Ссылки", "Links")) {
                Button {
                    if let url = URL(string: "https://telegram.org") {
                        openURL(url)
                    }
                } label: {
                    linkRow(icon: "paperplane.fill", title: "Telegram", subtitle: "telegram.org")
                }

                Button {
                    if let url = URL(string: "https://core.telegram.org/tdlib") {
                        openURL(url)
                    }
                } label: {
                    linkRow(icon: "doc.text.fill", title: "TDLib", subtitle: "core.telegram.org/tdlib")
                }
            }

            Section {
                Text(AppText.tr(
                    "Проект не связан с Telegram FZ-LLC. Используйте официальные API-ключи с my.telegram.org.",
                    "This project is not affiliated with Telegram FZ-LLC. Use official API keys from my.telegram.org."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("О приложении", "About"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func featureRow(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)
            Text(title)
        }
    }

    private func linkRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}
