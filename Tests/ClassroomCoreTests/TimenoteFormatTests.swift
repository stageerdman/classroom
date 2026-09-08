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

    func testMigratingLegacySyntaxRewritesOldTimenoteLines() {
        let legacy = "Intro\n> [!timenote 00:02:05.500] Key insight here\nOutro"
        let migrated = TimenoteFormat.migratingLegacySyntax(in: legacy)

        let lines = migrated.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Intro")
        XCTAssertEqual(lines[2], "Outro")

        let parsed = TimenoteFormat.parseLine(lines[1])
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.timestampSeconds ?? -1, 125.5, accuracy: 0.001)
        XCTAssertEqual(parsed?.text, "Key insight here")
    }

    func testMigratingLegacySyntaxIsIdempotentOnCurrentSyntax() {
        let current = TimenoteFormat.linePrefix(timestampSeconds: 42) + "Already current"
        XCTAssertEqual(TimenoteFormat.migratingLegacySyntax(in: current), current)
    }

    func testMigratingLegacySyntaxLeavesUnrelatedTextUnchanged() {
        let text = "Just a regular note.\n> A regular quote."
        XCTAssertEqual(TimenoteFormat.migratingLegacySyntax(in: text), text)
    }
}
#endif
