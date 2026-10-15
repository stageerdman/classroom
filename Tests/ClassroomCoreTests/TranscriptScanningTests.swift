#if canImport(XCTest)
import XCTest
@testable import ClassroomCore

final class TranscriptScanningTests: XCTestCase {
    private let fileManager = FileManager.default

    func testMarkdownNamedLikeTheVideoIsDiscoveredAsTranscript() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        try write(lesson, ClassroomScanner.lessonMarkerFileName)
        try write(lesson, "call.mp4", contents: "")
        try write(lesson, "call.md", contents: "**A** [00:01]\nHi.")

        let (resolved, classroom) = try scan(lesson)

        XCTAssertEqual(resolved.transcriptURL?.lastPathComponent, "call.md")
        XCTAssertNil(resolved.pageURL, "A transcript must not be adopted as the Page.")
        XCTAssertNil(resolved.noteURL)
        XCTAssertTrue(classroom.warnings.isEmpty, "A transcript sidecar is expected, not a stray file.")
    }

    func testTranscriptIsNotMigratedIntoPage() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        try write(lesson, ClassroomScanner.lessonMarkerFileName)
        try write(lesson, "call.mov", contents: "")
        try write(lesson, "call.md", contents: "transcript body")

        let (resolved, _) = try scan(lesson)

        // The legacy-markdown-to-page migration must leave the transcript alone.
        XCTAssertFalse(fileManager.fileExists(atPath: lesson.appendingPathComponent(ClassroomScanner.pageFileName).path))
        XCTAssertTrue(fileManager.fileExists(atPath: lesson.appendingPathComponent("call.md").path))
        XCTAssertEqual(resolved.transcriptURL?.lastPathComponent, "call.md")
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(resolved.transcriptURL), encoding: .utf8), "transcript body")
    }

    func testTranscriptCoexistsWithExplicitPageAndNote() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        try write(lesson, ClassroomScanner.lessonMarkerFileName)
        try write(lesson, "call.mp4", contents: "")
        try write(lesson, "call.md", contents: "transcript")
        try write(lesson, ClassroomScanner.pageFileName, contents: "page")
        try write(lesson, ClassroomScanner.noteFileName, contents: "notes")

        let (resolved, classroom) = try scan(lesson)

        XCTAssertEqual(resolved.transcriptURL?.lastPathComponent, "call.md")
        XCTAssertEqual(resolved.pageURL?.lastPathComponent, ClassroomScanner.pageFileName)
        XCTAssertEqual(resolved.noteURL?.lastPathComponent, ClassroomScanner.noteFileName)
        XCTAssertTrue(classroom.warnings.isEmpty)
    }

    func testMarkdownNotMatchingTheVideoNameIsNotATranscript() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        try write(lesson, ClassroomScanner.lessonMarkerFileName)
        try write(lesson, "call.mp4", contents: "")
        try write(lesson, "Other.md", contents: "not a transcript")

        let (resolved, _) = try scan(lesson)

        // Unrelated markdown keeps its existing behavior: migrates to page.md.
        XCTAssertNil(resolved.transcriptURL)
        XCTAssertEqual(resolved.pageURL?.lastPathComponent, ClassroomScanner.pageFileName)
    }

    func testVideoNamedPageDoesNotHijackPageMarkdownAsTranscript() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        try write(lesson, ClassroomScanner.lessonMarkerFileName)
        try write(lesson, "page.mp4", contents: "")
        try write(lesson, ClassroomScanner.pageFileName, contents: "authored page")

        let (resolved, _) = try scan(lesson)

        XCTAssertNil(resolved.transcriptURL, "page.md is the authored Page, never a transcript.")
        XCTAssertEqual(resolved.pageURL?.lastPathComponent, ClassroomScanner.pageFileName)
    }

    func testTranscriptMatchIsCaseInsensitive() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        try write(lesson, ClassroomScanner.lessonMarkerFileName)
        try write(lesson, "Call.MP4", contents: "")
        try write(lesson, "call.md", contents: "transcript")

        let (resolved, _) = try scan(lesson)

        XCTAssertEqual(resolved.transcriptURL?.lastPathComponent, "call.md")
    }

    func testLessonWithoutTranscriptHasNilTranscriptURL() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        try write(lesson, ClassroomScanner.lessonMarkerFileName)
        try write(lesson, "call.mp4", contents: "")

        let (resolved, _) = try scan(lesson)

        XCTAssertNil(resolved.transcriptURL)
    }

    // MARK: - Helpers

    private func scan(_ lessonURL: URL) throws -> (Lesson, Classroom) {
        let rootURL = lessonURL.deletingLastPathComponent().deletingLastPathComponent()
        let classroom = ClassroomScanner().scan(rootURL: rootURL)
        let lesson = try XCTUnwrap(classroom.modules.first?.directLessons.first)
        return (lesson, classroom)
    }

    private func write(_ directory: URL, _ name: String, contents: String = "") throws {
        try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
    }

    private func makeTempDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptScanningTests")
            .appendingPathComponent(UUID().uuidString)
        let lesson = root.appendingPathComponent("Module").appendingPathComponent("Lesson")
        try fileManager.createDirectory(at: lesson, withIntermediateDirectories: true)
        return lesson
    }
}
#endif
