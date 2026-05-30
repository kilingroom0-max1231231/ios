import Foundation
import SwiftUI

/// Builds an `AttributedString` with tappable links for URLs, @mentions and t.me links.
/// Only the `.link` attribute is applied so the caller controls font/color via SwiftUI
/// modifiers (`.font`, `.foregroundStyle`) and link tint via `.tint`.
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
            // Don't overwrite an already-linked region (e.g. URL detected first).
            if attr[lower..<upper].runs.contains(where: { $0.link != nil }) { return }
            attr[lower..<upper].link = url
        }

        // 1. Standard URLs / emails via the system detector.
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            detector.enumerateMatches(in: text, options: [], range: full) { result, _, _ in
                guard let result, let url = result.url else { return }
                addLink(url, range: result.range)
            }
        }

        // 2. Bare t.me / telegram.me links without a scheme.
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

        // 3. @mentions -> resolved as public usernames.
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
        }
    }
}

/// Renders text with tappable Telegram links. Apply `.font` / `.foregroundStyle` /
/// `.tint` on the resulting view to control styling.
struct LinkifiedText: View {
    let text: String

    var body: some View {
        Text(MessageTextLinker.attributed(text))
            .textSelection(.enabled)
    }
}

extension View {
    /// Routes link taps (URLs, @mentions, t.me invite links) through the view model so
    /// they open the right chat / external page instead of the default browser handler.
    func handleTelegramLinks(_ vm: AppViewModel) -> some View {
        environment(\.openURL, OpenURLAction { url in
            vm.handleInternalLink(url)
            return .handled
        })
    }
}
