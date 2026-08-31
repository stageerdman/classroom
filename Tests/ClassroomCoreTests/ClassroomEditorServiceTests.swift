#if canImport(XCTest)
import XCTest
@testable import ClassroomCore

final class ClassroomEditorServiceTests: XCTestCase {
    private let service = ClassroomEditorService()
    private let fileManager = FileManager.default

    // MARK: Ghosts

    func testGhostEntriesExcludesKnownNamesAndSurfacesTheRest() throws {
        let folder = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: folder) }

        try write(folder, "Stray.pdf")
        try fileManager.createDirectory(at: folder.appendingPathComponent("Unmarked Folder"), withIntermediateDirectories: true)
        _ = try service.createCategory(in: folder, name: "Known Category")

        let ghosts = service.ghostEntries(in: folder, excludingNames: ["Known Category"])

        XCTAssertEqual(Set(ghosts.map(\.name)), ["Stray.pdf", "Unmarked Folder"])
        XCTAssertEqual(ghosts.first { $0.name == "Stray.pdf" }?.isDirectory, false)
        XCTAssertEqual(ghosts.first { $0.name == "Unmarked Folder" }?.isDirectory, true)
    }

    func testLessonGhostEntriesExcludesMediaNotesAttachmentsAndRemoved() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }

        let media = try write(lesson, "Video.mp4")
        let notes = try write(lesson, "Notes.md")
        try write(lesson, "Extra.mp4")
        try fileManager.createDirectory(at: lesson.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: lesson.appendingPathComponent("Removed"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: lesson.appendingPathComponent("Unexpected Folder"), withIntermediateDirectories: true)

        let ghosts = service.lessonGhostEntries(lessonFolderURL: lesson, mediaURL: media, notesURL: notes)

        XCTAssertEqual(Set(ghosts.map(\.name)), ["Extra.mp4", "Unexpected Folder"])
    }

    // MARK: Transform

    func testTransformAutoPicksSoleMediaAndNotesAndArchivesTheRest() throws {
        let folder = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: folder) }

        try write(folder, "Lesson.mp4")
        try write(folder, "Lesson.md")
        try write(folder, "Extra.pdf")

        try service.transformToLesson(folder)

        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent(ClassroomScanner.lessonMarkerFileName).path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Lesson.mp4").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Lesson.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Attachments/Extra.pdf").path))
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent("Extra.pdf").path))
    }

    func testTransformHonorsExplicitChoiceAmongAmbiguousCandidates() throws {
        let folder = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: folder) }

        try write(folder, "A.mp4")
        try write(folder, "B.mp4")

        let candidates = service.transformCandidates(for: folder)
        XCTAssertEqual(candidates.mediaFiles.count, 2)

        try service.transformToLesson(folder, chosenMedia: folder.appendingPathComponent("B.mp4"))

        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("B.mp4").path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Attachments/A.mp4").path))
    }

    func testTransformRejectedOnlyWhenSubfolderIsItselfARealLessonOrAlreadyALesson() throws {
        let withNestedLesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: withNestedLesson) }
        let nested = withNestedLesson.appendingPathComponent("Nested")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try write(nested, ClassroomScanner.lessonMarkerFileName)

        XCTAssertThrowsError(try service.transformToLesson(withNestedLesson)) { error in
            XCTAssertEqual(error as? ClassroomEditorService.EditorError, .hasSubfolders)
        }

        let alreadyLesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: alreadyLesson) }
        try write(alreadyLesson, ClassroomScanner.lessonMarkerFileName)

        XCTAssertThrowsError(try service.transformToLesson(alreadyLesson)) { error in
            XCTAssertEqual(error as? ClassroomEditorService.EditorError, .alreadyALesson)
        }
    }

    func testTransformAllowedWithAnUnmarkedOrAttachmentsSubfolder() throws {
        // A folder with a plain, unmarked subfolder (not a real lesson) is a
        // valid transform target — the subfolder is left alone and just
        // surfaces as a ghost inside the new lesson afterward.
        let withPlainSubfolder = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: withPlainSubfolder) }
        try write(withPlainSubfolder, "Intro.md")
        try fileManager.createDirectory(at: withPlainSubfolder.appendingPathComponent("Extras"), withIntermediateDirectories: true)

        XCTAssertNoThrow(try service.transformToLesson(withPlainSubfolder))
        XCTAssertTrue(fileManager.fileExists(atPath: withPlainSubfolder.appendingPathComponent(ClassroomScanner.lessonMarkerFileName).path))

        // An existing "Attachments" folder — e.g. pre-organized by hand in
        // Finder before the folder was ever a recognized lesson — is also a
        // valid transform target and is left untouched (it's already named
        // correctly for the scanner to pick up).
        let withAttachments = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: withAttachments) }
        try write(withAttachments, "Intro.md")
        let attachments = withAttachments.appendingPathComponent("Attachments")
        try fileManager.createDirectory(at: attachments, withIntermediateDirectories: true)
        try write(attachments, "Handout.pdf")

        XCTAssertNoThrow(try service.transformToLesson(withAttachments))
        XCTAssertTrue(fileManager.fileExists(atPath: attachments.appendingPathComponent("Handout.pdf").path))
    }

    // MARK: Create / rename / move

    func testCreateLessonAndCategoryValidateNames() throws {
        let parent = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: parent) }

        let lesson = try service.createLesson(in: parent, name: "  New Lesson  ")
        XCTAssertEqual(lesson.lastPathComponent, "New Lesson")
        XCTAssertTrue(fileManager.fileExists(atPath: lesson.appendingPathComponent(ClassroomScanner.lessonMarkerFileName).path))

        _ = try service.createCategory(in: parent, name: "Category")
        XCTAssertThrowsError(try service.createCategory(in: parent, name: "Category")) { error in
            XCTAssertEqual(error as? ClassroomEditorService.EditorError, .nameCollision)
        }
        XCTAssertThrowsError(try service.createCategory(in: parent, name: "   ")) { error in
            XCTAssertEqual(error as? ClassroomEditorService.EditorError, .emptyName)
        }
        XCTAssertThrowsError(try service.createCategory(in: parent, name: "Bad/Name")) { error in
            XCTAssertEqual(error as? ClassroomEditorService.EditorError, .invalidCharacters)
        }
    }

    func testRenameRejectsCollisionAndMovesOnDisk() throws {
        let parent = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: parent) }

        let a = try service.createCategory(in: parent, name: "A")
        _ = try service.createCategory(in: parent, name: "B")

        XCTAssertThrowsError(try service.rename(a, to: "B")) { error in
            XCTAssertEqual(error as? ClassroomEditorService.EditorError, .nameCollision)
        }

        let renamed = try service.rename(a, to: "C")
        XCTAssertEqual(renamed.lastPathComponent, "C")
        XCTAssertFalse(fileManager.fileExists(atPath: a.path))
        XCTAssertTrue(fileManager.fileExists(atPath: renamed.path))
    }

    func testMoveRejectsCollisionAtDestination() throws {
        let parent = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: parent) }

        let categoryA = try service.createCategory(in: parent, name: "CategoryA")
        let categoryB = try service.createCategory(in: parent, name: "CategoryB")
        let lesson = try service.createLesson(in: categoryA, name: "Lesson")
        _ = try service.createLesson(in: categoryB, name: "Lesson")

        XCTAssertThrowsError(try service.move(lesson, into: categoryB)) { error in
            XCTAssertEqual(error as? ClassroomEditorService.EditorError, .nameCollision)
        }

        let categoryC = try service.createCategory(in: parent, name: "CategoryC")
        let moved = try service.move(lesson, into: categoryC)
        XCTAssertFalse(fileManager.fileExists(atPath: lesson.path))
        XCTAssertTrue(fileManager.fileExists(atPath: moved.path))
    }

    // MARK: Trash / restore (undo support)

    func testTrashReturnsTheResultingLocationAndRestoreMovesItBackExactly() throws {
        let parent = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: parent) }

        let lesson = try service.createLesson(in: parent, name: "Lesson")
        let trashedURL = try service.trash(lesson)

        XCTAssertFalse(fileManager.fileExists(atPath: lesson.path))
        XCTAssertTrue(fileManager.fileExists(atPath: trashedURL.path))

        try service.restore(trashedURL, to: lesson)
        XCTAssertTrue(fileManager.fileExists(atPath: lesson.path))
        XCTAssertFalse(fileManager.fileExists(atPath: trashedURL.path))
    }

    func testRestoreRejectsCollisionAtDestination() throws {
        let parent = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: parent) }

        let lesson = try service.createLesson(in: parent, name: "Lesson")
        let trashedURL = try service.trash(lesson)
        _ = try service.createLesson(in: parent, name: "Lesson") // something new now occupies the original spot

        XCTAssertThrowsError(try service.restore(trashedURL, to: lesson)) { error in
            XCTAssertEqual(error as? ClassroomEditorService.EditorError, .nameCollision)
        }
    }

    // MARK: Undo support — transform

    func testUndoTransformToLessonRestoresArchivedFilesAndRemovesTheMarker() throws {
        let folder = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: folder) }

        try write(folder, "Lesson.mp4")
        try write(folder, "Extra.pdf")

        let result = try service.transformToLesson(folder)
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent(ClassroomScanner.lessonMarkerFileName).path))
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Attachments/Extra.pdf").path))

        try service.undoTransformToLesson(folder, result: result)

        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent(ClassroomScanner.lessonMarkerFileName).path), "Marker should be gone")
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Extra.pdf").path), "Archived file should move back to the folder root")
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent("Attachments").path), "The freshly-created Attachments folder should be removed once emptied")
        XCTAssertTrue(fileManager.fileExists(atPath: folder.appendingPathComponent("Lesson.mp4").path), "The chosen media, which never moved, should still be there")
    }

    func testUndoTransformToLessonKeepsAPreExistingAttachmentsFolder() throws {
        let folder = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: folder) }

        try write(folder, "Lesson.mp4")
        let attachments = folder.appendingPathComponent("Attachments")
        try fileManager.createDirectory(at: attachments, withIntermediateDirectories: true)
        try write(attachments, "PreExisting.pdf")

        let result = try service.transformToLesson(folder)
        try service.undoTransformToLesson(folder, result: result)

        XCTAssertTrue(fileManager.fileExists(atPath: attachments.appendingPathComponent("PreExisting.pdf").path), "A pre-existing Attachments folder (not created by the transform) should survive undo")
    }

    // MARK: Import / attachments

    func testImportMovesSourceAndDisambiguatesNameCollisions() throws {
        let source = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: source) }
        let destination = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: destination) }

        let file1 = try write(source, "Handout.pdf")
        let imported1 = try service.importFile(file1, into: destination)
        XCTAssertEqual(imported1.lastPathComponent, "Handout.pdf")
        XCTAssertFalse(fileManager.fileExists(atPath: file1.path), "Import must move, not copy")

        let file2 = try write(source, "Handout.pdf")
        let imported2 = try service.importFile(file2, into: destination)
        XCTAssertEqual(imported2.lastPathComponent, "Handout 2.pdf", "Colliding import should be disambiguated, not overwritten")
    }

    func testRemoveAttachmentMovesToRemovedFolderRatherThanDeleting() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }
        let attachment = try service.addAttachment(lessonFolderURL: lesson, fileURL: try write(try makeTempDirectory(), "Notes.pdf"))

        try service.removeAttachment(lessonFolderURL: lesson, attachmentURL: attachment)

        XCTAssertFalse(fileManager.fileExists(atPath: attachment.path))
        XCTAssertTrue(fileManager.fileExists(atPath: lesson.appendingPathComponent("Removed/Notes.pdf").path))
    }

    func testReplaceHeroMediaDemotesOldMediaIntoAttachments() throws {
        let lesson = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: lesson) }
        try write(lesson, "Old.mp4")

        let newSource = try makeTempDirectory()
        let newMedia = try write(newSource, "New.mp4")

        try service.replaceHeroMedia(lessonFolderURL: lesson, newMediaURL: newMedia)

        XCTAssertTrue(fileManager.fileExists(atPath: lesson.appendingPathComponent("New.mp4").path))
        XCTAssertTrue(fileManager.fileExists(atPath: lesson.appendingPathComponent("Attachments/Old.mp4").path))
        XCTAssertFalse(fileManager.fileExists(atPath: lesson.appendingPathComponent("Old.mp4").path))
    }

    func testNotesLinkMarkdownDoesNotTouchTheFilesystem() throws {
        let folder = try makeTempDirectory()
        defer { try? fileManager.removeItem(at: folder) }
        let file = try write(folder, "Reference.pdf")

        let markdown = service.notesLinkMarkdown(for: file)

        XCTAssertTrue(markdown.hasPrefix("[Reference.pdf]("))
        XCTAssertTrue(fileManager.fileExists(atPath: file.path), "Inserting a notes link must never move the source file")
    }

    // MARK: Helpers

    @discardableResult
    private func write(_ directory: URL, _ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    private func makeTempDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("ClassroomEditorServiceTests")
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
#endif
