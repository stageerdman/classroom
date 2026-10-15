import Foundation

/// Parses a transcript markdown sidecar into ordered `TranscriptCue`s.
///
/// A cue begins at a **header line** of the form
/// `**Speaker** [timestamp] optional-annotation`, where `timestamp` is
/// `MM:SS`, `H:MM:SS`, or `HH:MM:SS` (optional fractional seconds allowed).
/// Every line until the next header is the cue's body (blank lines kept as
/// paragraph breaks). Lines before the first header are ignored.
///
/// Best-effort and total: malformed input never throws. A line that looks
/// like a header but carries an unparseable timestamp is treated as body
/// text rather than starting a new cue, so nothing is silently dropped.
public enum TranscriptParser {
    // **Name** [ts] trailing
    //  1: speaker (non-greedy, trimmed later)
    //  2: timestamp digits/colons/dot
    //  3: trailing annotation (e.g. "(interrupting)")
    private static let headerRegex = try! NSRegularExpression(
        pattern: #"^\s*\*\*(.+?)\*\*\s*\[\s*([0-9]{1,2}(?::[0-9]{2}){1,2}(?:\.[0-9]+)?)\s*\]\s*(.*?)\s*$"#
    )

    public static func parse(_ markdown: String) -> [TranscriptCue] {
        let lines = markdown.components(separatedBy: "\n")

        // Collect (start, speaker, parenthetical, bodyLines) before computing
        // `end` from the following cue's start in a second pass.
        var partials: [(start: Double, speaker: String, parenthetical: String?, body: [String])] = []

        for line in lines {
            if let header = parseHeader(line) {
                partials.append((header.start, header.speaker, header.parenthetical, []))
            } else if !partials.isEmpty {
                partials[partials.count - 1].body.append(line)
            }
            // else: preamble before the first header — ignored.
        }

        return partials.enumerated().map { index, partial in
            let end = index + 1 < partials.count ? partials[index + 1].start : .infinity
            return TranscriptCue(
                id: index,
                startSeconds: partial.start,
                endSeconds: end,
                speaker: partial.speaker,
                parenthetical: partial.parenthetical,
                text: trimmedBody(partial.body)
            )
        }
    }

    private static func parseHeader(_ line: String) -> (start: Double, speaker: String, parenthetical: String?)? {
        let ns = line as NSString
        guard let match = headerRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }

        let speaker = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        guard let start = parseTimestampSeconds(ns.substring(with: match.range(at: 2))) else {
            return nil
        }

        let trailing = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
        return (start, speaker, trailing.isEmpty ? nil : trailing)
    }

    /// Parses `MM:SS`, `H:MM:SS`, or `HH:MM:SS` (last field may carry a
    /// decimal) into seconds. Returns `nil` if any field isn't numeric.
    static func parseTimestampSeconds(_ timestamp: String) -> Double? {
        let components = timestamp.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count) else {
            return nil
        }

        var seconds = 0.0
        for component in components {
            guard let value = Double(component) else {
                return nil
            }
            seconds = seconds * 60 + value
        }
        return seconds
    }

    /// Drops leading/trailing blank lines so a cue body starts and ends on
    /// real text, while keeping interior blank lines as paragraph breaks.
    private static func trimmedBody(_ lines: [String]) -> String {
        var slice = lines[...]
        while let first = slice.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            slice = slice.dropFirst()
        }
        while let last = slice.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            slice = slice.dropLast()
        }
        return slice.joined(separator: "\n")
    }
}
