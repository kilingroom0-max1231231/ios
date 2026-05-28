import SwiftUI

struct GlobalSearchView: View {
    @ObservedObject var vm: AppViewModel
    @FocusState private var isSearchFocused: Bool

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
                .padding(.vertical, 10)

                searchField
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                resultsList
            }
            .background(ChatListScreenBackground().ignoresSafeArea())
            .navigationTitle(AppText.tr("Поиск", "Search"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onChange(of: vm.globalSearchScope) { _ in
            Task { await vm.runGlobalSearch() }
        }
        .onChange(of: vm.globalSearchQuery) { _ in
            Task { await vm.runGlobalSearch() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(
                vm.globalSearchScope == .myChats
                    ? AppText.tr("Чаты и сообщения", "Chats and messages")
                    : AppText.tr("Пользователи, каналы, сообщения", "Users, channels, messages"),
                text: $vm.globalSearchQuery
            )
            .focused($isSearchFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit {
                Task { await vm.runGlobalSearch() }
            }

            if vm.isGlobalSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { isSearchFocused = true }
    }

    @ViewBuilder
    private var resultsList: some View {
        List {
            if vm.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                Text(AppText.tr("Введите минимум 2 символа", "Enter at least 2 characters"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                if !vm.globalSearchChats.isEmpty {
                    Section(AppText.tr("Чаты", "Chats")) {
                        ForEach(vm.globalSearchChats) { chat in
                            Button {
                                vm.openChatFromSearch(chat.id)
                            } label: {
                                ChatSearchRow(chat: chat)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                        }
                    }
                }

                if vm.globalSearchScope == .telegram, !vm.globalSearchMessageHits.isEmpty {
                    Section(AppText.tr("Сообщения", "Messages")) {
                        ForEach(vm.globalSearchMessageHits) { hit in
                            Button {
                                vm.openChatFromSearch(hit.message.chatId)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(hit.chatTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(hit.message.text)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                        }
                    }
                }

                if vm.globalSearchChats.isEmpty,
                   vm.globalSearchMessageHits.isEmpty,
                   !vm.isGlobalSearching {
                    Text(AppText.tr("Ничего не найдено", "Nothing found"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct ChatSearchRow: View {
    let chat: TgChat

    var body: some View {
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
                    .font(.headline)
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
}
