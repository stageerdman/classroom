import Foundation

/// Load/save for a lesson's `page.md` — authored lesson content, editable
/// only while the containing Module is in edit mode (enforced by the UI,
/// not here).
public struct PageService {
    public static let defaultPageFileName = ClassroomScanner.pageFileName

    private let markdownFileService: MarkdownFileService

    public init(markdownFileService: MarkdownFileService = MarkdownFileService()) {
        self.markdownFileService = markdownFileService
    }

    public func pageURL(for lesson: Lesson) -> URL {
        lesson.pageURL ?? lesson.folderURL.appendingPathComponent(Self.defaultPageFileName)
    }

    public func loadPage(for lesson: Lesson) throws -> String {
        try markdownFileService.load(at: pageURL(for: lesson))
    }

    public func savePage(_ text: String, for lesson: Lesson) throws {
        try markdownFileService.save(text, to: pageURL(for: lesson))
    }
}
