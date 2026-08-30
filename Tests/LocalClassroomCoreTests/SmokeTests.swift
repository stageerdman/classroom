#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
@testable import LocalClassroomCore

#if canImport(XCTest)
final class SmokeTests: XCTestCase {
    func testAppInfoHasDisplayName() {
        XCTAssertEqual(AppInfo.displayName, "Local Classroom")
    }

    func testLessonFolderRequiresMarkerFile() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(root, "Module/Unmarked", marker: false, media: "Unmarked.mp4")
        try write(root, "Module/Marked", marker: true, media: "Marked.mp4")

        let classroom = ClassroomScanner().scan(rootURL: root)
        let module = try XCTUnwrap(classroom.modules.first)

        XCTAssertEqual(module.directLessons.map(\.title), ["Marked"])
        XCTAssertEqual(module.categories.map(\.name), ["Unmarked"])
    }

    func testLessonMediaAndNotesAreIndependentlyOptional() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(root, "Module/NotesOnly", marker: true, media: nil, notes: "Just text.")

        let classroom = ClassroomScanner().scan(rootURL: root)
        let lesson = try XCTUnwrap(classroom.modules.first?.directLessons.first)

        XCTAssertNil(lesson.mediaURL)
        XCTAssertEqual(lesson.notesURL?.lastPathComponent, "Notes.md")
    }

    func testModuleDescriptionReadFromDescriptionFile() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Module", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("What this module covers.".utf8).write(
            to: root.appendingPathComponent("Module/description.md")
        )
        try write(root, "Module/Lesson", marker: true, media: "Lesson.mp4")

        let classroom = ClassroomScanner().scan(rootURL: root)
        XCTAssertEqual(classroom.modules.first?.description, "What this module covers.")
    }

    func testAttachmentsOnlyExposedWhenNonEmpty() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(root, "Module/WithAttachments", marker: true, media: "Lesson.mp4")
        try Data().write(
            to: root.appendingPathComponent("Module/WithAttachments/Attachments/Handout.pdf")
        )

        try write(root, "Module/EmptyAttachments", marker: true, media: "Lesson.mp4")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Module/EmptyAttachments/Attachments", isDirectory: true),
            withIntermediateDirectories: true
        )

        let classroom = ClassroomScanner().scan(rootURL: root)
        let lessons = Dictionary(uniqueKeysWithValues: (classroom.modules.first?.directLessons ?? []).map { ($0.title, $0) })

        XCTAssertEqual(lessons["WithAttachments"]?.attachmentURLs.map(\.lastPathComponent), ["Handout.pdf"])
        XCTAssertEqual(lessons["EmptyAttachments"]?.attachmentURLs, [])
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalClassroomCoreTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(
        _ root: URL,
        _ relativePath: String,
        marker: Bool,
        media: String?,
        notes: String? = nil
    ) throws {
        let folderURL = root.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        if marker {
            try Data().write(to: folderURL.appendingPathComponent(ClassroomScanner.lessonMarkerFileName))
        }
        if let media {
            try Data().write(to: folderURL.appendingPathComponent(media))
        }
        if let notes {
            try Data(notes.utf8).write(to: folderURL.appendingPathComponent(NotesService.defaultNotesFileName))
        }
    }
}
#else
func smokeTestAppInfoHasDisplayName() {
    precondition(AppInfo.displayName == "Local Classroom")
}

func smokeTestPhaseFoldersAreReachable() {
    precondition(ClassroomScanner().scan(rootURL: URL(fileURLWithPath: "/path/that/does/not/exist")).warnings.count == 1)
}
#endif
