import SwiftUI

struct MessageSwipeSettingsView: View {
    @ObservedObject var store: MessageSwipeSettingsStore

    var body: some View {
        List {
            Section {
                Text(AppText.tr(
                    "Свайп сообщения влево открывает выбранные действия. Порядок сверху вниз — слева направо в чате.",
                    "Swipe a message left to reveal actions. Top-to-bottom order is left-to-right in chat."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section(AppText.tr("Действия", "Actions")) {
                ForEach(store.orderedActions) { action in
                    Toggle(isOn: binding(for: action)) {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
                .onMove(perform: store.move)
            }

            Section {
                Button(AppText.tr("Сбросить по умолчанию", "Reset to defaults")) {
                    store.resetToDefaults()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AppText.tr("Свайп сообщения", "Message swipe"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
    }

    private func binding(for action: MessageSwipeAction) -> Binding<Bool> {
        Binding(
            get: { store.isEnabled(action) },
            set: { store.setEnabled(action, enabled: $0) }
        )
    }
}
