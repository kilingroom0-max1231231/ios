import SwiftUI

struct MessageSwipeSettingsView: View {
    @ObservedObject var store: MessageSwipeSettingsStore

    var body: some View {
        List {
            Section {
                Text(AppText.tr(
                    "Свайп сообщения влево сразу выполняет выбранное действие.",
                    "Swipe a message left to run the selected action immediately."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section(AppText.tr("Действие", "Action")) {
                Picker(AppText.tr("При свайпе", "On swipe"), selection: $store.primaryAction) {
                    ForEach(MessageSwipeAction.allCases) { action in
                        Label(action.title, systemImage: action.systemImage)
                            .tag(action)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
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
    }
}
