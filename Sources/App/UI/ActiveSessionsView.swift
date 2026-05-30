import SwiftUI

struct ActiveSessionsView: View {
    @ObservedObject var vm: AppViewModel
    @State private var sessionPendingTermination: TgActiveSession?
    @State private var showTerminateOthersConfirm = false

    var body: some View {
        List {
            if vm.isActiveSessionsLoading && vm.activeSessions.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            } else if vm.activeSessions.isEmpty {
                Section {
                    Text(AppText.tr("Нет активных сессий", "No active sessions"))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            } else {
                if let current = vm.activeSessions.first(where: \.isCurrent) {
                    Section(AppText.tr("Это устройство", "This device")) {
                        sessionRow(current)
                    }
                }

                let others = vm.activeSessions.filter { !$0.isCurrent }
                if !others.isEmpty {
                    Section(AppText.tr("Другие устройства", "Other devices")) {
                        ForEach(others) { session in
                            sessionRow(session)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        sessionPendingTermination = session
                                    } label: {
                                        Label(AppText.tr("Завершить", "Terminate"), systemImage: "xmark.circle")
                                    }
                                }
                        }
                    }
                }
            }

            if vm.activeSessions.contains(where: { !$0.isCurrent }) {
                Section {
                    Button(role: .destructive) {
                        showTerminateOthersConfirm = true
                    } label: {
                        Text(AppText.tr("Завершить все другие сессии", "Terminate all other sessions"))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ChatListScreenBackground().ignoresSafeArea())
        .navigationTitle(AppText.tr("Устройства", "Devices"))
        .navigationBarTitleDisplayMode(.inline)
        .transparentNavigationBar()
        .refreshable {
            await vm.refreshActiveSessions()
        }
        .task {
            await vm.refreshActiveSessions()
        }
        .alert(
            AppText.tr("Завершить сессию?", "Terminate session?"),
            isPresented: Binding(
                get: { sessionPendingTermination != nil },
                set: { if !$0 { sessionPendingTermination = nil } }
            ),
            presenting: sessionPendingTermination
        ) { session in
            Button(AppText.tr("Завершить", "Terminate"), role: .destructive) {
                Task { await vm.terminateActiveSession(session) }
            }
            Button(AppText.tr("Отмена", "Cancel"), role: .cancel) {
                sessionPendingTermination = nil
            }
        } message: { session in
            Text(session.title)
        }
        .confirmationDialog(
            AppText.tr("Завершить все другие сессии?", "Terminate all other sessions?"),
            isPresented: $showTerminateOthersConfirm,
            titleVisibility: .visible
        ) {
            Button(AppText.tr("Завершить", "Terminate"), role: .destructive) {
                Task { await vm.terminateAllOtherActiveSessions() }
            }
            Button(AppText.tr("Отмена", "Cancel"), role: .cancel) {}
        }
    }

    private func sessionRow(_ session: TgActiveSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sessionIcon(for: session))
                .font(.title3)
                .foregroundStyle(session.isCurrent ? AppColors.accent : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.body.weight(session.isCurrent ? .semibold : .regular))
                    if session.isCurrent {
                        Text(AppText.tr("текущая", "active"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.accent)
                    }
                }

                if !session.subtitle.isEmpty {
                    Text(session.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(session.locationText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)

                Text(sessionActivityText(session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func sessionIcon(for session: TgActiveSession) -> String {
        let platform = session.platform.lowercased()
        if platform.contains("ios") || platform.contains("iphone") || platform.contains("ipad") {
            return "iphone"
        }
        if platform.contains("mac") {
            return "laptopcomputer"
        }
        if platform.contains("android") {
            return "smartphone"
        }
        if platform.contains("web") {
            return "globe"
        }
        return "desktopcomputer"
    }

    private func sessionActivityText(_ session: TgActiveSession) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: session.lastActiveDate, relativeTo: Date())
        return AppText.tr("Был(а) в сети \(relative)", "Last active \(relative)")
    }
}
