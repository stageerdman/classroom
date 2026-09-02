#if canImport(XCTest)
import XCTest
@testable import ClassroomCore

final class PageNoteScanningTests: XCTestCase {
    private let fileManager = FileManager.default

    func testExplicitPageAndNoteFilesAreResolvedByExactName() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        try write(lesson, ClassroomScanner.lessonMarkerFileName)
        try write(lesson, ClassroomScanner.pageFileName, contents: "Page content.")
        try write(lesson, ClassroomScanner.noteFileName, contents: "My notes.")

        let classroom = try scanClassroom(lesson)
        let resolvedLesson = try XCTUnwrap(classroom.modules.first?.directLessons.first)

        XCTAssertEqual(resolvedLesson.pageURL?.lastPathComponent, ClassroomScanner.pageFileName)
        XCTAssertEqual(resolvedLesson.noteURL?.lastPathComponent, ClassroomScanner.noteFileName)
        XCTAssertTrue(classroom.warnings.isEmpty)
    }

    func testLegacySingleMarkdownFileMigratesToPage() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        try write(lesson, ClassroomScanner.lessonMarkerFileName)
        try write(lesson, "Old Notes.md", contents: "Pre-split content.")

        let classroom = try scan(lesson)

        XCTAssertEqual(classroom.pageURL?.lastPathComponent, ClassroomScanner.pageFileName)
        XCTAssertNil(classroom.noteURL)
        XCTAssertFalse(fileManager.fileExists(atPath: lesson.appendingPathComponent("Old Notes.md").path))
        XCTAssertEqual(try String(contentsOf: classroom.pageURL!, encoding: .utf8), "Pre-split content.")
    }

    func testLegacyMigrationLeavesNoteFileUntouched() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        try write(lesson, ClassroomScanner.lessonMarkerFileName)
        try write(lesson, ClassroomScanner.noteFileName, contents: "My notes.")
        try write(lesson, "Old Notes.md", contents: "Pre-split content.")

        let classroom = try scan(lesson)

        XCTAssertEqual(classroom.pageURL?.lastPathComponent, ClassroomScanner.pageFileName)
        XCTAssertEqual(classroom.noteURL?.lastPathComponent, ClassroomScanner.noteFileName)
        XCTAssertEqual(try String(contentsOf: classroom.noteURL!, encoding: .utf8), "My notes.")
    }

    func testLeftoverMarkdownAfterPageAlreadyExistsIsWarnedNotTouched() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        try write(lesson, ClassroomScanner.lessonMarkerFileName)
        try write(lesson, ClassroomScanner.pageFileName, contents: "Page content.")
        try write(lesson, "Stray.md", contents: "Untouched.")

        let warning = try scanClassroom(lesson).warnings.first { $0.kind == .ambiguousLessonNotes }

        XCTAssertNotNil(warning)
        XCTAssertTrue(fileManager.fileExists(atPath: lesson.appendingPathComponent("Stray.md").path))
    }

    // MARK: - Helpers

    private func scan(_ lessonURL: URL) throws -> Lesson {
        let classroom = try scanClassroom(lessonURL)
        return try XCTUnwrap(classroom.modules.first?.directLessons.first)
    }

    private func scanClassroom(_ lessonURL: URL) throws -> Classroom {
        let rootURL = lessonURL.deletingLastPathComponent().deletingLastPathComponent()
        return ClassroomScanner().scan(rootURL: rootURL)
    }

    private func write(_ directory: URL, _ name: String, contents: String = "") throws {
        try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
    }

    private func makeTempDirectory() throws -> URL {
        // module/lesson nesting: ClassroomScanner treats the root's direct
        // children as modules and requires lessons one level below that.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PageNoteScanningTests")
            .appendingPathComponent(UUID().uuidString)
        let lesson = root.appendingPathComponent("Module").appendingPathComponent("Lesson")
        try fileManager.createDirectory(at: lesson, withIntermediateDirectories: true)
        return lesson
    }
}
#endif
