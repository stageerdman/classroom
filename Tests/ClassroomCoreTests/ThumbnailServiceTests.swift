#if canImport(XCTest)
import XCTest
@testable import ClassroomCore

final class ThumbnailServiceTests: XCTestCase {
    func testSampleTimesStartsAtZeroAndStaysWithinDuration() {
        let times = ThumbnailService.sampleTimes(duration: 120, interval: 10, maxCount: 60)

        XCTAssertEqual(times.first, 0)
        XCTAssertTrue(times.allSatisfy { $0 >= 0 && $0 < 120 })
        XCTAssertEqual(times, times.sorted())
    }

    func testSampleTimesRespectsMaxCountForLongVideos() {
        let times = ThumbnailService.sampleTimes(duration: 10_000, interval: 10, maxCount: 60)
        XCTAssertEqual(times.count, 60)
    }

    func testSampleTimesGuaranteesAMinimumSpreadForShortVideos() {
        let times = ThumbnailService.sampleTimes(duration: 3, interval: 10, maxCount: 60)
        XCTAssertEqual(times.count, 4)
    }

    func testSampleTimesIsEmptyForZeroOrNegativeDuration() {
        XCTAssertEqual(ThumbnailService.sampleTimes(duration: 0), [])
        XCTAssertEqual(ThumbnailService.sampleTimes(duration: -5), [])
    }
}
#endif
