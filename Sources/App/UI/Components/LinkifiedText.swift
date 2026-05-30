import Foundation
import SwiftUI

/// Builds an `AttributedString` with tappable links for URLs, @mentions and t.me links.
enum MessageTextLinker {
    static func attributed(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        guard !text.isEmpty else { return attr }

        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        func addLink(_ url: URL, range: NSRange) {
            guard let swiftRange = Range(range, in: text) else { return }
            guard
                let lower = AttributedString.Index(swiftRange.lowerBound, within: attr),
                let upper = AttributedString.Index(swiftRange.upperBound, within: attr)
            else { return }
            if attr[lower..<upper].runs.contains(where: { $0.link != nil }) { return }
            attr[lower..<upper].link = url
            attr[lower..<upper].underlineStyle = .single
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            detector.enumerateMatches(in: text, options: [], range: full) { result, _, _ in
                guard let result, let url = result.url else { return }
                addLink(url, range: result.range)
            }
        }

        addRegexLinks(
            in: text,
            attr: &attr,
            pattern: "(?i)\\b(?:t\\.me|telegram\\.me|telegram\\.dog)/[A-Za-z0-9_/+?=&%.\\-]+",
            range: full,
            urlBuilder: { match in
                let raw = ns.substring(with: match)
                return URL(string: "https://\(raw)")
            }
        )

        addRegexLinks(
            in: text,
            attr: &attr,
            pattern: "(?<![A-Za-z0-9_@/])@([A-Za-z][A-Za-z0-9_]{2,31})",
            range: full,
            urlBuilder: { match in
                let username = ns.substring(with: match).dropFirst()
                return URL(string: "https://t.me/\(username)")
            }
        )

        return attr
    }

    private static func addRegexLinks(
        in text: String,
        attr: inout AttributedString,
        pattern: String,
        range: NSRange,
        urlBuilder: (NSRange) -> URL?
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        regex.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
            guard let result, let url = urlBuilder(result.range) else { return }
            guard let swiftRange = Range(result.range, in: text) else { return }
            guard
                let lower = AttributedString.Index(swiftRange.lowerBound, within: attr),
                let upper = AttributedString.Index(swiftRange.upperBound, within: attr)
            else { return }
            if attr[lower..<upper].runs.contains(where: { $0.link != nil }) { return }
            attr[lower..<upper].link = url
            attr[lower..<upper].underlineStyle = .single
        }
    }
}

/// Renders text with tappable Telegram links. Apply `.font` / `.foregroundStyle` /
/// `.tint` on the resulting view to control styling.
struct LinkifiedText: View {
    let text: String
    var linkColor: Color = AppColors.accent

    var body: some View {
        Text(MessageTextLinker.attributed(text))
            .tint(linkColor)
            .textSelection(.enabled)
    }
}

struct TappableLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Routes link taps through the view model and optionally dismisses the current screen.
    func handleTelegramLinks(_ vm: AppViewModel, onNavigate: (() -> Void)? = nil) -> some View {
        environment(\.openURL, OpenURLAction { url in
            onNavigate?()
            vm.handleInternalLink(url)
            return .handled
        })
    }
}
