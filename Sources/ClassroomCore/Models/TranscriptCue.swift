import Foundation

/// One turn in a transcript: a speaker, the moment it starts, and the spoken
/// text. Produced by `TranscriptParser` from a `<video>.md` sidecar.
///
/// `startSeconds`/`endSeconds` share the same clock as the video and as
/// `TimenoteFormat` (see its header note), so clicking a cue can seek the
/// player and the player's `currentTimeSeconds` can pick out the active cue.
public struct TranscriptCue: Identifiable, Equatable {
    /// Index of this cue in the parsed, start-ordered array. Stable for the
    /// lifetime of a parse, which is all the view (and `scrollTo`) needs.
    public let id: Int
    public let startSeconds: Double
    /// The next cue's `startSeconds`, or `.infinity` for the last cue — the
    /// half-open interval `[startSeconds, endSeconds)` a cue is "active" for.
    public let endSeconds: Double
    /// The speaker name exactly as authored (e.g. "Obchodník"). Mapping a
    /// name to a display color is a view concern, kept out of the model.
    public let speaker: String
    /// Any annotation authored after the timestamp on the header line, kept
    /// verbatim including its brackets (e.g. "(interrupting)"). `nil` when
    /// there is none.
    public let parenthetical: String?
    /// The spoken text below the header line. May span multiple paragraphs
    /// (blank lines preserved); trimmed of surrounding blank lines.
    public let text: String

    public init(
        id: Int,
        startSeconds: Double,
        endSeconds: Double,
        speaker: String,
        parenthetical: String? = nil,
        text: String
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.speaker = speaker
        self.parenthetical = parenthetical
        self.text = text
    }
}

public extension Array where Element == TranscriptCue {
    /// The `id` of the cue active at `seconds` — the last cue whose
    /// `startSeconds` is `<= seconds`. `nil` only when `seconds` is before the
    /// first cue (or the transcript is empty). Binary search; assumes the
    /// array is start-ordered, which `TranscriptParser` guarantees.
    func activeCueID(at seconds: Double) -> Int? {
        guard let first, seconds >= first.startSeconds else {
            return nil
        }

        var low = 0
        var high = count - 1
        var result = first.id
        while low <= high {
            let mid = (low + high) / 2
            if self[mid].startSeconds <= seconds {
                result = self[mid].id
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
