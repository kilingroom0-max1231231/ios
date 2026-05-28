import SwiftUI

struct GlobalSearchView: View {
    @ObservedObject var vm: AppViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Picker("", selection: $vm.globalSearchScope) {
                        ForEach(GlobalSearchScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    searchField
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                resultsList
            }
            .background(ChatListScreenBackground().ignoresSafeArea())
            .mainTabNavigationBar(title: AppText.tr("Поиск", "Search"))
        }
        .onChange(of: vm.globalSearchScope) { _ in
            Task { await vm.runGlobalSearch() }
        }
        .onChange(of: vm.globalSearchQuery) { _ in
            Task { await vm.runGlobalSearch() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(
                vm.globalSearchScope == .myChats
                    ? AppText.tr("Чаты", "Chats")
                    : AppText.tr("Пользователи и каналы", "Users and channels"),
                text: $vm.globalSearchQuery
            )
            .focused($isSearchFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit {
                Task { await vm.runGlobalSearch() }
            }

            if !vm.globalSearchQuery.isEmpty {
                Button {
                    vm.globalSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if vm.isGlobalSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassContainer(cornerRadius: 18)
    }

    @ViewBuilder
    private var resultsList: some View {
        List {
            if vm.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                Text(AppText.tr("Введите минимум 2 символа", "Enter at least 2 characters"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                if !vm.globalSearchChats.isEmpty {
                    Section(AppText.tr("Чаты", "Chats")) {
                        ForEach(vm.globalSearchChats) { chat in
                            Button {
                                Task { await vm.openChatFromSearch(chat.id) }
                            } label: {
                                ChatSearchRow(chat: chat)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }

                if vm.globalSearchScope == .telegram, !vm.globalSearchMessageHits.isEmpty {
                    Section(AppText.tr("Сообщения", "Messages")) {
                        ForEach(vm.globalSearchMessageHits) { hit in
                            Button {
                                Task { await vm.openChatFromSearch(hit.message.chatId) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(hit.chatTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(hit.message.text)
                                        .font(.subheadline)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
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
                        .listRowSeparator(.hidden)
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
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
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
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
