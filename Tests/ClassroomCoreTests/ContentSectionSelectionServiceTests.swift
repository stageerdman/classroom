#if canImport(XCTest)
import XCTest
@testable import ClassroomCore

final class ContentSectionSelectionServiceTests: XCTestCase {
    func testSelectingAnUnselectedSectionAddsIt() {
        let updated = ContentSectionSelectionService.toggling(.notes, in: [.page])
        XCTAssertEqual(updated, [.page, .notes])
    }

    // The "drop the oldest selection once already at the cap" branch in
    // `toggling` only fires when a *third*, unselected section is tapped
    // while two are already selected — untestable with the real
    // `LessonContentSection` today, since it only has two cases. Revisit
    // once a third section (e.g. Files) exists.

    func testDeselectingOneOfTwoLeavesTheOther() {
        let updated = ContentSectionSelectionService.toggling(.page, in: [.page, .notes])
        XCTAssertEqual(updated, [.notes])
    }

    func testDeselectingTheOnlySelectedSectionIsANoOp() {
        let updated = ContentSectionSelectionService.toggling(.page, in: [.page])
        XCTAssertEqual(updated, [.page])
    }
}
#endif
