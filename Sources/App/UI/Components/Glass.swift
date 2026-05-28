import SwiftUI

enum Glass {
    static func fieldBackground() -> some ShapeStyle { .ultraThinMaterial }
}

public extension View {
    @ViewBuilder
    func applyLiquidGlassIfAvailable(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

private struct LegacyGlassButton: ButtonStyle {
    var prominent: Bool = false
    var cornerRadius: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                prominent
                    ? AnyShapeStyle(AppColors.accent.opacity(configuration.isPressed ? 0.75 : 0.95))
                    : AnyShapeStyle(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(prominent ? 0.10 : 0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassField: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .applyLiquidGlassIfAvailable(cornerRadius: cornerRadius, interactive: true)
            } else {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Glass.fieldBackground())
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .applyLiquidGlassIfAvailable()
            }
        }
    }
}

extension View {
    func glassField() -> some View {
        modifier(GlassField())
    }

    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        self
            .buttonStyle(LegacyGlassButton(prominent: prominent))
            .applyLiquidGlassIfAvailable(cornerRadius: 18, interactive: true)
    }

    @ViewBuilder
    func glassContainer(cornerRadius: CGFloat = 18) -> some View {
        if #available(iOS 26.0, *) {
            self.applyLiquidGlassIfAvailable(cornerRadius: cornerRadius)
        } else {
            self
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
