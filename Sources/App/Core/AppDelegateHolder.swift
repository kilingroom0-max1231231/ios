import SwiftUI

/// Bridges UIKit push callbacks into SwiftUI lifecycle.
enum AppDelegateHolder {
    @MainActor static weak var viewModel: AppViewModel?
}
