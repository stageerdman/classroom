import Foundation

/// Load/save for a lesson's `note.md` — the viewer's own running notes,
/// always editable regardless of Module edit mode.
public struct NotesService {
    public static let defaultNotesFileName = ClassroomScanner.noteFileName

    private let markdownFileService: MarkdownFileService

    public init(markdownFileService: MarkdownFileService = MarkdownFileService()) {
        self.markdownFileService = markdownFileService
    }

    public func noteURL(for lesson: Lesson) -> URL {
        lesson.noteURL ?? lesson.folderURL.appendingPathComponent(Self.defaultNotesFileName)
    }

    public func loadNotes(for lesson: Lesson) throws -> String {
        try markdownFileService.load(at: noteURL(for: lesson))
    }

    public func saveNotes(_ text: String, for lesson: Lesson) throws {
        try markdownFileService.save(text, to: noteURL(for: lesson))
    }
}
