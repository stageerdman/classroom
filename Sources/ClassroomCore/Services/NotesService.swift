import Foundation

public struct NotesService {
    /// Filename used when a lesson has no `.md` file yet and the user
    /// starts writing notes for the first time.
    public static let defaultNotesFileName = "Notes.md"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func noteURL(for lesson: Lesson) -> URL {
        lesson.notesURL ?? lesson.folderURL.appendingPathComponent(Self.defaultNotesFileName)
    }

    public func loadNotes(for lesson: Lesson) throws -> String {
        try loadNotes(at: noteURL(for: lesson))
    }

    public func loadNotes(at url: URL) throws -> String {
        guard fileManager.fileExists(atPath: url.path) else {
            return ""
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NotesServiceError.invalidUTF8(url.path)
        }

        return text
    }

    public func saveNotes(_ text: String, for lesson: Lesson) throws {
        try saveNotes(text, to: noteURL(for: lesson))
    }

    public func saveNotes(_ text: String, to url: URL) throws {
        let directoryURL = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let temporaryURL = directoryURL.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let data = Data(text.utf8)

        try data.write(to: temporaryURL, options: [.withoutOverwriting])

        do {
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}

public enum NotesServiceError: Error, Equatable {
    case invalidUTF8(String)
}
