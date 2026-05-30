import SwiftUI
import UIKit

struct CustomMainTabBar: View {
    @ObservedObject var store: MainTabBarStore
    var accent: Color
    var onCustomize: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)

            HStack(spacing: 0) {
                ForEach(store.visibleTabs) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                            store.selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 20, weight: store.selectedTab == tab ? .semibold : .regular))
                            Text(tab.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(store.selectedTab == tab ? accent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(store.selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        }
        .background {
            FrostedBarBackground()
                .ignoresSafeArea(edges: .bottom)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.55) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onCustomize()
        }
    }
}
