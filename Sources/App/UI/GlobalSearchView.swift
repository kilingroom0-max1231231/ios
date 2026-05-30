import SwiftUI

struct GlobalSearchView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $vm.globalSearchScope) {
                    ForEach(GlobalSearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)

                resultsList
            }
            .background(ChatListScreenBackground().ignoresSafeArea())
            .mainTabNavigationBar(title: AppText.tr("Поиск", "Search"))
            .searchable(
                text: $vm.globalSearchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: vm.globalSearchScope == .myChats
                    ? AppText.tr("Поиск по чатам", "Search chats")
                    : AppText.tr("Поиск пользователей и каналов", "Search users and channels")
            )
        }
        .onChange(of: vm.globalSearchScope) { _ in
            Task { await vm.runGlobalSearch() }
        }
        .onChange(of: vm.globalSearchQuery) { _ in
            Task { await vm.runGlobalSearch() }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        List {
            if vm.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                Text(AppText.tr("Введите минимум 2 символа", "Enter at least 2 characters"))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else if vm.isGlobalSearching {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if vm.globalSearchScope == .myChats {
                if vm.globalSearchChats.isEmpty {
                    Text(AppText.tr("Ничего не найдено", "Nothing found"))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(vm.globalSearchChats) { chat in
                        Button {
                            Task { await vm.openChat(chatId: chat.id) }
                        } label: {
                            chatRow(chat)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                }
            } else if vm.globalSearchMessageHits.isEmpty && vm.globalSearchChats.isEmpty {
                Text(AppText.tr("Ничего не найдено", "Nothing found"))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                if !vm.globalSearchChats.isEmpty {
                    Section(AppText.tr("Чаты", "Chats")) {
                        ForEach(vm.globalSearchChats) { chat in
                            Button {
                                Task { await vm.openChat(chatId: chat.id) }
                            } label: {
                                chatRow(chat)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                if !vm.globalSearchMessageHits.isEmpty {
                    Section(AppText.tr("Сообщения", "Messages")) {
                        ForEach(vm.globalSearchMessageHits) { hit in
                            Button {
                                Task { await vm.openChat(chatId: hit.message.chatId) }
                            } label: {
                                messageHitRow(hit)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func chatRow(_ chat: TgChat) -> some View {
        HStack(spacing: 12) {
            AvatarView(
                title: chat.title,
                identifier: chat.id,
                imagePath: chat.avatarPath,
                size: 44
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let preview = chat.lastMessagePreview, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func messageHitRow(_ hit: GlobalSearchMessageHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hit.chatTitle)
                .font(.subheadline.weight(.semibold))
            Text(hit.message.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
