import SwiftUI

struct ChatFolderSettingsView: View {
    @ObservedObject var vm: AppViewModel
    let folder: TgChatFolder
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var includedChats: [TgChat] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.tr("Название", "Name")) {
                    TextField(AppText.tr("Название папки", "Folder name"), text: $title)
                }

                Section(AppText.tr("Чаты в папке", "Chats in folder")) {
                    if isLoading {
                        ProgressView()
                    } else if includedChats.isEmpty {
                        Text(AppText.tr("Нет чатов", "No chats"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(includedChats) { chat in
                            HStack(spacing: 10) {
                                AvatarView(
                                    title: chat.title,
                                    identifier: chat.id,
                                    imagePath: chat.avatarPath,
                                    size: 36
                                )
                                Text(chat.title)
                                    .lineLimit(1)
                                Spacer()
                                Button(role: .destructive) {
                                    Task {
                                        await vm.removeChat(chat, fromFolder: folder.id)
                                        includedChats.removeAll { $0.id == chat.id }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle(folder.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.tr("Закрыть", "Close")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.tr("Сохранить", "Save")) {
                        Task {
                            await vm.renameChatFolder(folder, title: title)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                title = folder.title
                await loadIncludedChats()
            }
        }
    }

    private func loadIncludedChats() async {
        isLoading = true
        defer { isLoading = false }
        includedChats = await vm.loadIncludedChats(for: folder.id)
    }
}

struct MoveChatToFolderSheet: View {
    @ObservedObject var vm: AppViewModel
    let chat: TgChat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if vm.chatFolders.isEmpty {
                    Text(AppText.tr("Нет папок", "No folders"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.chatFolders) { folder in
                        Button {
                            Task {
                                await vm.addChat(chat, toFolder: folder.id)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if let emoji = folder.iconEmoji, !emoji.isEmpty {
                                    Text(emoji)
                                } else {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(AppColors.accent)
                                }
                                Text(folder.title)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(AppText.tr("В папку", "Move to folder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppText.tr("Отмена", "Cancel")) { dismiss() }
                }
            }
        }
    }
}
