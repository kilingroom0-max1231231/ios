import SwiftUI

struct BlockedUsersView: View {
    @ObservedObject var vm: AppViewModel
    @State private var senderPendingUnblock: TgBlockedSender?

    var body: some View {
        List {
            if vm.isBlockedUsersLoading && vm.blockedSenders.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            } else if vm.blockedSenders.isEmpty {
                Section {
                    Text(AppText.tr("Нет заблокированных пользователей", "No blocked users"))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(vm.blockedSenders) { sender in
                        HStack(spacing: 12) {
                            Image(systemName: sender.userId != nil ? "person.crop.circle" : "bubble.left.and.bubble.right")
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            Text(sender.title)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                senderPendingUnblock = sender
                            } label: {
                                Label(AppText.tr("Разблокировать", "Unblock"), systemImage: "hand.raised.slash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Заблокированные", "Blocked"))
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
        .refreshable {
            await vm.refreshBlockedUsers()
        }
        .task {
            await vm.refreshBlockedUsers()
        }
        .alert(
            AppText.tr("Разблокировать?", "Unblock?"),
            isPresented: Binding(
                get: { senderPendingUnblock != nil },
                set: { if !$0 { senderPendingUnblock = nil } }
            ),
            presenting: senderPendingUnblock
        ) { sender in
            Button(AppText.tr("Разблокировать", "Unblock"), role: .destructive) {
                Task { await vm.unblockSender(sender) }
            }
            Button(AppText.tr("Отмена", "Cancel"), role: .cancel) {
                senderPendingUnblock = nil
            }
        } message: { sender in
            Text(sender.title)
        }
    }
}
