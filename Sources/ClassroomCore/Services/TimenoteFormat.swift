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

    /// Cheap pre-filter for `migratingLegacySyntax(in:)` — skip the per-line
    /// regex pass unless a timenote directive might be present.
    private static let currentDirectiveMarker = "@timenote(at:"

    public static func formatTimestamp(_ totalSeconds: Double) -> String {
        let clampedSeconds = max(0, totalSeconds)
        let totalMilliseconds = Int((clampedSeconds * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds / 60_000) % 60
        let wholeSeconds = (totalMilliseconds / 1000) % 60
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, wholeSeconds, milliseconds)
    }

    /// The human-readable pill shown for a timestamp, shared by Notes
    /// timenotes and the transcript so both read the same: `[MM:SS]`, or
    /// `[HH:MM:SS]` once the stamp reaches an hour (or `forcingHours` is set —
    /// the transcript keeps one format for a long video). Zero-padded so a
    /// column of them stays aligned.
    public static func bracketedTimestamp(_ totalSeconds: Double, forcingHours: Bool = false) -> String {
        let total = max(0, Int(totalSeconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if forcingHours || hours > 0 {
            return String(format: "[%02d:%02d:%02d]", hours, minutes, seconds)
        }
        return String(format: "[%02d:%02d]", minutes, seconds)
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
        directivePrefix + secondsLiteral(timestampSeconds) + argumentsClose + bracketedTimestamp(timestampSeconds) + bodyClose
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

    /// Normalizes timenote lines in `text`, line by line:
    ///   * legacy `> [!timenote HH:MM:SS.mmm] text` → current directive syntax;
    ///   * current directives → their body re-rendered in the current pill
    ///     format (so notes saved with the old `{HH:MM:SS.mmm}` body upgrade to
    ///     the `[MM:SS]`/`[HH:MM:SS]` pill).
    /// Idempotent: a document already in the current form passes through
    /// unchanged (rebuilding from the directive's `at:` seconds reproduces the
    /// same line). Run once when a `page.md`/`note.md` loads so existing lesson
    /// content upgrades transparently; the next save persists the new form.
    public static func migratingLegacySyntax(in text: String) -> String {
        guard text.contains(legacyLinePrefixMarker) || text.contains(currentDirectiveMarker) else {
            return text
        }

        return text.components(separatedBy: "\n").map { line -> String in
            let ns = line as NSString

            if let match = legacyLineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               let timestampSeconds = parseTimestamp(ns.substring(with: match.range(at: 1))) {
                return linePrefix(timestampSeconds: timestampSeconds) + ns.substring(with: match.range(at: 2))
            }

            // A current-syntax directive: rebuild from its `at:` seconds so an
            // old `{HH:MM:SS.mmm}` body is re-rendered as the current pill.
            if let parsed = parseLine(line) {
                return linePrefix(timestampSeconds: parsed.timestampSeconds) + parsed.text
            }

            return line
        }.joined(separator: "\n")
    }
}
