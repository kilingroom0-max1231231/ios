import SwiftUI

struct TabBarCustomizationView: View {
    @ObservedObject var store: MainTabBarStore
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(AppText.tr(
                        "Удерживайте нижнюю панель, чтобы открыть эти настройки. Перетаскивайте вкладки для изменения порядка.",
                        "Long-press the bottom bar to open these settings. Drag tabs to reorder them."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Section(AppText.tr("Вкладки", "Tabs")) {
                    ForEach(store.tabOrder) { tab in
                        HStack(spacing: 12) {
                            Image(systemName: tab.systemImage)
                                .foregroundStyle(AppColors.accent)
                                .frame(width: 28)

                            Text(tab.title)

                            Spacer()

                            Toggle("", isOn: visibilityBinding(for: tab))
                                .labelsHidden()
                                .disabled(!store.isVisible(tab) && store.visibleTabs.count <= 1)
                        }
                    }
                    .onMove { source, destination in
                        store.moveTabs(from: source, to: destination)
                    }
                }

                Section {
                    Button(AppText.tr("Сбросить по умолчанию", "Reset to default")) {
                        store.resetToDefault()
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(AppText.tr("Панель вкладок", "Tab bar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppText.tr("Готово", "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func visibilityBinding(for tab: MainTab) -> Binding<Bool> {
        Binding(
            get: { store.isVisible(tab) },
            set: { store.setVisible(tab, visible: $0) }
        )
    }
}
