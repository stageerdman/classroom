import Foundation

/// Generic atomic load/save for a single Markdown file at an explicit URL.
/// `PageService` and `NotesService` are thin, lesson-aware wrappers around
/// this; it's also used directly for files with no per-lesson URL of their
/// own (e.g. a module's `description.md`).
public struct MarkdownFileService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(at url: URL) throws -> String {
        guard fileManager.fileExists(atPath: url.path) else {
            return ""
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MarkdownFileServiceError.invalidUTF8(url.path)
        }

        return text
    }

    public func save(_ text: String, to url: URL) throws {
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

public enum MarkdownFileServiceError: Error, Equatable {
    case invalidUTF8(String)
}
