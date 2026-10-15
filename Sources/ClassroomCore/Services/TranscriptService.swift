import Foundation

/// Loads a lesson's transcript sidecar (`<video>.md`) and parses it into
/// cues. Read-only — the transcript is an imported artifact, never edited in
/// the app (mirrors `NotesService`'s shape, without the save side).
public struct TranscriptService {
    private let markdownFileService: MarkdownFileService

    public init(markdownFileService: MarkdownFileService = MarkdownFileService()) {
        self.markdownFileService = markdownFileService
    }

    /// The parsed cues for `lesson`, or `[]` if the lesson has no transcript.
    /// Throws only if a transcript file exists but can't be read.
    public func loadCues(for lesson: Lesson) throws -> [TranscriptCue] {
        guard let transcriptURL = lesson.transcriptURL else {
            return []
        }
        return TranscriptParser.parse(try markdownFileService.load(at: transcriptURL))
    }
}
