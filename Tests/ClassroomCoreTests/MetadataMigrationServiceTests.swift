#if canImport(XCTest)
import XCTest
@testable import ClassroomCore

final class MetadataMigrationServiceTests: XCTestCase {
    func testLessonRenameInPlacePreservesStateAndOrderPosition() {
        var metadata = ClassroomMetadata()
        metadata.lessonState["Module/Category/OldName"] = LessonState(playbackPositionSeconds: 42, completed: true)
        metadata.lessonOrder["Module/Category"] = ["Other", "OldName"]

        let migrated = MetadataMigrationService.migrate(
            metadata,
            kind: .lesson,
            oldPath: "Module/Category/OldName",
            newPath: "Module/Category/NewName"
        )

        XCTAssertNil(migrated.lessonState["Module/Category/OldName"])
        XCTAssertEqual(migrated.lessonState["Module/Category/NewName"]?.playbackPositionSeconds, 42)
        XCTAssertEqual(migrated.lessonState["Module/Category/NewName"]?.completed, true)
        XCTAssertEqual(migrated.lessonOrder["Module/Category"], ["Other", "NewName"])
    }

    func testLessonMoveToDifferentParentDropsStaleOrderAndKeepsState() {
        var metadata = ClassroomMetadata()
        metadata.lessonState["Module/CategoryA/Lesson"] = LessonState(completed: true)
        metadata.lessonOrder["Module/CategoryA"] = ["Lesson", "Other"]
        metadata.lessonOrder["Module/CategoryB"] = ["Existing"]

        let migrated = MetadataMigrationService.migrate(
            metadata,
            kind: .lesson,
            oldPath: "Module/CategoryA/Lesson",
            newPath: "Module/CategoryB/Lesson"
        )

        XCTAssertNil(migrated.lessonState["Module/CategoryA/Lesson"])
        XCTAssertEqual(migrated.lessonState["Module/CategoryB/Lesson"]?.completed, true)
        XCTAssertEqual(migrated.lessonOrder["Module/CategoryA"], ["Other"])
        XCTAssertEqual(migrated.lessonOrder["Module/CategoryB"], ["Existing"], "Move should not insert into the new parent's saved order; it appends naturally on next scan")
    }

    func testCategoryRenameCascadesToContainedLessonsAndItsOwnOrderKey() {
        var metadata = ClassroomMetadata()
        metadata.lessonState["Module/OldCategory/Lesson1"] = LessonState(completed: true)
        metadata.lessonState["Module/OldCategory/Lesson2"] = LessonState(playbackPositionSeconds: 10)
        metadata.lessonOrder["Module/OldCategory"] = ["Lesson2", "Lesson1"]
        metadata.categoryOrder["Module"] = ["OldCategory", "Other"]

        let migrated = MetadataMigrationService.migrate(
            metadata,
            kind: .category,
            oldPath: "Module/OldCategory",
            newPath: "Module/NewCategory"
        )

        XCTAssertNil(migrated.lessonState["Module/OldCategory/Lesson1"])
        XCTAssertEqual(migrated.lessonState["Module/NewCategory/Lesson1"]?.completed, true)
        XCTAssertEqual(migrated.lessonState["Module/NewCategory/Lesson2"]?.playbackPositionSeconds, 10)
        XCTAssertNil(migrated.lessonOrder["Module/OldCategory"])
        XCTAssertEqual(migrated.lessonOrder["Module/NewCategory"], ["Lesson2", "Lesson1"])
        XCTAssertEqual(migrated.categoryOrder["Module"], ["NewCategory", "Other"])
    }

    func testModuleRenameCascadesEverywhere() {
        var metadata = ClassroomMetadata()
        metadata.moduleOrder = ["OldModule", "Other"]
        metadata.categoryOrder["OldModule"] = ["CategoryA"]
        metadata.lessonOrder["OldModule"] = ["DirectLesson"]
        metadata.lessonOrder["OldModule/CategoryA"] = ["Lesson1"]
        metadata.lessonState["OldModule/DirectLesson"] = LessonState(completed: true)
        metadata.lessonState["OldModule/CategoryA/Lesson1"] = LessonState(playbackPositionSeconds: 5)

        let migrated = MetadataMigrationService.migrate(
            metadata,
            kind: .module,
            oldPath: "OldModule",
            newPath: "NewModule"
        )

        XCTAssertEqual(migrated.moduleOrder, ["NewModule", "Other"])
        XCTAssertNil(migrated.categoryOrder["OldModule"])
        XCTAssertEqual(migrated.categoryOrder["NewModule"], ["CategoryA"])
        XCTAssertEqual(migrated.lessonOrder["NewModule"], ["DirectLesson"])
        XCTAssertEqual(migrated.lessonOrder["NewModule/CategoryA"], ["Lesson1"])
        XCTAssertEqual(migrated.lessonState["NewModule/DirectLesson"]?.completed, true)
        XCTAssertEqual(migrated.lessonState["NewModule/CategoryA/Lesson1"]?.playbackPositionSeconds, 5)
    }
}
#endif
