#if canImport(XCTest)
import XCTest
@testable import ClassroomCore

final class ModuleFileTreeScannerTests: XCTestCase {
    func testTreeSurfacesAttachmentsAndRemovedFoldersAsOrdinaryNodes() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let moduleURL = root.appendingPathComponent("Module", isDirectory: true)
        let lessonURL = moduleURL.appendingPathComponent("Lesson", isDirectory: true)
        try FileManager.default.createDirectory(at: lessonURL, withIntermediateDirectories: true)
        try Data().write(to: lessonURL.appendingPathComponent(ClassroomScanner.lessonMarkerFileName))
        try Data().write(to: lessonURL.appendingPathComponent("Lesson.mp4"))
        try FileManager.default.createDirectory(
            at: lessonURL.appendingPathComponent("Attachments", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: lessonURL.appendingPathComponent("Attachments/Handout.pdf"))
        try FileManager.default.createDirectory(
            at: lessonURL.appendingPathComponent("Removed", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: lessonURL.appendingPathComponent("Removed/OldHandout.pdf"))

        let nodes = ModuleFileTreeScanner().scan(moduleURL: moduleURL, rootURL: root)

        let lessonNode = try XCTUnwrap(nodes.first { $0.name == "Lesson" })
        XCTAssertTrue(lessonNode.isLessonFolder)
        XCTAssertFalse(lessonNode.children.contains { $0.name == ClassroomScanner.lessonMarkerFileName }, "The marker file itself must never appear as a node")

        let childNames = Set(lessonNode.children.map(\.name))
        XCTAssertTrue(childNames.contains("Attachments"))
        XCTAssertTrue(childNames.contains("Removed"))
        XCTAssertTrue(childNames.contains("Lesson.mp4"))

        let attachmentsNode = try XCTUnwrap(lessonNode.children.first { $0.name == "Attachments" })
        XCTAssertEqual(attachmentsNode.children.map(\.name), ["Handout.pdf"])
        let removedNode = try XCTUnwrap(lessonNode.children.first { $0.name == "Removed" })
        XCTAssertEqual(removedNode.children.map(\.name), ["OldHandout.pdf"])

        XCTAssertEqual(lessonNode.structuralKind, .lesson)
        XCTAssertNil(attachmentsNode.structuralKind, "Attachments is not a tracked classroom node")
        XCTAssertNil(removedNode.structuralKind, "Removed is not a tracked classroom node")
    }

    func testNestedLessonUnderCategoryIsTrackedButItsContentsAreNot() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let moduleURL = root.appendingPathComponent("Module", isDirectory: true)
        let lessonURL = moduleURL.appendingPathComponent("Category/Lesson", isDirectory: true)
        try FileManager.default.createDirectory(at: lessonURL, withIntermediateDirectories: true)
        try Data().write(to: lessonURL.appendingPathComponent(ClassroomScanner.lessonMarkerFileName))
        try FileManager.default.createDirectory(
            at: lessonURL.appendingPathComponent("Loose Untransformed", isDirectory: true),
            withIntermediateDirectories: true
        )

        let nodes = ModuleFileTreeScanner().scan(moduleURL: moduleURL, rootURL: root)
        let categoryNode = try XCTUnwrap(nodes.first { $0.name == "Category" })
        XCTAssertEqual(categoryNode.structuralKind, .category)

        let lessonNode = try XCTUnwrap(categoryNode.children.first { $0.name == "Lesson" })
        XCTAssertEqual(lessonNode.structuralKind, .lesson)

        let looseNode = try XCTUnwrap(lessonNode.children.first { $0.name == "Loose Untransformed" })
        XCTAssertNil(looseNode.structuralKind, "A folder nested inside a lesson is never a tracked classroom node, even if unclassified")
    }

    func testPlainFolderIsNotFlaggedAsLesson() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let moduleURL = root.appendingPathComponent("Module", isDirectory: true)
        try FileManager.default.createDirectory(
            at: moduleURL.appendingPathComponent("Category", isDirectory: true),
            withIntermediateDirectories: true
        )

        let nodes = ModuleFileTreeScanner().scan(moduleURL: moduleURL, rootURL: root)
        XCTAssertEqual(nodes.first { $0.name == "Category" }?.isLessonFolder, false)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModuleFileTreeScannerTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
#endif
