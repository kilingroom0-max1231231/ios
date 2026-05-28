import SwiftUI

struct SearchView: View {
    @ObservedObject var vm: AppViewModel
    @State private var query = ""
    @State private var remoteResults: [TgChat] = []
    @State private var isSearchingRemote = false
    @FocusState private var isFocused: Bool

    private var localResults: [TgChat] {
        vm.searchLocalChats(query: query)
    }

    var body: some View {
        List {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !localResults.isEmpty {
                    Section(AppText.tr("Мои чаты", "My chats")) {
                        ForEach(localResults) { chat in
                            searchRow(chat)
                        }
                    }
                }

                Section(AppText.tr("Telegram", "Telegram")) {
                    if isSearchingRemote {
                        HStack {
                            ProgressView()
                            Text(AppText.tr("Поиск…", "Searching…"))
                                .foregroundStyle(.secondary)
                        }
                    } else if remoteResults.isEmpty {
                        Text(AppText.tr("Ничего не найдено", "Nothing found"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(remoteResults) { chat in
                            searchRow(chat)
                        }
                    }
                }
            } else {
                Section {
                    Text(AppText.tr("Введите имя, @username или название чата", "Enter a name, @username, or chat title"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AppText.tr("Поиск", "Search"))
        .searchable(text: $query, prompt: AppText.tr("Поиск в Telegram", "Search Telegram"))
        .onSubmit(of: .search) {
            Task { await runRemoteSearch() }
        }
        .onChange(of: query) { _ in
            Task { await runRemoteSearchDebounced() }
        }
        .background(ChatListScreenBackground().ignoresSafeArea())
    }

    @ViewBuilder
    private func searchRow(_ chat: TgChat) -> some View {
        Button {
            Task { await vm.openChat(chatId: chat.id) }
        } label: {
            HStack(spacing: 12) {
                AvatarView(
                    title: chat.title,
                    identifier: chat.id,
                    imagePath: chat.avatarPath,
                    size: 44,
                    isSavedMessages: chat.kind == .savedMessages
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let preview = chat.lastMessagePreview, !preview.isEmpty {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    @State private var remoteSearchTask: Task<Void, Never>?

    private func runRemoteSearchDebounced() async {
        remoteSearchTask?.cancel()
        let current = query
        remoteSearchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, current == query else { return }
            await runRemoteSearch()
        }
    }

    private func runRemoteSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            remoteResults = []
            return
        }
        isSearchingRemote = true
        defer { isSearchingRemote = false }
        remoteResults = await vm.searchTelegram(query: trimmed)
    }
}
