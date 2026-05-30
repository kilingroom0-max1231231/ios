import Foundation
import SwiftUI

/// Builds an `AttributedString` with tappable links for URLs, @mentions and t.me links.
enum MessageTextLinker {
    static func attributed(
        _ text: String,
        entities: [TgMessageTextEntity] = [],
        textColor: Color? = nil,
        linkColor: Color? = nil
    ) -> AttributedString {
        let normalized = normalize(text)
        var attr = AttributedString(normalized)
        guard !normalized.isEmpty else { return attr }

        let ns = normalized as NSString
        let full = NSRange(location: 0, length: ns.length)

        func addLink(_ url: URL, range: NSRange) {
            guard let swiftRange = Range(range, in: normalized) else { return }
            guard
                let lower = AttributedString.Index(swiftRange.lowerBound, within: attr),
                let upper = AttributedString.Index(swiftRange.upperBound, within: attr)
            else { return }
            if attr[lower..<upper].runs.contains(where: { $0.link != nil }) { return }
            attr[lower..<upper].link = url
            if let linkColor {
                attr[lower..<upper].foregroundColor = linkColor
            }
            attr[lower..<upper].underlineStyle = .single
        }

        for entity in entities.sorted(by: { $0.offset < $1.offset }) {
            let range = NSRange(location: entity.offset, length: entity.length)
            guard NSIntersectionRange(range, full) == range else { continue }
            addLink(entity.url, range: range)
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            detector.enumerateMatches(in: normalized, options: [], range: full) { result, _, _ in
                guard let result, let url = result.url else { return }
                addLink(url, range: result.range)
            }
        }

        addRegexLinks(
            in: normalized,
            attr: &attr,
            pattern: "(?i)(?:https?://)?(?:t\\.me|telegram\\.me|telegram\\.dog)/\\+[A-Za-z0-9_\\-]+",
            range: full,
            urlBuilder: { match in
                let raw = ns.substring(with: match)
                if raw.lowercased().hasPrefix("http") {
                    return URL(string: raw)
                }
                return URL(string: "https://\(raw)")
            }
        )

        addRegexLinks(
            in: normalized,
            attr: &attr,
            pattern: "(?i)\\b(?:t\\.me|telegram\\.me|telegram\\.dog)/[A-Za-z0-9_/+?=&%.\\-]+",
            range: full,
            urlBuilder: { match in
                let raw = ns.substring(with: match)
                return URL(string: "https://\(raw)")
            }
        )

        addRegexLinks(
            in: normalized,
            attr: &attr,
            pattern: "(?<![A-Za-z0-9_@/])@([A-Za-z][A-Za-z0-9_]{2,31})",
            range: full,
            urlBuilder: { match in
                let username = ns.substring(with: match).dropFirst()
                return URL(string: "https://t.me/\(username)")
            }
        )

        if let textColor {
            for run in attr.runs where run.link == nil {
                attr[run.range].foregroundColor = textColor
            }
        }

        return attr
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .replacingOccurrences(of: "\u{2007}", with: " ")
            .replacingOccurrences(of: "\u{feff}", with: "")
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

/// Renders text with tappable Telegram links.
struct LinkifiedText: View {
    let text: String
    var entities: [TgMessageTextEntity] = []
    var linkColor: Color = AppColors.accent
    var textColor: Color = .primary

    var body: some View {
        Text(MessageTextLinker.attributed(
            text,
            entities: entities,
            textColor: textColor,
            linkColor: linkColor
        ))
        .tint(linkColor)
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
