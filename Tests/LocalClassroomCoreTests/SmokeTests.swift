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

    func testPhaseFoldersAreReachable() {
        XCTAssertEqual(ModelNamespace.phase, 0)
        XCTAssertEqual(ServiceNamespace.phase, 0)
        XCTAssertEqual(ViewModelNamespace.phase, 0)
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
