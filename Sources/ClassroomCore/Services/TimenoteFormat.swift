import Foundation

/// Encoding for a timestamped note: `> [!timenote HH:MM:SS.mmm] text`, an
/// Obsidian-callout-flavored line that links a note back to a moment in
/// the lesson's video/audio. `HH:MM:SS.mmm` (period-delimited
/// milliseconds) is the same convention future transcript ingestion
/// should use, so notes and transcript cues share one clock.
public enum TimenoteFormat {
    public static let linePrefixMarker = "> [!timenote "
    private static let closingBracket = "] "

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
        linePrefixMarker + formatTimestamp(timestampSeconds) + closingBracket
    }

    /// Parses a line, returning its timestamp (in seconds) and note text
    /// if it matches the timenote format; `nil` otherwise.
    public static func parseLine(_ line: String) -> (timestampSeconds: Double, text: String)? {
        guard line.hasPrefix(linePrefixMarker) else {
            return nil
        }

        let afterMarker = line.dropFirst(linePrefixMarker.count)
        guard let closingRange = afterMarker.range(of: closingBracket) else {
            return nil
        }

        let timestampText = String(afterMarker[afterMarker.startIndex..<closingRange.lowerBound])
        guard let timestampSeconds = parseTimestamp(timestampText) else {
            return nil
        }

        return (timestampSeconds, String(afterMarker[closingRange.upperBound...]))
    }
}
