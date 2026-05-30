import SwiftUI

struct EditMessageAutoDeleteView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    private struct Option: Identifiable {
        let id: Int
        let title: String
        let seconds: Int
    }

    private var options: [Option] {
        [
            Option(id: 0, title: AppText.tr("Выкл.", "Off"), seconds: 0),
            Option(id: 1, title: AppText.tr("1 день", "1 day"), seconds: 86_400),
            Option(id: 2, title: AppText.tr("1 неделя", "1 week"), seconds: 604_800),
            Option(id: 3, title: AppText.tr("1 месяц", "1 month"), seconds: 2_592_000)
        ]
    }

    var body: some View {
        List {
            Section {
                ForEach(options) { option in
                    Button {
                        guard vm.securitySnapshot.messageAutoDeleteSeconds != option.seconds else { return }
                        isSaving = true
                        Task {
                            await vm.updateMessageAutoDelete(seconds: option.seconds)
                            isSaving = false
                            if vm.status.isEmpty { dismiss() }
                        }
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if vm.securitySnapshot.messageAutoDeleteSeconds == option.seconds {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                    .disabled(isSaving)
                }
            } footer: {
                Text(AppText.tr(
                    "Новые сообщения в личных чатах будут автоматически удаляться через указанный срок.",
                    "New messages in private chats will auto-delete after this period."
                ))
            }

            if !vm.status.isEmpty {
                Section {
                    Text(vm.status)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Автоудаление", "Auto-delete"))
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
    }
}

struct EditAccountDeletionView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    private struct Option: Identifiable {
        let id: Int
        let title: String
        let days: Int
    }

    private var options: [Option] {
        [
            Option(id: 1, title: AppText.tr("1 месяц", "1 month"), days: 30),
            Option(id: 3, title: AppText.tr("3 месяца", "3 months"), days: 90),
            Option(id: 6, title: AppText.tr("6 месяцев", "6 months"), days: 180),
            Option(id: 12, title: AppText.tr("12 месяцев", "12 months"), days: 365),
            Option(id: 18, title: AppText.tr("18 месяцев", "18 months"), days: 548)
        ]
    }

    var body: some View {
        List {
            Section {
                ForEach(options) { option in
                    Button {
                        guard vm.securitySnapshot.accountDeleteDays != option.days else { return }
                        isSaving = true
                        Task {
                            await vm.updateAccountDeletionPeriod(days: option.days)
                            isSaving = false
                            if vm.status.isEmpty { dismiss() }
                        }
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if vm.securitySnapshot.accountDeleteDays == option.days {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                    .disabled(isSaving)
                }
            } footer: {
                Text(AppText.tr(
                    "Если вы не заходите в Telegram, аккаунт будет удалён через указанный срок.",
                    "If you don't log in to Telegram, your account will be deleted after this period."
                ))
            }

            if !vm.status.isEmpty {
                Section {
                    Text(vm.status)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Удаление аккаунта", "Account deletion"))
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
    }
}
