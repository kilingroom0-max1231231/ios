import SwiftUI

struct NewConversationView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case user
        case group
        case channel
        case link

        var id: String { rawValue }

        var title: String {
            switch self {
            case .user: return AppText.tr("Личный", "Private")
            case .group: return AppText.tr("Группа", "Group")
            case .channel: return AppText.tr("Канал", "Channel")
            case .link: return AppText.tr("Ссылка", "Link")
            }
        }
    }

    @State private var tab: Tab = .user
    @State private var username = ""
    @State private var title = ""
    @State private var description = ""
    @State private var memberIdsText = ""
    @State private var inviteLink = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Form {
                    switch tab {
                    case .user:
                        Section {
                            TextField(AppText.tr("Username (@name)", "Username (@name)"), text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } footer: {
                            Text(AppText.tr("Или откройте чат из вкладки «Контакты»", "Or open a chat from Contacts"))
                        }
                    case .group:
                        Section {
                            TextField(AppText.tr("Название", "Title"), text: $title)
                            TextField(AppText.tr("Описание", "Description"), text: $description, axis: .vertical)
                                .lineLimit(2...4)
                            TextField(AppText.tr("ID участников через запятую", "Member user IDs, comma-separated"), text: $memberIdsText)
                                .keyboardType(.numbersAndPunctuation)
                        }
                    case .channel:
                        Section {
                            TextField(AppText.tr("Название канала", "Channel title"), text: $title)
                            TextField(AppText.tr("Описание", "Description"), text: $description, axis: .vertical)
                                .lineLimit(2...4)
                        }
                    case .link:
                        Section {
                            TextField("https://t.me/+…", text: $inviteLink)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(ChatListScreenBackground().ignoresSafeArea())
            .navigationTitle(AppText.tr("Новый чат", "New chat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.tr("Отмена", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.tr("Создать", "Create")) {
                        Task { await submit() }
                    }
                    .disabled(vm.isBusy || !canSubmit)
                }
            }
        }
    }

    private var canSubmit: Bool {
        switch tab {
        case .user: return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .group, .channel: return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .link: return !inviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submit() async {
        do {
            let chatId: Int64
            switch tab {
            case .user:
                chatId = try await vm.openChatByUsername(username)
            case .group:
                let members = parseMemberIds(memberIdsText)
                chatId = try await vm.createGroup(title: title, description: description, memberUserIds: members)
            case .channel:
                chatId = try await vm.createChannel(title: title, description: description)
            case .link:
                chatId = try await vm.joinChatByInviteLink(inviteLink)
            }
            dismiss()
            vm.navigationTargetChatId = chatId
            await vm.refreshChats()
        } catch {
            vm.status = error.localizedDescription
        }
    }

    private func parseMemberIds(_ text: String) -> [Int64] {
        text
            .split { $0 == "," || $0 == " " || $0 == ";" }
            .compactMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
