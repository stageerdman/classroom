#if canImport(XCTest)
import XCTest
@testable import ClassroomCore

final class TimenoteFormatTests: XCTestCase {
    func testFormatTimestampProducesZeroPaddedHoursMinutesSecondsMilliseconds() {
        XCTAssertEqual(TimenoteFormat.formatTimestamp(0), "00:00:00.000")
        XCTAssertEqual(TimenoteFormat.formatTimestamp(65.25), "00:01:05.250")
        XCTAssertEqual(TimenoteFormat.formatTimestamp(3661.5), "01:01:01.500")
    }

    func testFormatTimestampClampsNegativeToZero() {
        XCTAssertEqual(TimenoteFormat.formatTimestamp(-5), "00:00:00.000")
    }

    func testParseTimestampRoundTripsWithFormat() {
        for seconds in [0.0, 1.005, 65.25, 3661.5, 7199.999] {
            let timestamp = TimenoteFormat.formatTimestamp(seconds)
            let parsed = TimenoteFormat.parseTimestamp(timestamp)
            XCTAssertNotNil(parsed)
            XCTAssertEqual(parsed!, seconds, accuracy: 0.001)
        }
    }

    func testParseTimestampRejectsMalformedInput() {
        XCTAssertNil(TimenoteFormat.parseTimestamp("not a timestamp"))
        XCTAssertNil(TimenoteFormat.parseTimestamp("00:00"))
        XCTAssertNil(TimenoteFormat.parseTimestamp("00:00:00"))
    }

    func testLinePrefixAndParseLineRoundTrip() {
        let line = TimenoteFormat.linePrefix(timestampSeconds: 125.5) + "Key insight here"
        let parsed = TimenoteFormat.parseLine(line)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.timestampSeconds ?? -1, 125.5, accuracy: 0.001)
        XCTAssertEqual(parsed?.text, "Key insight here")
    }

    func testParseLineRejectsNonTimenoteLines() {
        XCTAssertNil(TimenoteFormat.parseLine("Just a regular note."))
        XCTAssertNil(TimenoteFormat.parseLine("> A regular quote."))
    }
}
#endif
