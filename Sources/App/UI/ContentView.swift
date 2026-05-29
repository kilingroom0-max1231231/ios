import SwiftUI

struct ContentView: View {
    @StateObject private var appearance = AppAppearanceStore.shared

    var body: some View {
        AppShellView()
            .preferredColorScheme(appearance.resolvedColorScheme)
    }
}
