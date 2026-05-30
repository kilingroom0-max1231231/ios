import SwiftUI

struct GlobalSearchView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $vm.globalSearchScope) {
                        ForEach(GlobalSearchScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if vm.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    Section {
                        Text(AppText.tr("Введите минимум 2 символа", "Enter at least 2 characters"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else if vm.isGlobalSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else if vm.globalSearchScope == .myChats {
                    if vm.globalSearchChats.isEmpty {
                        Section {
                            Text(AppText.tr("Ничего не найдено", "Nothing found"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        Section {
                            ForEach(vm.globalSearchChats) { chat in
                                Button {
                                    Task { await vm.openChat(chatId: chat.id) }
                                } label: {
                                    GlobalSearchChatRow(chat: chat)
                                }
                                .buttonStyle(ChatRowPressStyle())
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    }
                } else if vm.globalSearchMessageHits.isEmpty && vm.globalSearchChats.isEmpty {
                    Section {
                        Text(AppText.tr("Ничего не найдено", "Nothing found"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    if !vm.globalSearchChats.isEmpty {
                        Section(AppText.tr("Чаты", "Chats")) {
                            ForEach(vm.globalSearchChats) { chat in
                                Button {
                                    Task { await vm.openChat(chatId: chat.id) }
                                } label: {
                                    GlobalSearchChatRow(chat: chat)
                                }
                                .buttonStyle(ChatRowPressStyle())
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    }

                    if !vm.globalSearchMessageHits.isEmpty {
                        Section(AppText.tr("Сообщения", "Messages")) {
                            ForEach(vm.globalSearchMessageHits) { hit in
                                Button {
                                    Task { await vm.openChat(chatId: hit.message.chatId) }
                                } label: {
                                    messageHitRow(hit)
                                }
                                .buttonStyle(ChatRowPressStyle())
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ChatListScreenBackground())
            .transparentNavigationBar()
            .navigationTitle(AppText.tr("Поиск", "Search"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $vm.globalSearchQuery,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: vm.globalSearchScope == .myChats
                    ? AppText.tr("Поиск", "Search")
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

    private func messageHitRow(_ hit: GlobalSearchMessageHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hit.chatTitle)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(hit.message.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct GlobalSearchChatRow: View {
    let chat: TgChat

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                title: chat.title,
                identifier: chat.id,
                imagePath: chat.avatarPath,
                size: 52,
                isSavedMessages: chat.kind == .savedMessages
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(chat.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let preview = chat.lastMessagePreview, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
