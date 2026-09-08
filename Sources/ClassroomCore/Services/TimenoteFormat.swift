import Foundation

/// Encoding for a timestamped note: `> @timenote(at: SECONDS){HH:MM:SS.mmm} text`,
/// a blockquote line whose directive body is the clickable, always-visible
/// timestamp pill (see `TimenoteDirective` in ClassroomApp for why the
/// display form is the directive's *body* rather than its arguments) and
/// links a note back to a moment in the lesson's video/audio. `HH:MM:SS.mmm`
/// (period-delimited milliseconds) is the same convention future transcript
/// ingestion should use, so notes and transcript cues share one clock.
public enum TimenoteFormat {
    /// Everything up to and including the directive's opening `{` — i.e. the
    /// part that carries the raw seconds value and gets muted/hidden by the
    /// editor except while the caret is inside it.
    private static let directivePrefix = "> @timenote(at: "
    private static let argumentsClose = "){"
    private static let bodyClose = "} "

    /// Legacy on-disk syntax marker, checked as a cheap pre-filter before
    /// running `legacyLineRegex` over a document; see
    /// `migratingLegacySyntax(in:)`.
    private static let legacyLinePrefixMarker = "> [!timenote "

    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^> @timenote\(at:\s*([0-9]*\.?[0-9]+)\)\{[^}]*\} ?(.*)$"#
    )
    private static let legacyLineRegex = try! NSRegularExpression(
        pattern: #"^> \[!timenote ([0-9:.]+)\] ?(.*)$"#
    )

    public static func formatTimestamp(_ totalSeconds: Double) -> String {
        let clampedSeconds = max(0, totalSeconds)
        let totalMilliseconds = Int((clampedSeconds * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds / 60_000) % 60
        let wholeSeconds = (totalMilliseconds / 1000) % 60
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, wholeSeconds, milliseconds)
    }

    public static func parseTimestamp(_ timestamp: String) -> Double? {
        let components = timestamp.split(separator: ":")
        guard components.count == 3 else {
            return nil
        }

        let secondsAndMilliseconds = components[2].split(separator: ".")
        guard
            secondsAndMilliseconds.count == 2,
            let hours = Double(components[0]),
            let minutes = Double(components[1]),
            let wholeSeconds = Double(secondsAndMilliseconds[0]),
            let milliseconds = Double(secondsAndMilliseconds[1])
        else {
            return nil
        }

        return hours * 3600 + minutes * 60 + wholeSeconds + milliseconds / 1000
    }

    /// The text to insert for a new timenote, with a trailing space ready
    /// for the note's content.
    public static func linePrefix(timestampSeconds: Double) -> String {
        directivePrefix + secondsLiteral(timestampSeconds) + argumentsClose + formatTimestamp(timestampSeconds) + bodyClose
    }

    /// A locale-independent, `Double`-parseable literal for the directive's
    /// `at:` argument — millisecond precision matches `formatTimestamp`.
    private static func secondsLiteral(_ totalSeconds: Double) -> String {
        String(format: "%.3f", max(0, totalSeconds))
    }

    /// Parses a line, returning its timestamp (in seconds) and note text
    /// if it matches the timenote format; `nil` otherwise.
    public static func parseLine(_ line: String) -> (timestampSeconds: Double, text: String)? {
        let ns = line as NSString
        guard let match = lineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }

        guard let timestampSeconds = Double(ns.substring(with: match.range(at: 1))) else {
            return nil
        }

        return (timestampSeconds, ns.substring(with: match.range(at: 2)))
    }

    /// Rewrites any legacy `> [!timenote HH:MM:SS.mmm] text` lines in `text`
    /// to the current directive syntax, line by line. Idempotent: text with
    /// no legacy lines (including text already in the current format) passes
    /// through unchanged. Run once when a `page.md`/`note.md` loads so
    /// existing lesson notes upgrade transparently; the next save persists
    /// the new form.
    public static func migratingLegacySyntax(in text: String) -> String {
        guard text.contains(legacyLinePrefixMarker) else {
            return text
        }

        return text.components(separatedBy: "\n").map { line -> String in
            let ns = line as NSString
            guard
                let match = legacyLineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                let timestampSeconds = parseTimestamp(ns.substring(with: match.range(at: 1)))
            else {
                return line
            }

            return linePrefix(timestampSeconds: timestampSeconds) + ns.substring(with: match.range(at: 2))
        }.joined(separator: "\n")
    }
}
