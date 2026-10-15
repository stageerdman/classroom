import Foundation

/// Encoding for a "comment on a Page quote": a Notes line that shows the
/// quoted passage as a clickable chip and links back to where it appears in
/// the lesson's Page.
///
/// Stored as a directive whose `ref` argument carries the quoted text, base64
/// so arbitrary punctuation / quotes / newlines in the selection can't break
/// the directive syntax (the engine's string arguments are not escape-aware).
/// The visible body is a short, readable preview — the full text for matching
/// lives in the `ref`. Mirrors `TimenoteFormat`'s directive shape.
public enum PageQuoteFormat {
    /// `onLinkClick` target prefix; the suffix is the base64 `ref`.
    public static let clickTargetPrefix = "classroom-pagequote:"

    private static let directivePrefix = "> @pagequote(ref: \""
    private static let argumentsClose = "\"){"
    private static let bodyClose = "} "
    private static let maxPreviewLength = 90

    /// The Notes line to insert for `quote`, ending with a trailing space so
    /// the user's comment continues on the same line.
    public static func linePrefix(quote: String) -> String {
        directivePrefix + encode(quote) + argumentsClose + preview(of: quote) + bodyClose
    }

    public static func encode(_ quote: String) -> String {
        Data(quote.utf8).base64EncodedString()
    }

    public static func decode(_ ref: String) -> String? {
        Data(base64Encoded: ref).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// A short, single-line, brace-free preview shown as the chip label.
    static func preview(of quote: String) -> String {
        let collapsed = quote
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
        let trimmed = collapsed.count > maxPreviewLength
            ? collapsed.prefix(maxPreviewLength).trimmingCharacters(in: .whitespaces) + "…"
            : collapsed
        return "“\(trimmed)”"
    }

    /// Finds `quote` in `text` tolerant of whitespace differences (the Page may
    /// wrap or space the passage differently than the stored copy), returning
    /// its range in `text`, or `nil` if the passage is no longer present.
    public static func range(ofQuote quote: String, in text: String) -> NSRange? {
        let tokens = quote
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        guard !tokens.isEmpty else {
            return nil
        }

        let pattern = tokens.joined(separator: "\\s+")
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let ns = text as NSString
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))?.range
    }
}
